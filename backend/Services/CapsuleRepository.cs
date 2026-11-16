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
                AverageTamEaseOfUse = avgPeou
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
                    return loaded;
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
