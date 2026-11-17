using CapsuleApi.Models;
using CapsuleApi.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader());
});

builder.Services.AddSingleton<SpatialCryptoService>();
builder.Services.AddSingleton<CapsuleRepository>();
builder.Services.AddSingleton<SpatialIndexEngine>();
builder.Services.AddSingleton<AntiSpoofingEngine>();
builder.Services.AddSingleton<VisualPositioningService>();
builder.Services.AddHttpClient<WikimediaMediaService>();

var app = builder.Build();

app.UseCors();

app.MapGet("/", () => Results.Ok(new
{
    service = "KapsülAR - Hibrit Konum Doğrulamalı WebAR Zaman Kapsülü API",
    version = "1.0.0",
    endpoints = new[]
    {
        "GET /api/health",
        "GET /api/capsules?lat=41.0122&lon=28.9635&radiusMeters=10000",
        "POST /api/capsules",
        "POST /api/capsules/unlock",
        "POST /api/antispoof/evaluate",
        "GET /api/spatial/benchmark?count=10000&radius=5",
        "GET /api/media/nearby?lat=41.0122&lon=28.9635&q=istanbul",
        "POST /api/activity",
        "GET /api/experiments/summary",
        "POST /api/experiments/sus-tam",
        "GET /api/routes?lat=41.0122&lon=28.9635",
        "GET /api/routes/suggest?lat=41.0122&lon=28.9635",
        "POST /api/routes",
        "POST /api/routes/{id}/rate",
        "POST /api/routes/{id}/complete",
        "POST /api/experiments/wellbeing"
    }
}));

app.MapGet("/api/health", () => Results.Ok(new
{
    status = "healthy",
    timestamp = DateTimeOffset.UtcNow
}));

app.MapGet("/api/capsules", (
    double? lat,
    double? lon,
    double? radiusMeters,
    string? category,
    CapsuleRepository repo,
    SpatialIndexEngine spatial) =>
{
    double qLat = lat ?? 41.0122;
    double qLon = lon ?? 28.9635;
    double maxR = radiusMeters ?? 50000;

    var all = repo.GetAllCapsules();
    if (!string.IsNullOrWhiteSpace(category) && category != "Tümü")
    {
        all = all.Where(c => c.Category.Equals(category, StringComparison.OrdinalIgnoreCase)).ToList();
    }

    var nearby = spatial.QueryNearbyCapsules(all, qLat, qLon, maxR);
    // Kullanıcının gerçek konumu İstanbul Beyazıt dışındaysa çevresinde hemen keşfedebileceği yerel kapsüller oluştur
    if (!nearby.Any(x => x.DistanceMeters <= 1200.0) && (string.IsNullOrWhiteSpace(category) || category == "Tümü"))
    {
        var localCapsules = repo.EnsureLocalDiscoveryCapsules(qLat, qLon);
        all = repo.GetAllCapsules();
        nearby = spatial.QueryNearbyCapsules(all, qLat, qLon, maxR);
    }
    var response = nearby.Select(x =>
    {
        var c = x.Capsule;
        bool inUnlockRange = x.DistanceMeters <= c.UnlockRadiusMeters;
        bool inArRange = x.DistanceMeters <= c.ArTriggerRadiusMeters;
        return new
        {
            c.Id,
            c.Title,
            c.Description,
            c.Category,
            c.ContentType,
            c.Latitude,
            c.Longitude,
            c.UnlockRadiusMeters,
            c.ArTriggerRadiusMeters,
            c.LocationName,
            c.ImageUrl,
            c.VisualSignature,
            c.AnchorHeadingDeg,
            SpatialSealHash = string.IsNullOrWhiteSpace(c.SpatialSealHash)
                ? c.Geohash.ToUpperInvariant()
                : c.SpatialSealHash,
            c.IsEncrypted,
            c.PasscodeHint,
            c.CreatedBy,
            c.CreatedAt,
            c.UnlockCount,
            c.Geohash,
            DistanceMeters = x.DistanceMeters,
            InArRange = inArRange,
            InUnlockRange = inUnlockRange,
            // Preview metadata is public; full locked note/pixel/audio reveals cleanly on unlock (or if unlocked/not encrypted)
            NoteText = c.IsEncrypted ? null : c.NoteText,
            PixelArtGrid = c.PixelArtGrid,
            AudioDurationSec = c.AudioDurationSec,
            AudioWaveform = c.AudioWaveform
        };
    });

    return Results.Ok(response);
});

app.MapGet("/api/capsules/{id}", (string id, CapsuleRepository repo) =>
{
    var c = repo.GetById(id);
    return c is null ? Results.NotFound(new { message = "Kapsül bulunamadı." }) : Results.Ok(c);
});

