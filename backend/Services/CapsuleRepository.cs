using System.Text.Json;
using CapsuleApi.Models;

namespace CapsuleApi.Services;

public sealed class CapsuleRepository
{
    private readonly string _dataFilePath;
    private readonly SpatialCryptoService _crypto;
    private readonly object _sync = new();
    private PersistedState _state;

    private sealed class PersistedState
    {
        public List<Capsule> Capsules { get; set; } = new();
        public List<WalkingRoute> Routes { get; set; } = new();
        public List<int> WellBeingScores { get; set; } = new();
        public int BlockedSpoofAttempts { get; set; } = 14;
        public int TotalSpoofChecks { get; set; } = 14;
        public int TotalStepsLogged { get; set; } = 4280;
        public double TotalDistanceMeters { get; set; } = 3180;
        public List<SusTamSubmission> SusSubmissions { get; set; } = new();
    }

    public CapsuleRepository(IWebHostEnvironment env, SpatialCryptoService crypto)
    {
        _crypto = crypto;
        var dir = Path.Combine(env.ContentRootPath, "data");
        Directory.CreateDirectory(dir);
        _dataFilePath = Path.Combine(dir, "state.json");
        _state = LoadOrSeed();
    }

    public List<Capsule> GetAllCapsules()
    {
        lock (_sync)
        {
            return _state.Capsules.Select(c => c).ToList();
        }
    }

    public Capsule? GetById(string id)
    {
        lock (_sync)
        {
            return _state.Capsules.FirstOrDefault(c => c.Id == id);
        }
    }

    public List<Capsule> EnsureLocalDiscoveryCapsules(double lat, double lon)
    {
        lock (_sync)
        {
            // Check if any capsule is already within 1200m
            bool hasNearby = _state.Capsules.Any(c => GeoMath.HaversineMeters(lat, lon, c.Latitude, c.Longitude) <= 1200.0);
            if (hasNearby) return _state.Capsules;

            double cosLat = Math.Max(Math.Cos(lat * Math.PI / 180.0), 0.1);
            double dLat(double meters) => meters / 111320.0;
            double dLon(double meters) => meters / (111320.0 * cosLat);

            var local = new List<Capsule>
            {
                new()
                {
                    Id = $"loc-{Guid.NewGuid():N}"[..10],
                    Title = "Yakın Çevre Keşif Kapsülü",
                    Description = "Konumunuzun hemen yakınında yürüyüşle açılabilecek başlangıç zaman kapsülü.",
                    Category = "Fiziksel Aktivite",
                    ContentType = "note",
                    Latitude = lat + dLat(45),
                    Longitude = lon + dLon(35),
                    UnlockRadiusMeters = 5.0,
                    ArTriggerRadiusMeters = 15.0,
                    LocationName = "Yakın Yürüyüş Noktası",
                    ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg",
                    NoteText = "Harika! İlk yerel yürüyüş kapsülünü başarıyla doğrulayıp açtınız.",
                    VisualSignature = "a4c8e2f09b7531d6",
                    CreatedBy = "KapsülAR Sistemi",
                    Geohash = GeoMath.EncodeGeohash(lat + dLat(45), lon + dLon(35), 7)
                },
                new()
                {
                    Id = $"loc-{Guid.NewGuid():N}"[..10],
                    Title = "Mahalle Piksel Hatırası",
                    Description = "140 metre mesafedeki yürüyüş durağında saklı piksel sanat eseri.",
                    Category = "Kampüs Yaşamı",
                    ContentType = "pixelArt",
                    Latitude = lat - dLat(95),
                    Longitude = lon + dLon(105),
                    UnlockRadiusMeters = 5.0,
                    ArTriggerRadiusMeters = 15.0,
                    LocationName = "Çevre Keşif Durağı",
                    ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/1/1e/Istanbul_University_campus_March_2008c.JPG",
                    PixelArtGrid = CreateSamplePixelArt(),
                    NoteText = "Kısa bir açık hava yürüyüşüyle bu piksel eseri açtınız!",
                    VisualSignature = "a4c8e2f09b7531d6",
                    CreatedBy = "Tasarım Topluluğu",
                    Geohash = GeoMath.EncodeGeohash(lat - dLat(95), lon + dLon(105), 7)
                },
                new()
                {
                    Id = $"loc-{Guid.NewGuid():N}"[..10],
                    Title = "Bölge Sesli Zaman İzleri",
                    Description = "250 metre yürüyüş hedefi için bırakılmış sesli anı kapsülü.",
                    Category = "Kültürel Miras",
                    ContentType = "audio",
                    Latitude = lat + dLat(180),
                    Longitude = lon - dLon(165),
                    UnlockRadiusMeters = 5.0,
                    ArTriggerRadiusMeters = 15.0,
                    LocationName = "Açık Alan Rotası",
                    ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/2/2b/S%C3%BCleymaniye_Camii.jpg",
                    NoteText = "Bu rotada 350 adım tamamlandı!",
                    AudioDurationSec = 16,
                    AudioWaveform = new List<double> { 0.3, 0.5, 0.8, 0.9, 0.5, 0.7, 0.85, 0.4, 0.6, 0.3 },
                    VisualSignature = "b8d2e4c19a7f5310",
                    CreatedBy = "Keşif Ekibi",
                    Geohash = GeoMath.EncodeGeohash(lat + dLat(180), lon - dLon(165), 7)
                }
            };

            _state.Capsules.InsertRange(0, local);
            SaveLocked();
            return _state.Capsules;
        }
    }

