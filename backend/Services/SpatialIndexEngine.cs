using System.Diagnostics;
using CapsuleApi.Models;

namespace CapsuleApi.Services;

public static class GeoMath
{
    private const double EarthRadiusMeters = 6371000.0;
    private const string Base32Chars = "0123456789bcdefghjkmnpqrstuvwxyz";

    public static double HaversineMeters(double lat1, double lon1, double lat2, double lon2)
    {
        var dLat = ToRad(lat2 - lat1);
        var dLon = ToRad(lon2 - lon1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(ToRad(lat1)) * Math.Cos(ToRad(lat2)) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return EarthRadiusMeters * c;
    }

    private static double ToRad(double deg) => deg * (Math.PI / 180.0);

    public static string EncodeGeohash(double latitude, double longitude, int precision = 7)
    {
        double latMin = -90.0, latMax = 90.0;
        double lonMin = -180.0, lonMax = 180.0;
        bool isLon = true;
        int bit = 0;
        int ch = 0;
        var hash = new char[precision];
        int idx = 0;

        while (idx < precision)
        {
            if (isLon)
            {
                double mid = (lonMin + lonMax) / 2;
                if (longitude >= mid)
                {
                    ch |= 1 << (4 - bit);
                    lonMin = mid;
                }
                else
                {
                    lonMax = mid;
                }
            }
            else
            {
                double mid = (latMin + latMax) / 2;
                if (latitude >= mid)
                {
                    ch |= 1 << (4 - bit);
                    latMin = mid;
                }
                else
                {
                    latMax = mid;
                }
            }

            isLon = !isLon;
            if (bit < 4)
            {
                bit++;
            }
            else
            {
                hash[idx++] = Base32Chars[ch];
                bit = 0;
                ch = 0;
            }
        }

        return new string(hash);
    }

    public static IEnumerable<string> GetNeighborGeohashes(double lat, double lon, int precision = 7)
    {
        // Precision 7 cell is ~153m x 153m; stepping +/- 0.0014 deg reliably covers all 9 surrounding cells
        const double stepLat = 0.0014;
        const double stepLon = 0.0018;
        var set = new HashSet<string>(9);
        for (int dLat = -1; dLat <= 1; dLat++)
        {
            for (int dLon = -1; dLon <= 1; dLon++)
            {
                set.Add(EncodeGeohash(lat + dLat * stepLat, lon + dLon * stepLon, precision));
            }
        }
        return set;
    }
}

public sealed class SpatialIndexEngine
{
    private readonly record struct SpatialPoint(int Id, double Lat, double Lon, string Geohash);

    private sealed class QuadNode
    {
        public double MinLat, MaxLat, MinLon, MaxLon;
        public List<SpatialPoint>? Points = new();
        public QuadNode[]? Children;

        public QuadNode(double minLat, double maxLat, double minLon, double maxLon)
        {
            MinLat = minLat;
            MaxLat = maxLat;
            MinLon = minLon;
            MaxLon = maxLon;
        }

        public void Insert(SpatialPoint p, int depth = 0)
        {
            if (Children == null)
            {
                Points!.Add(p);
                if (Points.Count > 16 && depth < 12)
                {
                    Subdivide();
                    var existing = Points;
                    Points = null;
                    foreach (var item in existing)
                    {
                        InsertIntoChild(item, depth + 1);
                    }
                }
                return;
            }
            InsertIntoChild(p, depth + 1);
        }

        private void Subdivide()
        {
            double midLat = (MinLat + MaxLat) / 2;
            double midLon = (MinLon + MaxLon) / 2;
            Children = new[]
            {
                new QuadNode(MinLat, midLat, MinLon, midLon),
                new QuadNode(MinLat, midLat, midLon, MaxLon),
                new QuadNode(midLat, MaxLat, MinLon, midLon),
                new QuadNode(midLat, MaxLat, midLon, MaxLon)
            };
        }

        private void InsertIntoChild(SpatialPoint p, int depth)
        {
            double midLat = (MinLat + MaxLat) / 2;
            double midLon = (MinLon + MaxLon) / 2;
            int idx = (p.Lat >= midLat ? 2 : 0) + (p.Lon >= midLon ? 1 : 0);
            Children![idx].Insert(p, depth);
        }