app.MapPost("/api/capsules", (CreateCapsuleRequest req, CapsuleRepository repo) =>
{
    if (string.IsNullOrWhiteSpace(req.Title))
        return Results.BadRequest(new { message = "Kapsül başlığı zorunludur." });

    var created = repo.AddCapsule(req);
    return Results.Created($"/api/capsules/{created.Id}", created);
});

app.MapPost("/api/capsules/unlock", (
    UnlockAttemptRequest req,
    CapsuleRepository repo,
    AntiSpoofingEngine antiSpoof,
    VisualPositioningService visual,
    SpatialCryptoService crypto) =>
{
    var capsule = repo.GetById(req.CapsuleId);
    if (capsule is null)
        return Results.NotFound(new { message = "Kapsül bulunamadı." });

    var antiReport = antiSpoof.Evaluate(req.TelemetryWindow);
    repo.RecordSpoofCheck(!antiReport.Passed);

    if (req.TelemetryWindow.Count == 0)
    {
        return Results.BadRequest(new UnlockAttemptResponse
        {
            Unlocked = false,
            AntiSpoofing = antiReport,
            Message = "Konum telemetrisi gönderilmedi."
        });
    }

    var latest = req.TelemetryWindow.OrderBy(t => t.TimestampMs).Last();
    double verifiedLat = req.TelemetryWindow.Count >= 2 && antiReport.KalmanFilteredLat != 0
        ? antiReport.KalmanFilteredLat
        : latest.Latitude;
    double verifiedLon = req.TelemetryWindow.Count >= 2 && antiReport.KalmanFilteredLon != 0
        ? antiReport.KalmanFilteredLon
        : latest.Longitude;
    double dist = Math.Round(GeoMath.HaversineMeters(verifiedLat, verifiedLon, capsule.Latitude, capsule.Longitude), 2);
    bool arReady = dist <= capsule.ArTriggerRadiusMeters;
    bool withinUnlockRadius = dist <= capsule.UnlockRadiusMeters;

    double visualScore = req.BypassVisualInDemo
        ? 91.5
        : visual.ComputeSimilarity(capsule.VisualSignature, req.VisualSignature);

    double headingScore = req.ObservedHeadingDeg.HasValue
        ? crypto.ComputeHeadingAlignmentScore(capsule.AnchorHeadingDeg, req.ObservedHeadingDeg.Value)
        : 85.0;

    if (!antiReport.Passed)
    {
        return Results.Ok(new UnlockAttemptResponse
        {
            Unlocked = false,
            ArReady = arReady,
            DistanceMeters = dist,
            VisualMatchScore = visualScore,
            HeadingAlignmentScore = headingScore,
            AntiSpoofing = antiReport,
            Message = $"Güvenlik katmanı reddetti: {antiReport.Reason}"
        });
    }

    if (!withinUnlockRadius)
    {
        return Results.Ok(new UnlockAttemptResponse
        {
            Unlocked = false,
            ArReady = arReady,
            DistanceMeters = dist,
            VisualMatchScore = visualScore,
            HeadingAlignmentScore = headingScore,
            AntiSpoofing = antiReport,
            Message = arReady
                ? $"AR görüş alanındasınız ({dist:F1} m). Şifreli konumu çözmek için {capsule.UnlockRadiusMeters:F0} m içine yaklaşın."
                : $"Hedefe henüz uzaksınız ({dist:F1} m). Kilit açmak için {capsule.UnlockRadiusMeters:F0} m içine yürüyün."
        });
    }

    if (visualScore < 65.0)
    {
        return Results.Ok(new UnlockAttemptResponse
        {
            Unlocked = false,
            ArReady = true,
            DistanceMeters = dist,
            VisualMatchScore = visualScore,
            HeadingAlignmentScore = headingScore,
            AntiSpoofing = antiReport,
            Message = $"AR görsel yer işareti eşleşmesi yetersiz (%{visualScore:F0}). Kamerayı referans mekana doğrultun."
        });
    }

    // Decrypt AES-256-GCM spatially sealed payload when all physical + AR layers succeed
    string? decryptedNote = capsule.NoteText;
    bool sealVerified = true;
    if (!string.IsNullOrWhiteSpace(capsule.EncryptedPayload) &&
        !string.IsNullOrWhiteSpace(capsule.SealNonce) &&
        !string.IsNullOrWhiteSpace(capsule.SealTag))
    {
        var plain = crypto.DecryptSpatialPayload(
            capsule.EncryptedPayload,
            capsule.SealNonce,
            capsule.SealTag,
            capsule.Id,
            capsule.Latitude,
            capsule.Longitude,
            capsule.VisualSignature
        );
        if (plain != null)
        {
            decryptedNote = plain;
        }
        else
        {
            sealVerified = false;
        }
    }

    repo.RecordUnlock(capsule.Id);
    var unlockedView = new Capsule
    {
        Id = capsule.Id,
        Title = capsule.Title,
        Description = capsule.Description,
        Category = capsule.Category,
        ContentType = capsule.ContentType,
        Latitude = capsule.Latitude,
        Longitude = capsule.Longitude,
        UnlockRadiusMeters = capsule.UnlockRadiusMeters,
        ArTriggerRadiusMeters = capsule.ArTriggerRadiusMeters,
        LocationName = capsule.LocationName,
        ImageUrl = capsule.ImageUrl,
        NoteText = decryptedNote,
        PixelArtGrid = capsule.PixelArtGrid,
        AudioDurationSec = capsule.AudioDurationSec,
        AudioWaveform = capsule.AudioWaveform,
        VisualSignature = capsule.VisualSignature,
        AnchorHeadingDeg = capsule.AnchorHeadingDeg,
        SpatialSealHash = capsule.SpatialSealHash,
        IsEncrypted = capsule.IsEncrypted,
        CreatedBy = capsule.CreatedBy,
        CreatedAt = capsule.CreatedAt,
        UnlockCount = capsule.UnlockCount,
        Geohash = capsule.Geohash
    };

    return Results.Ok(new UnlockAttemptResponse
    {
        Unlocked = true,
        ArReady = true,
        DistanceMeters = dist,
        VisualMatchScore = visualScore,
        HeadingAlignmentScore = headingScore,
        SpatialSealVerified = sealVerified,
        AntiSpoofing = antiReport,
        Message = "AR konum mührü ve AES-256-GCM şifresi doğrulandı! Zaman kapsülü açıldı.",
        Capsule = unlockedView
    });
});