    public Capsule AddCapsule(CreateCapsuleRequest req)
    {
        lock (_sync)
        {
            var id = Guid.NewGuid().ToString("N")[..10];
            var visualSig = string.IsNullOrWhiteSpace(req.VisualSignature) ? "a4c8e2f09b7531d6" : req.VisualSignature;
            var plainNote = req.NoteText ?? req.Description;
            var sealedData = _crypto.EncryptSpatialPayload(
                plainNote,
                id,
                req.Latitude,
                req.Longitude,
                req.AnchorHeadingDeg,
                visualSig
            );

            var capsule = new Capsule
            {
                Id = id,
                Title = req.Title.Trim(),
                Description = req.Description.Trim(),
                Category = string.IsNullOrWhiteSpace(req.Category) ? "Kampüs Yaşamı" : req.Category,
                ContentType = string.IsNullOrWhiteSpace(req.ContentType) ? "note" : req.ContentType,
                Latitude = req.Latitude,
                Longitude = req.Longitude,
                UnlockRadiusMeters = Math.Clamp(req.UnlockRadiusMeters, 3.0, 25.0),
                ArTriggerRadiusMeters = Math.Clamp(req.ArTriggerRadiusMeters, 10.0, 50.0),
                LocationName = string.IsNullOrWhiteSpace(req.LocationName) ? "Kampüs Noktası" : req.LocationName.Trim(),
                ImageUrl = req.ImageUrl,
                NoteText = req.IsEncrypted ? null : plainNote,
                PixelArtGrid = req.PixelArtGrid,
                AudioDurationSec = req.AudioDurationSec,
                AudioWaveform = req.AudioWaveform,
                VisualSignature = visualSig,
                AnchorHeadingDeg = req.AnchorHeadingDeg,
                SpatialSealHash = sealedData.SealHashHex,
                EncryptedPayload = sealedData.CipherBase64,
                SealNonce = sealedData.NonceBase64,
                SealTag = sealedData.TagBase64,
                ClientSealProof = req.ClientSealProof,
                IsEncrypted = req.IsEncrypted,
                PasscodeHint = req.PasscodeHint,
                CreatedBy = string.IsNullOrWhiteSpace(req.CreatedBy) ? "Gezgin" : req.CreatedBy.Trim(),
                CreatedAt = DateTimeOffset.UtcNow,
                UnlockCount = 0,
                Geohash = GeoMath.EncodeGeohash(req.Latitude, req.Longitude, 7)
            };

            _state.Capsules.Insert(0, capsule);
            SaveLocked();
            return capsule;
        }
    }

    public void RecordUnlock(string capsuleId)
    {
        lock (_sync)
        {
            var c = _state.Capsules.FirstOrDefault(x => x.Id == capsuleId);
            if (c != null)
            {
                c.UnlockCount++;
                SaveLocked();
            }
        }
    }

    public void RecordSpoofCheck(bool blocked)
    {
        lock (_sync)
        {
            _state.TotalSpoofChecks++;
            if (blocked) _state.BlockedSpoofAttempts++;
            SaveLocked();
        }
    }

    public void RecordActivity(ActivityRecordRequest req)
    {
        lock (_sync)
        {
            if (req.StepsAdded > 0) _state.TotalStepsLogged += req.StepsAdded;
            if (req.DistanceMetersAdded > 0) _state.TotalDistanceMeters += req.DistanceMetersAdded;
            SaveLocked();
        }
    }