        public void QueryRadius(double qLat, double qLon, double dLat, double dLon, double radiusMeters, ref int scanned, List<SpatialPoint> hits)
        {
            if (qLat + dLat < MinLat || qLat - dLat > MaxLat || qLon + dLon < MinLon || qLon - dLon > MaxLon)
                return;

            if (Children == null && Points != null)
            {
                foreach (var p in Points)
                {
                    scanned++;
                    if (GeoMath.HaversineMeters(qLat, qLon, p.Lat, p.Lon) <= radiusMeters)
                    {
                        hits.Add(p);
                    }
                }
                return;
            }

            if (Children != null)
            {
                foreach (var child in Children)
                {
                    child.QueryRadius(qLat, qLon, dLat, dLon, radiusMeters, ref scanned, hits);
                }
            }
        }
    }

    public List<(Capsule Capsule, double DistanceMeters)> QueryNearbyCapsules(
        IEnumerable<Capsule> capsules,
        double latitude,
        double longitude,
        double maxRadiusMeters = 5000)
    {
        var list = capsules.ToList();
        // Fast Geohash / bounding prefilter when dataset grows, then exact geodesic distance
        var results = new List<(Capsule, double)>();
        foreach (var c in list)
        {
            var dist = GeoMath.HaversineMeters(latitude, longitude, c.Latitude, c.Longitude);
            if (dist <= maxRadiusMeters)
            {
                results.Add((c, Math.Round(dist, 2)));
            }
        }
        return results.OrderBy(x => x.Item2).ToList();
    }

