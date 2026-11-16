namespace CapsuleApi.Models;

public enum CapsuleContentType
{
    Note,
    Photo,
    PixelArt,
    Audio
}

public sealed class Capsule
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N")[..10];
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Category { get; set; } = "Kültürel Miras";
    public string ContentType { get; set; } = "note"; // note | photo | pixelArt | audio
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double UnlockRadiusMeters { get; set; } = 5.0;
    public double ArTriggerRadiusMeters { get; set; } = 15.0;
    public string LocationName { get; set; } = string.Empty;
    public string? ImageUrl { get; set; }
    public string? NoteText { get; set; }
    public List<int>? PixelArtGrid { get; set; } // 16x16 ARGB palette indices or colors
    public int? AudioDurationSec { get; set; }
    public List<double>? AudioWaveform { get; set; }
    public string VisualSignature { get; set; } = string.Empty;
    public double AnchorHeadingDeg { get; set; }
    public string SpatialSealHash { get; set; } = string.Empty;
    public string? EncryptedPayload { get; set; }
    public string? SealNonce { get; set; }
    public string? SealTag { get; set; }
    public string? ClientSealProof { get; set; }
    public bool IsEncrypted { get; set; }
    public string? PasscodeHint { get; set; }
    public string CreatedBy { get; set; } = "Gezgin";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public int UnlockCount { get; set; }
    public string Geohash { get; set; } = string.Empty;
}

public sealed class CreateCapsuleRequest
{
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Category { get; set; } = "Kampüs Yaşamı";
    public string ContentType { get; set; } = "note";
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double UnlockRadiusMeters { get; set; } = 5.0;
    public double ArTriggerRadiusMeters { get; set; } = 15.0;
    public string LocationName { get; set; } = string.Empty;
    public string? ImageUrl { get; set; }
    public string? NoteText { get; set; }
    public List<int>? PixelArtGrid { get; set; }
    public int? AudioDurationSec { get; set; }
    public List<double>? AudioWaveform { get; set; }
    public string? VisualSignature { get; set; }
    public double AnchorHeadingDeg { get; set; }
    public string? ClientSealProof { get; set; }
    public bool IsEncrypted { get; set; } = true;
    public string? PasscodeHint { get; set; }
    public string CreatedBy { get; set; } = "Kullanıcı";
}

public sealed class TelemetrySample
{
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double AccuracyMeters { get; set; } = 5.0;
    public double AltitudeMeters { get; set; }
    public double ReportedSpeedMps { get; set; }
    public double HeadingDeg { get; set; }
    public bool IsMocked { get; set; }
    public long TimestampMs { get; set; }
    public double AccelX { get; set; }
    public double AccelY { get; set; }
    public double AccelZ { get; set; } = 9.81;
    public double GyroAlpha { get; set; }
    public double GyroBeta { get; set; }
    public double GyroGamma { get; set; }
}

public sealed class VerificationLayerResult
{
    public string Name { get; set; } = string.Empty;
    public bool Passed { get; set; }
    public double Score { get; set; }
    public string Detail { get; set; } = string.Empty;
}

public sealed class AntiSpoofingReport
{
    public bool Passed { get; set; }
    public double TrustScore { get; set; } // 0..100
    public double MaxObservedSpeedMps { get; set; }
    public double MaxObservedAccelerationMps2 { get; set; }
    public bool ImpossibleJumpDetected { get; set; }
    public bool SensorFusionConsistent { get; set; }
    public bool MockProviderDetected { get; set; }
    public double SignalJitterStdDev { get; set; }
    public double KalmanFilteredLat { get; set; }
    public double KalmanFilteredLon { get; set; }
    public double KalmanInnovationMeters { get; set; }
    public int SampleCount { get; set; }
    public string Reason { get; set; } = string.Empty;
    public List<VerificationLayerResult> Layers { get; set; } = new();
}

public sealed class UnlockAttemptRequest
{
    public string UserId { get; set; } = "demo-user";
    public string CapsuleId { get; set; } = string.Empty;
    public List<TelemetrySample> TelemetryWindow { get; set; } = new();
    public string? VisualSignature { get; set; }
    public double? ObservedHeadingDeg { get; set; }
    public bool BypassVisualInDemo { get; set; }
}

public sealed class UnlockAttemptResponse
{
    public bool Unlocked { get; set; }
    public bool ArReady { get; set; }
    public double DistanceMeters { get; set; }
    public double VisualMatchScore { get; set; }
    public double HeadingAlignmentScore { get; set; }
    public bool SpatialSealVerified { get; set; }
    public AntiSpoofingReport AntiSpoofing { get; set; } = new();
    public string Message { get; set; } = string.Empty;
    public Capsule? Capsule { get; set; }
}

public sealed class SpatialStrategyMetrics
{
    public string Strategy { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public double AvgQueryMs { get; set; }
    public double P95QueryMs { get; set; }
    public int AvgCandidatesScanned { get; set; }
    public int MatchesFound { get; set; }
    public double EstimatedMemoryKb { get; set; }
}

public sealed class SpatialBenchmarkResponse
{
    public int SyntheticPointCount { get; set; }
    public int QueryIterations { get; set; }
    public double QueryRadiusMeters { get; set; }
    public DateTimeOffset ExecutedAt { get; set; } = DateTimeOffset.UtcNow;
    public List<SpatialStrategyMetrics> Results { get; set; } = new();
}

public sealed class ActivityRecordRequest
{
    public string UserId { get; set; } = "demo-user";
    public string Group { get; set; } = "Deney Grubu (WebAR)";
    public int StepsAdded { get; set; }
    public double DistanceMetersAdded { get; set; }
    public string? DiscoveredCapsuleId { get; set; }
}

public sealed class SusTamSubmission
{
    public string UserId { get; set; } = "demo-user";
    public string Group { get; set; } = "Deney"; // Kontrol | Deney
    public List<int> SusAnswers { get; set; } = new(); // 10 items, 1..5
    public double TamPerceivedUsefulness { get; set; } // 1..5
    public double TamEaseOfUse { get; set; } // 1..5
    public double TamBehavioralIntention { get; set; } // 1..5
}

public sealed class ExperimentSummary
{
    public int TotalCapsules { get; set; }
    public int TotalUnlocks { get; set; }
    public int BlockedSpoofAttempts { get; set; }
    public double SpoofBlockRatePercent { get; set; }
    public int TotalStepsLogged { get; set; }
    public double TotalDistanceKm { get; set; }
    public int SusResponsesCount { get; set; }
    public double AverageSusScore { get; set; }
    public double AverageTamUsefulness { get; set; }
    public double AverageTamEaseOfUse { get; set; }
}

public sealed class NearbyMediaItem
{
    public string Title { get; set; } = string.Empty;
    public string ImageUrl { get; set; } = string.Empty;
    public string Source { get; set; } = "Wikimedia Commons";
    public string Description { get; set; } = string.Empty;
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public double? DistanceMeters { get; set; }
}