    public double AddSusTamSubmission(SusTamSubmission submission)
    {
        lock (_sync)
        {
            _state.SusSubmissions.Add(submission);
            SaveLocked();
            return ComputeSusScore(submission.SusAnswers);
        }
    }

    public List<WalkingRoute> GetAllRoutes(double? lat = null, double? lon = null)
    {
        lock (_sync)
        {
            return _state.Routes.Select(r =>
            {
                double distFromUser = 0;
                if (lat.HasValue && lon.HasValue && r.Waypoints.Count > 0)
                {
                    distFromUser = Math.Round(
                        GeoMath.HaversineMeters(lat.Value, lon.Value, r.Waypoints[0].Latitude, r.Waypoints[0].Longitude) / 1000.0,
                        2);
                }

                return new WalkingRoute
                {
                    Id = r.Id,
                    Title = r.Title,
                    Description = r.Description,
                    CityDistrict = r.CityDistrict,
                    RouteCategory = r.RouteCategory,
                    Difficulty = r.Difficulty,
                    SocialTag = r.SocialTag,
                    IsRawPreset = r.IsRawPreset,
                    CreatedBy = r.CreatedBy,
                    CreatedAt = r.CreatedAt,
                    DistanceKm = r.DistanceKm,
                    EstimatedMinutes = r.EstimatedMinutes,
                    EstimatedSteps = r.EstimatedSteps,
                    AverageRating = r.AverageRating,
                    RatingCount = r.RatingCount,
                    CompletionCount = r.CompletionCount,
                    DistanceFromUserKm = distFromUser,
                    Waypoints = r.Waypoints,
                    Ratings = r.Ratings.OrderByDescending(x => x.CreatedAt).ToList()
                };
            }).ToList();
        }
    }

    public WalkingRoute CreateRoute(CreateRouteRequest req, string? overrideCategory = null)
    {
        lock (_sync)
        {
            var ordered = req.Waypoints
                .Select((w, idx) => new RouteWaypoint
                {
                    Order = idx + 1,
                    Name = string.IsNullOrWhiteSpace(w.Name) ? $"Durak {idx + 1}" : w.Name.Trim(),
                    Latitude = w.Latitude,
                    Longitude = w.Longitude,
                    Hint = w.Hint?.Trim() ?? string.Empty
                })
                .ToList();

            double totalMeters = ComputeRouteDistanceMeters(ordered);
            double distKm = Math.Round(totalMeters / 1000.0, 2);
            int estMinutes = Math.Max(5, (int)Math.Round((distKm / 4.2) * 60.0));
            int estSteps = Math.Max(120, (int)Math.Round(totalMeters / 0.72));

            var route = new WalkingRoute
            {
                Id = $"rt-{Guid.NewGuid():N}"[..10],
                Title = req.Title.Trim(),
                Description = string.IsNullOrWhiteSpace(req.Description)
                    ? "Hareketsizliği azaltan ve sosyalleşmeyi teşvik eden topluluk yürüyüş rotası."
                    : req.Description.Trim(),
                CityDistrict = string.IsNullOrWhiteSpace(req.CityDistrict) ? "Yerel İlçe / Kampüs" : req.CityDistrict.Trim(),
                RouteCategory = overrideCategory ?? (req.IsRawPreset ? "Ham Rota" : "Topluluk Rotası"),
                Difficulty = string.IsNullOrWhiteSpace(req.Difficulty) ? "Kolay" : req.Difficulty.Trim(),
                SocialTag = string.IsNullOrWhiteSpace(req.SocialTag) ? "Üni Öğrenci Buluşması" : req.SocialTag.Trim(),
                IsRawPreset = req.IsRawPreset,
                CreatedBy = string.IsNullOrWhiteSpace(req.CreatedBy) ? "Gezgin" : req.CreatedBy.Trim(),
                CreatedAt = DateTimeOffset.UtcNow,
                DistanceKm = distKm,
                EstimatedMinutes = estMinutes,
                EstimatedSteps = estSteps,
                AverageRating = 0,
                RatingCount = 0,
                CompletionCount = 0,
                Waypoints = ordered,
                Ratings = new List<RouteRating>()
            };

            _state.Routes.Insert(0, route);
            SaveLocked();
            return route;
        }
    }