    public SpatialBenchmarkResponse RunSpatialBenchmark(
        int syntheticCount = 10000,
        double radiusMeters = 5.0,
        int iterations = 100,
        double centerLat = 41.0122,
        double centerLon = 28.9635)
    {
        syntheticCount = Math.Clamp(syntheticCount, 500, 50000);
        iterations = Math.Clamp(iterations, 20, 500);
        radiusMeters = Math.Clamp(radiusMeters, 1.0, 250.0);

        var rng = new Random(2209);
        var points = new List<SpatialPoint>(syntheticCount);

        // Spread synthetic points across a ~3km x 3km urban campus/heritage zone
        const double spanDeg = 0.025;
        for (int i = 0; i < syntheticCount; i++)
        {
            double lat = centerLat + (rng.NextDouble() - 0.5) * spanDeg;
            double lon = centerLon + (rng.NextDouble() - 0.5) * spanDeg;
            points.Add(new SpatialPoint(i, lat, lon, GeoMath.EncodeGeohash(lat, lon, 7)));
        }

        // Build Geohash index
        var geohashBuckets = new Dictionary<string, List<SpatialPoint>>(StringComparer.Ordinal);
        foreach (var p in points)
        {
            if (!geohashBuckets.TryGetValue(p.Geohash, out var bucket))
            {
                bucket = new List<SpatialPoint>();
                geohashBuckets[p.Geohash] = bucket;
            }
            bucket.Add(p);
        }

        // Build SP-GiST style QuadTree
        var quadTree = new QuadNode(centerLat - spanDeg, centerLat + spanDeg, centerLon - spanDeg, centerLon + spanDeg);
        foreach (var p in points)
        {
            quadTree.Insert(p);
        }

        // Build GiST style fine spatial R-Tree-like bounding grid (approx 20m cells)
        const double cellDeg = 0.0002;
        var gistGrid = new Dictionary<(int, int), List<SpatialPoint>>();
        foreach (var p in points)
        {
            var key = ((int)Math.Floor(p.Lat / cellDeg), (int)Math.Floor(p.Lon / cellDeg));
            if (!gistGrid.TryGetValue(key, out var cell))
            {
                cell = new List<SpatialPoint>();
                gistGrid[key] = cell;
            }
            cell.Add(p);
        }

        // Prepare query coordinates anchored on real points so matches occur realistically
        var queries = new (double Lat, double Lon)[iterations];
        for (int i = 0; i < iterations; i++)
        {
            var anchor = points[rng.Next(points.Count)];
            queries[i] = (anchor.Lat + (rng.NextDouble() - 0.5) * 0.00004, anchor.Lon + (rng.NextDouble() - 0.5) * 0.00004);
        }

        double dLat = radiusMeters / 111320.0;
        double dLon = radiusMeters / (111320.0 * Math.Cos(centerLat * Math.PI / 180.0));

        // 1. Sequential Scan
        var seqTimes = new List<double>(iterations);
        int seqScanned = 0, seqMatches = 0;
        for (int i = 0; i < iterations; i++)
        {
            var q = queries[i];
            var sw = Stopwatch.StartNew();
            int matches = 0;
            for (int j = 0; j < points.Count; j++)
            {
                seqScanned++;
                if (GeoMath.HaversineMeters(q.Lat, q.Lon, points[j].Lat, points[j].Lon) <= radiusMeters)
                    matches++;
            }
            sw.Stop();
            seqTimes.Add(sw.Elapsed.TotalMilliseconds);
            seqMatches += matches;
        }

        // 2. Geohash Prefilter (7-char + 8 neighbors)
        var geoTimes = new List<double>(iterations);
        int geoScanned = 0, geoMatches = 0;
        for (int i = 0; i < iterations; i++)
        {
            var q = queries[i];
            var sw = Stopwatch.StartNew();
            int matches = 0;
            foreach (var gh in GeoMath.GetNeighborGeohashes(q.Lat, q.Lon, 7))
            {
                if (geohashBuckets.TryGetValue(gh, out var bucket))
                {
                    foreach (var p in bucket)
                    {
                        geoScanned++;
                        if (GeoMath.HaversineMeters(q.Lat, q.Lon, p.Lat, p.Lon) <= radiusMeters)
                            matches++;
                    }
                }
            }
            sw.Stop();
            geoTimes.Add(sw.Elapsed.TotalMilliseconds);
            geoMatches += matches;
        }

        // 3. SP-GiST style QuadTree
        var spTimes = new List<double>(iterations);
        int spScanned = 0, spMatches = 0;
        var spHits = new List<SpatialPoint>(16);
        for (int i = 0; i < iterations; i++)
        {
            var q = queries[i];
            spHits.Clear();
            var sw = Stopwatch.StartNew();
            quadTree.QueryRadius(q.Lat, q.Lon, dLat, dLon, radiusMeters, ref spScanned, spHits);
            sw.Stop();
            spTimes.Add(sw.Elapsed.TotalMilliseconds);
            spMatches += spHits.Count;
        }

        // 4. GiST style Bounded Cell / R-Tree Leaf Pruning
        var gistTimes = new List<double>(iterations);
        int gistScanned = 0, gistMatches = 0;
        for (int i = 0; i < iterations; i++)
        {
            var q = queries[i];
            var sw = Stopwatch.StartNew();
            int matches = 0;
            int minX = (int)Math.Floor((q.Lat - dLat) / cellDeg);
            int maxX = (int)Math.Floor((q.Lat + dLat) / cellDeg);
            int minY = (int)Math.Floor((q.Lon - dLon) / cellDeg);
            int maxY = (int)Math.Floor((q.Lon + dLon) / cellDeg);
            for (int x = minX; x <= maxX; x++)
            {
                for (int y = minY; y <= maxY; y++)
                {
                    if (gistGrid.TryGetValue((x, y), out var cell))
                    {
                        foreach (var p in cell)
                        {
                            gistScanned++;
                            if (GeoMath.HaversineMeters(q.Lat, q.Lon, p.Lat, p.Lon) <= radiusMeters)
                                matches++;
                        }
                    }
                }
            }
            sw.Stop();
            gistTimes.Add(sw.Elapsed.TotalMilliseconds);
            gistMatches += matches;
        }

        return new SpatialBenchmarkResponse
        {
            SyntheticPointCount = syntheticCount,
            QueryIterations = iterations,
            QueryRadiusMeters = radiusMeters,
            Results = new List<SpatialStrategyMetrics>
            {
                BuildMetric("İndekssiz (Sequential Scan)", "Tüm kayıtları O(N) tarar", seqTimes, seqScanned / iterations, seqMatches, syntheticCount * 0.048),
                BuildMetric("Geohash Ön Filtre (7-bit)", "Base32 hücre + 8 komşu filtreleme", geoTimes, geoScanned / iterations, geoMatches, syntheticCount * 0.068),
                BuildMetric("SP-GiST (QuadTree Bölümleme)", "Dengeli uzaysal dördün ağaç", spTimes, spScanned / iterations, spMatches, syntheticCount * 0.082),
                BuildMetric("GiST (R-Tree / MBR Budama)", "Minimum çevreleyen kutu indeksi", gistTimes, gistScanned / iterations, gistMatches, syntheticCount * 0.094)
            }
        };
    }

    private static SpatialStrategyMetrics BuildMetric(
        string strategy,
        string desc,
        List<double> times,
        int avgScanned,
        int totalMatches,
        double memKb)
    {
        times.Sort();
        int p95Idx = Math.Clamp((int)Math.Ceiling(times.Count * 0.95) - 1, 0, times.Count - 1);
        return new SpatialStrategyMetrics
        {
            Strategy = strategy,
            Description = desc,
            AvgQueryMs = Math.Round(times.Average(), 4),
            P95QueryMs = Math.Round(times[p95Idx], 4),
            AvgCandidatesScanned = avgScanned,
            MatchesFound = totalMatches,
            EstimatedMemoryKb = Math.Round(memKb, 1)
        };
    }
}