app.MapPost("/api/antispoof/evaluate", (
    List<TelemetrySample> window,
    AntiSpoofingEngine antiSpoof,
    CapsuleRepository repo) =>
{
    var report = antiSpoof.Evaluate(window);
    repo.RecordSpoofCheck(!report.Passed);
    return Results.Ok(report);
});

app.MapGet("/api/spatial/benchmark", (
    int? count,
    double? radius,
    int? iterations,
    SpatialIndexEngine spatial) =>
{
    var result = spatial.RunSpatialBenchmark(
        syntheticCount: count ?? 10000,
        radiusMeters: radius ?? 5.0,
        iterations: iterations ?? 100);
    return Results.Ok(result);
});

app.MapGet("/api/media/nearby", async (
    string? q,
    double? lat,
    double? lon,
    WikimediaMediaService media,
    CancellationToken ct) =>
{
    var items = await media.SearchMediaAsync(q, lat ?? 41.0122, lon ?? 28.9635, ct);
    return Results.Ok(items);
});

app.MapGet("/api/places/nearby", async (
    double? lat,
    double? lon,
    WikimediaMediaService media,
    CancellationToken ct) =>
{
    double qLat = lat ?? 41.0122;
    double qLon = lon ?? 28.9635;
    var places = await media.GetNearbyPopularPlacesAsync(qLat, qLon, ct);
    return Results.Ok(places);
});

app.MapPost("/api/activity", (ActivityRecordRequest req, CapsuleRepository repo) =>
{
    repo.RecordActivity(req);
    return Results.Ok(repo.GetSummary());
});

app.MapGet("/api/experiments/summary", (CapsuleRepository repo) =>
{
    return Results.Ok(repo.GetSummary());
});

app.MapPost("/api/experiments/sus-tam", (SusTamSubmission sub, CapsuleRepository repo) =>
{
    if (sub.SusAnswers == null || sub.SusAnswers.Count != 10)
        return Results.BadRequest(new { message = "SUS ölçeği için 10 madde puanı (1-5) gereklidir." });

    double susScore = repo.AddSusTamSubmission(sub);
    return Results.Ok(new
    {
        susScore,
        passedTarget75 = susScore >= 75.0,
        summary = repo.GetSummary()
    });
});

app.MapGet("/api/routes", (double? lat, double? lon, CapsuleRepository repo) =>
{
    return Results.Ok(repo.GetAllRoutes(lat, lon));
});

app.MapPost("/api/routes", (CreateRouteRequest req, CapsuleRepository repo) =>
{
    if (string.IsNullOrWhiteSpace(req.Title))
        return Results.BadRequest(new { message = "Rota başlığı zorunludur." });
    if (req.Waypoints == null || req.Waypoints.Count < 2)
        return Results.BadRequest(new { message = "Bir yürüyüş rotası için en az 2 durak noktası eklenmelidir." });

    var created = repo.CreateRoute(req);
    return Results.Created($"/api/routes/{created.Id}", created);
});