    public WalkingRoute? RateRoute(string routeId, RateRouteRequest req)
    {
        lock (_sync)
        {
            var route = _state.Routes.FirstOrDefault(r => r.Id == routeId);
            if (route is null) return null;

            int stars = Math.Clamp(req.Stars, 1, 5);
            int mood = Math.Clamp(req.MoodBoostScore, 1, 5);
            route.Ratings.Insert(0, new RouteRating
            {
                Id = Guid.NewGuid().ToString("N")[..8],
                UserName = string.IsNullOrWhiteSpace(req.UserName) ? "Gezgin" : req.UserName.Trim(),
                Stars = stars,
                Comment = req.Comment?.Trim() ?? string.Empty,
                MoodBoostScore = mood,
                CreatedAt = DateTimeOffset.UtcNow
            });

            route.RatingCount = route.Ratings.Count;
            route.AverageRating = Math.Round(route.Ratings.Average(x => x.Stars), 1);
            _state.WellBeingScores.Add(mood);
            SaveLocked();
            return route;
        }
    }

    public WalkingRoute? CompleteRoute(string routeId, int? moodBoostScore)
    {
        lock (_sync)
        {
            var route = _state.Routes.FirstOrDefault(r => r.Id == routeId);
            if (route is null) return null;

            route.CompletionCount++;
            _state.TotalStepsLogged += route.EstimatedSteps;
            _state.TotalDistanceMeters += route.DistanceKm * 1000.0;
            if (moodBoostScore.HasValue)
            {
                _state.WellBeingScores.Add(Math.Clamp(moodBoostScore.Value, 1, 5));
            }
            SaveLocked();
            return route;
        }
    }

    public void RecordWellBeing(WellBeingCheckInRequest req)
    {
        lock (_sync)
        {
            int avg = (int)Math.Round((Math.Clamp(req.MoodScore, 1, 5) + Math.Clamp(req.SocialConnectedness, 1, 5)) / 2.0);
            _state.WellBeingScores.Add(avg);
            SaveLocked();
        }
    }

    public ExperimentSummary GetSummary()
    {
        lock (_sync)
        {
            double avgSus = _state.SusSubmissions.Count > 0
                ? Math.Round(_state.SusSubmissions.Select(s => ComputeSusScore(s.SusAnswers)).Average(), 1)
                : 82.5;
            double avgPu = _state.SusSubmissions.Count > 0
                ? Math.Round(_state.SusSubmissions.Average(s => s.TamPerceivedUsefulness), 2)
                : 4.35;
            double avgPeou = _state.SusSubmissions.Count > 0
                ? Math.Round(_state.SusSubmissions.Average(s => s.TamEaseOfUse), 2)
                : 4.48;

            double blockRate = _state.TotalSpoofChecks > 0
                ? Math.Round((double)_state.BlockedSpoofAttempts / _state.TotalSpoofChecks * 100.0, 1)
                : 100.0;

            double avgWellBeing = _state.WellBeingScores.Count > 0
                ? Math.Round(_state.WellBeingScores.Average(), 2)
                : 4.4;

            return new ExperimentSummary
            {
                TotalCapsules = _state.Capsules.Count,
                TotalUnlocks = _state.Capsules.Sum(c => c.UnlockCount),
                BlockedSpoofAttempts = _state.BlockedSpoofAttempts,
                SpoofBlockRatePercent = blockRate,
                TotalStepsLogged = _state.TotalStepsLogged,
                TotalDistanceKm = Math.Round(_state.TotalDistanceMeters / 1000.0, 2),
                SusResponsesCount = _state.SusSubmissions.Count,
                AverageSusScore = avgSus,
                AverageTamUsefulness = avgPu,
                AverageTamEaseOfUse = avgPeou,
                TotalRoutes = _state.Routes.Count,
                TotalRouteCompletions = _state.Routes.Sum(r => r.CompletionCount),
                TotalRouteRatings = _state.Routes.Sum(r => r.RatingCount),
                AverageWellBeingScore = avgWellBeing
            };
        }
    }

    public static double ComputeSusScore(List<int> answers)
    {
        if (answers == null || answers.Count != 10) return 0;
        double sum = 0;
        for (int i = 0; i < 10; i++)
        {
            int val = Math.Clamp(answers[i], 1, 5);
            // Odd items (index 0,2,4,6,8): score - 1; Even items (index 1,3,5,7,9): 5 - score
            sum += (i % 2 == 0) ? (val - 1) : (5 - val);
        }
        return Math.Round(sum * 2.5, 1);
    }

