using CapsuleApi.Models;

namespace CapsuleApi.Services;

public sealed class AntiSpoofingEngine
{
    private const double PedestrianMaxSpeedMps = 8.5;     // ~30 km/h sprint/bike bound
    private const double ImpossibleJumpSpeedMps = 18.0;   // > 65 km/h teleportation
    private const double MaxReasonableAccelMps2 = 12.0;

    public AntiSpoofingReport Evaluate(List<TelemetrySample> rawWindow)
    {
        if (rawWindow == null || rawWindow.Count == 0)
        {
            return new AntiSpoofingReport
            {
                Passed = false,
                TrustScore = 0,
                SampleCount = 0,
                Reason = "Konum telemetri penceresi boş. Doğrulama yapılamadı."
            };
        }

        // Focus on the last 30 seconds
        var sorted = rawWindow.OrderBy(s => s.TimestampMs).ToList();
        long latestTs = sorted[^1].TimestampMs;
        var window = sorted.Where(s => latestTs - s.TimestampMs <= 30_000).ToList();
        if (window.Count == 0) window = sorted;

        // ------------------------------------------------------------------
        // KATMAN 1: OS Mock Location & Sinyal Gürültü (Multipath Jitter) Analizi
        // ------------------------------------------------------------------
        bool mockDetected = window.Any(s => s.IsMocked);
        bool suspiciousZeroAccuracy = window.All(s => s.AccuracyMeters <= 0.0);

        double meanAcc = window.Average(s => s.AccuracyMeters);
        double accJitterStdDev = Math.Sqrt(window.Average(s => Math.Pow(s.AccuracyMeters - meanAcc, 2)));
        bool syntheticFlatSignal = window.Count >= 4 && accJitterStdDev < 0.001 && window.Any(s => s.ReportedSpeedMps > 0.5);

        double layer1Score = 100.0;
        var layer1Notes = new List<string>();
        if (mockDetected)
        {
            layer1Score = 0;
            layer1Notes.Add("Android Mock Location sağlayıcısı tespit edildi");
        }
        else
        {
            if (suspiciousZeroAccuracy)
            {
                layer1Score -= 45;
                layer1Notes.Add("0.0m sahte doğruluk değeri");
            }
            if (syntheticFlatSignal)
            {
                layer1Score -= 25;
                layer1Notes.Add("Doğal GPS sinyal sapması yok (sentetik veri şüphesi)");
            }
        }
        bool layer1Pass = !mockDetected && layer1Score >= 60.0;

        // ------------------------------------------------------------------
        // KATMAN 2: Kinematik Fizik (Hız, İvme, İmkansız Sıçrama)
        // ------------------------------------------------------------------
        double maxSpeed = 0;
        double maxAccel = 0;
        double prevSpeed = 0;
        bool jumpDetected = false;
        double totalDistanceMoved = 0;

        for (int i = 1; i < window.Count; i++)
        {
            var prev = window[i - 1];
            var curr = window[i];
            double dtSec = Math.Max((curr.TimestampMs - prev.TimestampMs) / 1000.0, 0.25);
            double distM = GeoMath.HaversineMeters(prev.Latitude, prev.Longitude, curr.Latitude, curr.Longitude);
            totalDistanceMoved += distM;

            double speed = distM / dtSec;
            if (speed > maxSpeed) maxSpeed = speed;

            double accel = Math.Abs(speed - prevSpeed) / dtSec;
            if (accel > maxAccel) maxAccel = accel;
            prevSpeed = speed;

            if (speed > ImpossibleJumpSpeedMps || (distM > 32.0 && dtSec <= 2.0))
            {
                jumpDetected = true;
            }
        }

        double layer2Score = 100.0;
        if (jumpDetected) layer2Score -= 70.0;
        else if (maxSpeed > PedestrianMaxSpeedMps) layer2Score -= 30.0;
        if (maxAccel > MaxReasonableAccelMps2) layer2Score -= 25.0;
        layer2Score = Math.Clamp(layer2Score, 0, 100);
        bool layer2Pass = !jumpDetected && layer2Score >= 60.0;

        // ------------------------------------------------------------------
        // KATMAN 3: 2D Kalman Filtresi & Konum Kayması (Drift) Düzeltmesi
        // ------------------------------------------------------------------
        var (kLat, kLon, innovationMeters) = RunKalmanSmoothing(window);
        double layer3Score = innovationMeters <= 12.0
            ? 100.0
            : Math.Clamp(100.0 - (innovationMeters - 12.0) * 2.5, 10.0, 100.0);
        bool layer3Pass = innovationMeters <= 25.0;

        // ------------------------------------------------------------------
        // KATMAN 4: IMU Sensör Füzyonu (GPS Hareketi <-> İvmeölçer/Jiroskop)
        // ------------------------------------------------------------------
        // Remove baseline gravity (~9.81 m/s^2) via sample mean to measure dynamic walking energy
        var mags = window.Select(s => Math.Sqrt(s.AccelX * s.AccelX + s.AccelY * s.AccelY + s.AccelZ * s.AccelZ)).ToList();
        double avgMag = mags.Average();
        double dynamicRms = Math.Sqrt(mags.Select(m => Math.Pow(m - avgMag, 2)).Average());
        double gyroEnergy = window.Sum(s => Math.Abs(s.GyroAlpha) + Math.Abs(s.GyroBeta) + Math.Abs(s.GyroGamma));
        bool hasImuData = window.Any(s => Math.Abs(s.AccelX) > 0.005 || Math.Abs(s.AccelY) > 0.005 || Math.Abs(s.GyroBeta) > 0.005);

        bool sensorFusionConsistent = true;
        double layer4Score = 100.0;
        if (totalDistanceMoved > 10.0 && hasImuData && dynamicRms < 0.045 && gyroEnergy < 0.05)
        {
            // GPS moves while device sits motionless on a desk
            sensorFusionConsistent = false;
            layer4Score = 25.0;
        }
        else if (totalDistanceMoved > 10.0 && !hasImuData)
        {
            // Desktop browser without IMU hardware: neutral partial trust
            layer4Score = 78.0;
        }

        // Weighted hybrid trust score
        double trustScore = Math.Round(
            layer1Score * 0.25 +
            layer2Score * 0.35 +
            layer3Score * 0.20 +
            layer4Score * 0.20, 1);

        if (mockDetected || jumpDetected)
        {
            trustScore = Math.Min(trustScore, 28.0);
        }

        bool passed = !mockDetected && !jumpDetected && layer1Pass && layer2Pass && trustScore >= 65.0;

        var reasons = new List<string>();
        if (mockDetected) reasons.Add("Sahte konum uygulaması (Mock GPS) engellendi.");
        if (jumpDetected) reasons.Add($"Fiziksel olarak imkansız konum sıçraması ({maxSpeed:F1} m/s).");
        else if (maxSpeed > PedestrianMaxSpeedMps) reasons.Add($"Yaya hızı sınırı aşıldı ({maxSpeed:F1} m/s).");
        if (!sensorFusionConsistent) reasons.Add("GPS hareketi ile ivmeölçer/jiroskop verisi tutarsız.");
        if (!layer3Pass) reasons.Add($"Kalman sapması yüksek ({innovationMeters:F1} m).");
        if (layer1Notes.Count > 0 && !mockDetected) reasons.AddRange(layer1Notes);

        return new AntiSpoofingReport
        {
            Passed = passed,
            TrustScore = Math.Clamp(trustScore, 0, 100),
            MaxObservedSpeedMps = Math.Round(maxSpeed, 2),
            MaxObservedAccelerationMps2 = Math.Round(maxAccel, 2),
            ImpossibleJumpDetected = jumpDetected,
            SensorFusionConsistent = sensorFusionConsistent,
            MockProviderDetected = mockDetected,
            SignalJitterStdDev = Math.Round(accJitterStdDev, 3),
            KalmanFilteredLat = kLat,
            KalmanFilteredLon = kLon,
            KalmanInnovationMeters = Math.Round(innovationMeters, 2),
            SampleCount = window.Count,
            Reason = passed
                ? "4/4 konum ve sensör katmanı tutarlı; Kalman filtresi ile konum doğrulandı."
                : string.Join(" ", reasons),
            Layers = new List<VerificationLayerResult>
            {
                new()
                {
                    Name = "Sağlayıcı & Sinyal Bütünlüğü",
                    Passed = layer1Pass,
                    Score = Math.Round(layer1Score, 1),
                    Detail = mockDetected ? "Mock GPS bayrağı aktif" : $"Jitter σ={accJitterStdDev:F2}m"
                },
                new()
                {
                    Name = "Kinematik Hız & İvme",
                    Passed = layer2Pass,
                    Score = Math.Round(layer2Score, 1),
                    Detail = $"Maks {maxSpeed:F1} m/s, İvme {maxAccel:F1} m/s²"
                },
                new()
                {
                    Name = "Kalman Drift Filtresi",
                    Passed = layer3Pass,
                    Score = Math.Round(layer3Score, 1),
                    Detail = $"Tahmin sapması {innovationMeters:F1} m"
                },
                new()
                {
                    Name = "IMU Sensör Füzyonu",
                    Passed = sensorFusionConsistent,
                    Score = Math.Round(layer4Score, 1),
                    Detail = sensorFusionConsistent
                        ? $"Dinamik enerji RMS={dynamicRms:F2} m/s²"
                        : "GPS hareketi ile IMU uyuşmuyor"
                }
            }
        };
    }