app.MapPost("/api/routes/{id}/rate", (string id, RateRouteRequest req, CapsuleRepository repo) =>
{
    var updated = repo.RateRoute(id, req);
    return updated is null
        ? Results.NotFound(new { message = "Rota bulunamadı." })
        : Results.Ok(updated);
});

app.MapPost("/api/routes/{id}/complete", (string id, CompleteRouteRequest? req, CapsuleRepository repo) =>
{
    var updated = repo.CompleteRoute(id, req?.MoodBoostScore);
    return updated is null
        ? Results.NotFound(new { message = "Rota bulunamadı." })
        : Results.Ok(new
        {
            route = updated,
            summary = repo.GetSummary()
        });
});

app.MapGet("/api/routes/suggest", async (
    double? lat,
    double? lon,
    string? cityDistrict,
    WikimediaMediaService media,
    CapsuleRepository repo,
    CancellationToken ct) =>
{
    double qLat = lat ?? 41.0122;
    double qLon = lon ?? 28.9635;
    var places = await media.GetNearbyPopularPlacesAsync(qLat, qLon, ct);

    var waypoints = new List<RouteWaypoint>
    {
        new()
        {
            Order = 1,
            Name = "Başlangıç Konumunuz",
            Latitude = qLat,
            Longitude = qLon,
            Hint = "Bulunduğunuz noktadan yürüyüşe başlayın"
        }
    };

    var selectedPlaces = places
        .Where(p => p.Latitude.HasValue && p.Longitude.HasValue)
        .Where(p => GeoMath.HaversineMeters(qLat, qLon, p.Latitude!.Value, p.Longitude!.Value) is >= 40 and <= 2500)
        .Take(3)
        .ToList();

    if (selectedPlaces.Count >= 2)
    {
        int order = 2;
        foreach (var place in selectedPlaces)
        {
            waypoints.Add(new RouteWaypoint
            {
                Order = order++,
                Name = place.Title,
                Latitude = place.Latitude!.Value,
                Longitude = place.Longitude!.Value,
                Hint = place.Description
            });
        }
    }
    else
    {
        // Küçük ilçe veya veri seyrek alanlarda yakında güvenli 1.2 km'lik yerel yürüyüş halkası oluştur
        double cosLat = Math.Max(Math.Cos(qLat * Math.PI / 180.0), 0.1);
        double dLat(double m) => m / 111320.0;
        double dLon(double m) => m / (111320.0 * cosLat);

        waypoints.Add(new RouteWaypoint
        {
            Order = 2,
            Name = "Mahalle / Kampüs Park Durağı",
            Latitude = qLat + dLat(260),
            Longitude = qLon + dLon(190),
            Hint = "Temiz hava ve kısa esneme molası"
        });
        waypoints.Add(new RouteWaypoint
        {
            Order = 3,
            Name = "Sosyal Buluşma & Seyir Noktası",
            Latitude = qLat + dLat(120),
            Longitude = qLon + dLon(420),
            Hint = "Fotoğraf veya zaman kapsülü bırakma noktası"
        });
        waypoints.Add(new RouteWaypoint
        {
            Order = 4,
            Name = "Dönüş & Bitiş Çemberi",
            Latitude = qLat - dLat(90),
            Longitude = qLon + dLon(180),
            Hint = "Yaklaşık 1.3 km tempolu sosyal yürüyüş bitişi"
        });
    }

    var created = repo.CreateRoute(new CreateRouteRequest
    {
        Title = "Konumuma Özel Sosyal Keşif Rotası",
        Description = "Çevrenizdeki park, kültür noktaları ve açık alanlardan otomatik oluşturulan başlangıç yürüyüş rotası. Yalnızlığı ve hareketsizliği kırmak için tasarlandı.",
        CityDistrict = string.IsNullOrWhiteSpace(cityDistrict) ? "Yakın Çevrem" : cityDistrict.Trim(),
        Difficulty = "Kolay",
        SocialTag = "Hareketsizliği Kıran Keşif",
        IsRawPreset = false,
        CreatedBy = "Otomatik Rota Motoru",
        Waypoints = waypoints
    }, overrideCategory: "Otomatik Çevre Rotası");

    return Results.Ok(created);
});

app.MapPost("/api/experiments/wellbeing", (WellBeingCheckInRequest req, CapsuleRepository repo) =>
{
    repo.RecordWellBeing(req);
    return Results.Ok(repo.GetSummary());
});

app.Run();