    private PersistedState LoadOrSeed()
    {
        if (File.Exists(_dataFilePath))
        {
            try
            {
                var json = File.ReadAllText(_dataFilePath);
                var loaded = JsonSerializer.Deserialize<PersistedState>(json);
                if (loaded != null && loaded.Capsules.Count > 0)
                {
                    if (loaded.Routes.Count == 0)
                    {
                        loaded.Routes = CreateSeededRoutes();
                        loaded.WellBeingScores = loaded.WellBeingScores.Count == 0
                            ? new List<int> { 4, 5, 4, 5 }
                            : loaded.WellBeingScores;
                        _state = loaded;
                        SaveLocked();
                    }
                    return loaded;
                }
            }
            catch
            {
                // Fall back to fresh seed if corrupted
            }
        }

        var seeded = CreateSeededState();
        _state = seeded;
        SaveLocked();
        return seeded;
    }

    private void SaveLocked()
    {
        var json = JsonSerializer.Serialize(_state, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(_dataFilePath, json);
    }

    private static PersistedState CreateSeededState()
    {
        // Build a 16x16 pixel-art heart/hourglass icon for the campus pixel art capsule
        var pixelArt = CreateSamplePixelArt();

        var capsules = new List<Capsule>
        {
            new()
            {
                Id = "cap-beyazit",
                Title = "1933 Kampüs Hafızası",
                Description = "Tarihi ana kapı önünde üniversite tarihinden kısa bir sesli anı ve arşiv notu.",
                Category = "Kültürel Miras",
                ContentType = "audio",
                Latitude = 41.0119,
                Longitude = 28.9639,
                UnlockRadiusMeters = 5.0,
                ArTriggerRadiusMeters = 15.0,
                LocationName = "İstanbul Üniversitesi Tarihi Kapı",
                ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/a/aa/%C4%B0stanbul_%C3%9Cniversitesi.JPG",
                NoteText = "Darülfünun'dan günümüze bu taş kapıdan geçen binlerce öğrencinin ayak izi burada saklı.",
                AudioDurationSec = 18,
                AudioWaveform = new List<double> { 0.2, 0.45, 0.78, 0.9, 0.62, 0.35, 0.8, 0.95, 0.7, 0.4, 0.55, 0.85, 0.6, 0.3, 0.5, 0.25 },
                VisualSignature = "b8d2e4c19a7f5310",
                CreatedBy = "Tarih Kulübü",
                UnlockCount = 27
            },
            new()
            {
                Id = "cap-bahce",
                Title = "Çınar Altı Piksel Sanatı",
                Description = "Merkez bahçede yürüyüş molası verenler için bırakılmış 16x16 piksel sanat eseri.",
                Category = "Kampüs Yaşamı",
                ContentType = "pixelArt",
                Latitude = 41.0124,
                Longitude = 28.9634,
                UnlockRadiusMeters = 5.0,
                ArTriggerRadiusMeters = 15.0,
                LocationName = "Merkez Kampüs Bahçesi",
                ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/1/1e/Istanbul_University_campus_March_2008c.JPG",
                PixelArtGrid = pixelArt,
                NoteText = "Kampüs bahçesinde 500 adımını tamamlayan ilk gezginler için çizildi!",
                VisualSignature = "a4c8e2f09b7531d6",
                CreatedBy = "Tasarım Topluluğu",
                UnlockCount = 19
            },
            new()
            {
                Id = "cap-suleymaniye",
                Title = "Mimar Sinan Akustik Rotası",
                Description = "Süleymaniye avlusunda kubbe akustiğini ve Haliç manzarasını anlatan görsel kapsül.",
                Category = "Kültürel Miras",
                ContentType = "photo",
                Latitude = 41.0161,
                Longitude = 28.9642,
                UnlockRadiusMeters = 5.0,
                ArTriggerRadiusMeters = 15.0,
                LocationName = "Süleymaniye Külliyesi Avlusu",
                ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/2/2b/S%C3%BCleymaniye_Camii.jpg",
                NoteText = "1557'de tamamlanan külliyenin avlusundan Haliç'e doğru baktığınızda 650 metrelik kültür rotasının zirvesindesiniz.",
                VisualSignature = "c9e1f3a7b5d28460",
                CreatedBy = "Akıllı Turizm Ekibi",
                UnlockCount = 41
            },
            new()
            {
                Id = "cap-kafe",
                Title = "Kitabevi Kahve Sürprizi",
                Description = "Yürüyüş rotasını tamamlayıp kapı önüne ulaşan ziyaretçilere özel %20 kahve & kitap notu.",
                Category = "Yerel İşletme",
                ContentType = "note",
                Latitude = 41.0132,
                Longitude = 28.9651,
                UnlockRadiusMeters = 5.0,
                ArTriggerRadiusMeters = 15.0,
                LocationName = "Sahaflar & Kampüs Kitabevi",
                ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg",
                NoteText = "Tebrikler! Fiziksel mağaza önü WebAR kapsülünü açtınız. Kasa kodu: KAPSUL-2209",
                VisualSignature = "7f8e9a2c4b6d1035",
                IsEncrypted = true,
                PasscodeHint = "Kasa indirim kapsülü",
                CreatedBy = "Yerel İşletme Ortağı",
                UnlockCount = 14
            },
            new()
            {
                Id = "cap-galata",
                Title = "Galata Yokuşu Adım Meydanı",
                Description = "Yokuş yürüyüşünü tamamlayanlar için Boğaz manzaralı sesli keşif kapsülü.",
                Category = "Fiziksel Aktivite",
                ContentType = "audio",
                Latitude = 41.0256,
                Longitude = 28.9741,
                UnlockRadiusMeters = 5.0,
                ArTriggerRadiusMeters = 15.0,
                LocationName = "Galata Kulesi Meydanı",
                ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg",
                NoteText = "Karaköy'den buraya yürüyerek ortalama 1.450 adım attınız. Harika bir tempo!",
                AudioDurationSec = 24,
                AudioWaveform = new List<double> { 0.3, 0.5, 0.85, 0.72, 0.4, 0.66, 0.92, 0.81, 0.48, 0.75, 0.6, 0.35, 0.88, 0.54, 0.42, 0.2 },
                VisualSignature = "d4a7c9e2f1b86035",
                CreatedBy = "Sağlıklı Kampüs",
                UnlockCount = 33
            },
            new()
            {
                Id = "cap-kizkulesi",
                Title = "Sahil Koşu Hattı Zaman Kapsülü",
                Description = "Üsküdar sahil yürüyüş parkurunun 3. kilometresi için bırakılmış panoramik fotoğraf kapsülü.",
                Category = "Fiziksel Aktivite",
                ContentType = "photo",
                Latitude = 41.0211,
                Longitude = 29.0041,
                UnlockRadiusMeters = 5.0,
                ArTriggerRadiusMeters = 15.0,
                LocationName = "Üsküdar Sahil Yolu",
                ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/b/b3/K%C4%B1zKulesi.jpg",
                NoteText = "Sahil şeridinde gün batımı yürüyüşü: 3.000 adım kontrol noktası tamamlandı.",
                VisualSignature = "e5c2a8f49173bd06",
                CreatedBy = "Koşu Kulübü",
                UnlockCount = 22
            }
        };

        foreach (var c in capsules)
        {
            c.Geohash = GeoMath.EncodeGeohash(c.Latitude, c.Longitude, 7);
        }

        return new PersistedState
        {
            Capsules = capsules,
            Routes = CreateSeededRoutes(),
            WellBeingScores = new List<int> { 4, 5, 4, 5, 4 },
            SusSubmissions = new List<SusTamSubmission>
            {
                new()
                {
                    UserId = "pilot-01",
                    Group = "Deney",
                    SusAnswers = new List<int> { 5, 2, 5, 1, 4, 2, 5, 1, 5, 2 },
                    TamPerceivedUsefulness = 4.5,
                    TamEaseOfUse = 4.6,
                    TamBehavioralIntention = 4.4
                },
                new()
                {
                    UserId = "pilot-02",
                    Group = "Deney",
                    SusAnswers = new List<int> { 4, 2, 5, 2, 4, 1, 4, 2, 5, 2 },
                    TamPerceivedUsefulness = 4.2,
                    TamEaseOfUse = 4.4,
                    TamBehavioralIntention = 4.3
                }
            }
        };
    }

    private static double ComputeRouteDistanceMeters(List<RouteWaypoint> waypoints)
    {
        double total = 0;
        for (int i = 1; i < waypoints.Count; i++)
        {
            total += GeoMath.HaversineMeters(
                waypoints[i - 1].Latitude,
                waypoints[i - 1].Longitude,
                waypoints[i].Latitude,
                waypoints[i].Longitude);
        }
        return total;
    }

    private static List<WalkingRoute> CreateSeededRoutes()
    {
        var rawRoutes = new List<WalkingRoute>
        {
            new()
            {
                Id = "rt-likya",
                Title = "Likya Yolu: Ovacık – Faralya – Kabak Ham Rotası",
                Description = "Türkiye'nin en bilinen uzun mesafe yürüyüş parkurunun başlangıç etabını sunan ham GPS rotası. Doğa yürüyüşü grupları ve açık hava sosyalleşmesi için duraklı referans hat.",
                CityDistrict = "Muğla / Fethiye",
                RouteCategory = "Ham Rota",
                Difficulty = "Orta",
                SocialTag = "Doğa & Kültür Keşfi",
                IsRawPreset = true,
                CreatedBy = "Likya Ham Rota Arşivi",
                CompletionCount = 34,
                Waypoints = new List<RouteWaypoint>
                {
                    new() { Order = 1, Name = "Ovacık Likya Başlangıç Kapısı", Latitude = 36.5718, Longitude = 29.1536, Hint = "Sarı-kırmızı Likya işaretleme başlangıcı" },
                    new() { Order = 2, Name = "Kozağaç Çeşmesi", Latitude = 36.5542, Longitude = 29.1465, Hint = "Orman içi gölgelik mola durağı" },
                    new() { Order = 3, Name = "Kirme Köyü Sırtı", Latitude = 36.5356, Longitude = 29.1394, Hint = "Ölüdeniz panoramik seyir noktası" },
                    new() { Order = 4, Name = "Faralya – Kelebekler Vadisi Üstü", Latitude = 36.4945, Longitude = 29.1328, Hint = "Kanyon seyir terası ve sosyalleşme molası" },
                    new() { Order = 5, Name = "Kabak Koyu İniş Patikası", Latitude = 36.4648, Longitude = 29.1241, Hint = "Etap bitiş ve kamp alanı buluşma noktası" }
                },
                Ratings = new List<RouteRating>
                {
                    new() { UserName = "Zeynep K.", Stars = 5, MoodBoostScore = 5, Comment = "Ham duraklar net olduğu için yalnız gelenlerle Faralya'da yürüyüş grubu kurduk." },
                    new() { UserName = "Emre T.", Stars = 5, MoodBoostScore = 4, Comment = "Özellikle gün batımı etabı çok motive edici, işaretler GPS ile uyumlu." }
                }
            },
            new()
            {
                Id = "rt-frig",
                Title = "Frig Vadisi: Ayazini – Emre Gölü Ham Rotası",
                Description = "Küçük ilçe ve kırsal yerleşimlerdeki gençler ile halkın hafta sonu hareketsizliğini kırması için hazırlanan kaya anıtları ve göl kenarı yürüyüş hattı.",
                CityDistrict = "Afyonkarahisar / İhsaniye",
                RouteCategory = "Ham Rota",
                Difficulty = "Kolay",
                SocialTag = "Halk & Öğrenci Hafta Sonu",
                IsRawPreset = true,
                CreatedBy = "Anadolu Kültür Rotaları",
                CompletionCount = 21,
                Waypoints = new List<RouteWaypoint>
                {
                    new() { Order = 1, Name = "Ayazini Kaya Kilisesi", Latitude = 39.0928, Longitude = 30.4839, Hint = "Buluşma ve ısınma yürüyüşü başlangıcı" },
                    new() { Order = 2, Name = "Ayazini Kaya Mezarları", Latitude = 39.0956, Longitude = 30.4892, Hint = "Tarihi fotoğraf kapsülü noktası" },
                    new() { Order = 3, Name = "Avdalaz Kalesi Seyir", Latitude = 39.0998, Longitude = 30.4945, Hint = "Kısa soluklanma ve manzara durağı" },
                    new() { Order = 4, Name = "Emre Gölü Yürüyüş Kıyısı", Latitude = 39.1086, Longitude = 30.5062, Hint = "Göl çevresi yürüyüş ve sohbet alanı" }
                },
                Ratings = new List<RouteRating>
                {
                    new() { UserName = "Mert A.", Stars = 5, MoodBoostScore = 5, Comment = "İlçede yapacak bir şey yok sanıyorduk, öğrenci topluluğuyla 4 kişi tamamladık." }
                }
            },
            new()
            {
                Id = "rt-oltu",
                Title = "Küçük İlçe Keşif: Oltu Kalesi – Çoruh Kenarı Öğrenci Hattı",
                Description = "Küçük ilçede okuyan üniversite öğrencilerinin kampüs dışına çıkıp sosyalleşemediği alanları canlandıran güvenli akşamüstü yürüyüş rotası.",
                CityDistrict = "Erzurum / Oltu",
                RouteCategory = "Ham Rota",
                Difficulty = "Kolay",
                SocialTag = "Üni Öğrenci Buluşması",
                IsRawPreset = true,
                CreatedBy = "İlçe Gençlik Yürüyüşü",
                CompletionCount = 19,
                Waypoints = new List<RouteWaypoint>
                {
                    new() { Order = 1, Name = "Oltu Kampüs / MYO Çıkışı", Latitude = 40.5468, Longitude = 41.9942, Hint = "Öğrenci buluşma başlangıcı" },
                    new() { Order = 2, Name = "Oltu Kalesi Çevresi", Latitude = 40.5495, Longitude = 41.9963, Hint = "Tarihi kale etrafı hafif tempo" },
                    new() { Order = 3, Name = "Kültür Parkı & Kütüphane Önü", Latitude = 40.5512, Longitude = 41.9990, Hint = "Çay molası ve sosyalleşme noktası" },
                    new() { Order = 4, Name = "Oltu Çayı Yürüyüş Bandı", Latitude = 40.5477, Longitude = 42.0028, Hint = "Akşamüstü nehir kenarı bitiş" }
                },
                Ratings = new List<RouteRating>
                {
                    new() { UserName = "Sena D.", Stars = 4, MoodBoostScore = 5, Comment = "Yurttan çıkıp yürümek için bahane oldu, parkta yeni arkadaşlarla tanıştık." }
                }
            },
            new()
            {
                Id = "rt-beyazit",
                Title = "Beyazıt – Süleymaniye Sosyal & Kültür Yürüyüşü",
                Description = "Kampüs içinde hareketsiz kalan öğrenciler için tarihi durakları ve kitapçı kafeleri bağlayan düşük eğimli sosyalleşme rotası.",
                CityDistrict = "İstanbul / Fatih",
                RouteCategory = "Topluluk Rotası",
                Difficulty = "Kolay",
                SocialTag = "Üni Öğrenci Buluşması",
                IsRawPreset = false,
                CreatedBy = "SOY Tech Keşif Ekibi",
                CompletionCount = 46,
                Waypoints = new List<RouteWaypoint>
                {
                    new() { Order = 1, Name = "İ.Ü. Tarihi Ana Kapı", Latitude = 41.0119, Longitude = 28.9639, Hint = "Meydan girişi buluşma noktası" },
                    new() { Order = 2, Name = "Merkez Kampüs Bahçesi", Latitude = 41.0124, Longitude = 28.9634, Hint = "Çınar altı piksel kapsül durağı" },
                    new() { Order = 3, Name = "Sahaflar & Kitabevi Sokağı", Latitude = 41.0132, Longitude = 28.9651, Hint = "Kahve ve kitap sohbeti molası" },
                    new() { Order = 4, Name = "Süleymaniye Külliyesi Avlusu", Latitude = 41.0161, Longitude = 28.9642, Hint = "Haliç manzaralı rota bitişi" }
                },
                Ratings = new List<RouteRating>
                {
                    new() { UserName = "Ozan H.", Stars = 5, MoodBoostScore = 5, Comment = "Ders arası 15 dakikalık yürüyüş zihnimi açtı." },
                    new() { UserName = "Semih B.", Stars = 4, MoodBoostScore = 4, Comment = "Kapsüllerle birleşince rota çok daha eğlenceli oluyor." }
                }
            }
        };

        foreach (var r in rawRoutes)
        {
            double meters = ComputeRouteDistanceMeters(r.Waypoints);
            r.DistanceKm = Math.Round(meters / 1000.0, 2);
            r.EstimatedMinutes = Math.Max(8, (int)Math.Round((r.DistanceKm / 4.2) * 60.0));
            r.EstimatedSteps = Math.Max(200, (int)Math.Round(meters / 0.72));
            r.RatingCount = r.Ratings.Count;
            r.AverageRating = r.Ratings.Count > 0 ? Math.Round(r.Ratings.Average(x => x.Stars), 1) : 0;
        }

        return rawRoutes;
    }

    private static List<int> CreateSamplePixelArt()
    {
        // 16x16 palette indices (0 = transparent, 1 = indigo, 2 = amber/gold, 3 = emerald, 4 = white)
        const string pattern =
            "0000000000000000" +
            "0001111111111000" +
            "0001222222221000" +
            "0000122442210000" +
            "0000012442100000" +
            "0000001221000000" +
            "0000000110000000" +
            "0000000110000000" +
            "0000001331000000" +
            "0000013333100000" +
            "0000133443310000" +
            "0001333333331000" +
            "0001111111111000" +
            "0000000000000000" +
            "0033000000003300" +
            "0000000000000000";

        int[] palette = { 0x00000000, unchecked((int)0xFF3F51B5), unchecked((int)0xFFF59E0B), unchecked((int)0xFF10B981), unchecked((int)0xFFFFFFFF) };
        return pattern.Select(ch => palette[ch - '0']).ToList();
    }
}