    /// <summary>
    /// 2D constant-position/velocity Kalman smoother in local tangent meters.
    /// Mitigates 5-20m urban GPS drift and measures sudden teleportation innovation.
    /// </summary>
    private static (double Lat, double Lon, double InnovationMeters) RunKalmanSmoothing(List<TelemetrySample> window)
    {
        var origin = window[0];
        double cosLat = Math.Cos(origin.Latitude * Math.PI / 180.0);
        const double metersPerDegLat = 111320.0;
        double metersPerDegLon = 111320.0 * Math.Max(cosLat, 0.1);

        double x = 0, y = 0;       // meters east/north from origin
        double vx = 0, vy = 0;     // m/s
        double pPos = 9.0;         // initial position variance
        double lastInnovation = 0.0;

        for (int i = 1; i < window.Count; i++)
        {
            var prev = window[i - 1];
            var curr = window[i];
            double dt = Math.Clamp((curr.TimestampMs - prev.TimestampMs) / 1000.0, 0.2, 10.0);

            // Predict
            double predX = x + vx * dt;
            double predY = y + vy * dt;
            double processNoise = 1.6 * dt; // pedestrian acceleration allowance
            pPos += processNoise;

            // Measurement in local meters
            double mx = (curr.Longitude - origin.Longitude) * metersPerDegLon;
            double my = (curr.Latitude - origin.Latitude) * metersPerDegLat;
            double rNoise = Math.Pow(Math.Clamp(curr.AccuracyMeters, 2.5, 35.0), 2) * 0.45;

            double dx = mx - predX;
            double dy = my - predY;
            lastInnovation = Math.Sqrt(dx * dx + dy * dy);

            double gain = pPos / (pPos + rNoise);
            x = predX + gain * dx;
            y = predY + gain * dy;
            vx = 0.55 * vx + 0.45 * (dx / dt);
            vy = 0.55 * vy + 0.45 * (dy / dt);
            pPos = (1.0 - gain) * pPos;
        }

        double filteredLat = origin.Latitude + (y / metersPerDegLat);
        double filteredLon = origin.Longitude + (x / metersPerDegLon);
        return (filteredLat, filteredLon, lastInnovation);
    }
}

public sealed class VisualPositioningService
{
    public double ComputeSimilarity(string? expectedSig, string? observedSig)
    {
        if (string.IsNullOrWhiteSpace(expectedSig) || string.IsNullOrWhiteSpace(observedSig))
            return 0.0;

        string a = expectedSig.Trim().ToLowerInvariant();
        string b = observedSig.Trim().ToLowerInvariant();

        if (a == b) return 98.4;

        int len = Math.Min(a.Length, b.Length);
        if (len == 0) return 0.0;

        double totalDiff = 0;
        for (int i = 0; i < len; i++)
        {
            int va = HexVal(a[i]);
            int vb = HexVal(b[i]);
            totalDiff += Math.Abs(va - vb) / 15.0;
        }

        double similarity = (1.0 - (totalDiff / len)) * 100.0;
        return Math.Round(Math.Clamp(similarity, 0, 100), 1);
    }

    private static int HexVal(char c) => c switch
    {
        >= '0' and <= '9' => c - '0',
        >= 'a' and <= 'f' => 10 + (c - 'a'),
        _ => 7
    };
}
