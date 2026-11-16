using System.Globalization;
using System.Text.Json;
using CapsuleApi.Models;

namespace CapsuleApi.Services;

public sealed class WikimediaMediaService
{
    private readonly HttpClient _http;

    private static readonly List<NearbyMediaItem> CuratedFallbackMedia = new()
    {
        new NearbyMediaItem
        {
            Title = "İstanbul Üniversitesi Tarihi Ana Kapısı (Beyazıt)",
            ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/a/aa/%C4%B0stanbul_%C3%9Cniversitesi.JPG",
            Source = "Wikimedia Commons",
            Description = "Beyazıt Meydanı girişindeki tarihi üniversite kapısı ve kampüs rotası.",
            Latitude = 41.0119,
            Longitude = 28.9639
        },
        new NearbyMediaItem
        {
            Title = "İstanbul Üniversitesi Merkez Kampüsü Bahçesi",
            ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/1/1e/Istanbul_University_campus_March_2008c.JPG",
            Source = "Wikimedia Commons",
            Description = "Kampüs yürüyüş rotası ve açık alan etkinlik merkezi.",
            Latitude = 41.0124,
            Longitude = 28.9634
        },
        new NearbyMediaItem
        {
            Title = "Süleymaniye Külliyesi ve Kültür Rotası",
            ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/2/2b/S%C3%BCleymaniye_Camii.jpg",
            Source = "Wikimedia Commons",
            Description = "Mimar Sinan'ın eseri, kültürel miras zaman kapsülü durağı.",
            Latitude = 41.0161,
            Longitude = 28.9642
        },
        new NearbyMediaItem
        {
            Title = "Galata Kulesi ve Çevresi",
            ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg",
            Source = "Wikimedia Commons",
            Description = "Tarihi yarımada ve Haliç manzaralı keşif noktası.",
            Latitude = 41.0256,
            Longitude = 28.9741
        },
        new NearbyMediaItem
        {
            Title = "Kız Kulesi Sahil Yürüyüş Hattı",
            ImageUrl = "https://upload.wikimedia.org/wikipedia/commons/b/b3/K%C4%B1zKulesi.jpg",
            Source = "Wikimedia Commons",
            Description = "Boğaz kıyısı yürüyüş ve koşu rotası dijital kapsül durağı.",
            Latitude = 41.0211,
            Longitude = 29.0041
        }
    };

    public WikimediaMediaService(HttpClient http)
    {
        _http = http;
        _http.Timeout = TimeSpan.FromSeconds(6);
        if (!_http.DefaultRequestHeaders.UserAgent.Any())
        {
            _http.DefaultRequestHeaders.UserAgent.ParseAdd("KapsulAR-2209A/1.0 (https://github.com/kapsular-webar)");
        }
    }

    public async Task<List<NearbyMediaItem>> SearchMediaAsync(string? query, double? lat, double? lon, CancellationToken ct = default)
    {
        var results = new List<NearbyMediaItem>();

        try
        {
            if (!string.IsNullOrWhiteSpace(query))
            {
                var q = Uri.EscapeDataString(query.Trim());
                var url = $"https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch={q}&gsrnamespace=6&gsrlimit=8&prop=imageinfo&iiprop=url|mime|extmetadata&iiurlwidth=800&format=json";
                using var resp = await _http.GetAsync(url, ct);
                if (resp.IsSuccessStatusCode)
                {
                    await using var stream = await resp.Content.ReadAsStreamAsync(ct);
                    using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
                    if (doc.RootElement.TryGetProperty("query", out var qEl) &&
                        qEl.TryGetProperty("pages", out var pages))
                    {
                        foreach (var prop in pages.EnumerateObject())
                        {
                            var item = ParseCommonsPage(prop.Value);
                            if (item != null) results.Add(item);
                        }
                    }
                }
            }
            else if (lat.HasValue && lon.HasValue)
            {
                results.AddRange(await FetchWikipediaGeosearchAsync(lat.Value, lon.Value, ct));
            }
        }
        catch
        {
            // Network unavailable or API timeout -> graceful fallback below
        }

        return results.Count == 0 ? CuratedFallbackMedia : results;
    }

    public async Task<List<NearbyMediaItem>> GetNearbyPopularPlacesAsync(double lat, double lon, CancellationToken ct = default)
    {
        var combined = new List<NearbyMediaItem>();
        var wikiTask = FetchWikipediaGeosearchAsync(lat, lon, ct);
        var osmTask = FetchOverpassPoisAsync(lat, lon, ct);

        await Task.WhenAll(wikiTask, osmTask);
        combined.AddRange(wikiTask.Result);
        combined.AddRange(osmTask.Result);

        // Deduplicate by normalized title and sort by distance
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var unique = new List<NearbyMediaItem>();
        foreach (var item in combined)
        {
            if (!item.Latitude.HasValue || !item.Longitude.HasValue) continue;
            var key = item.Title.Trim();
            if (string.IsNullOrWhiteSpace(key) || !seen.Add(key)) continue;

            item.DistanceMeters = Math.Round(GeoMath.HaversineMeters(lat, lon, item.Latitude.Value, item.Longitude.Value), 1);
            unique.Add(item);
        }

        if (unique.Count == 0)
        {
            foreach (var fb in CuratedFallbackMedia)
            {
                unique.Add(new NearbyMediaItem
                {
                    Title = fb.Title,
                    ImageUrl = fb.ImageUrl,
                    Source = fb.Source,
                    Description = fb.Description,
                    Latitude = fb.Latitude,
                    Longitude = fb.Longitude,
                    DistanceMeters = fb.Latitude.HasValue && fb.Longitude.HasValue
                        ? Math.Round(GeoMath.HaversineMeters(lat, lon, fb.Latitude.Value, fb.Longitude.Value), 1)
                        : null
                });
            }
        }

        return unique.OrderBy(p => p.DistanceMeters ?? double.MaxValue).Take(14).ToList();
    }

    private async Task<List<NearbyMediaItem>> FetchWikipediaGeosearchAsync(double lat, double lon, CancellationToken ct)
    {
        var items = new List<NearbyMediaItem>();
        try
        {
            var latStr = lat.ToString(CultureInfo.InvariantCulture);
            var lonStr = lon.ToString(CultureInfo.InvariantCulture);
            var url = $"https://tr.wikipedia.org/w/api.php?action=query&generator=geosearch&ggscoord={latStr}|{lonStr}&ggsradius=3000&ggslimit=10&prop=pageimages|coordinates&pithumbsize=800&format=json";
            using var resp = await _http.GetAsync(url, ct);
            if (!resp.IsSuccessStatusCode) return items;

            await using var stream = await resp.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            if (!doc.RootElement.TryGetProperty("query", out var qEl) ||
                !qEl.TryGetProperty("pages", out var pages))
                return items;

            foreach (var prop in pages.EnumerateObject())
            {
                var val = prop.Value;
                string title = val.TryGetProperty("title", out var t) ? t.GetString() ?? "Mekan" : "Mekan";
                string img = "https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg";
                if (val.TryGetProperty("thumbnail", out var thumb) &&
                    thumb.TryGetProperty("source", out var src))
                {
                    img = src.GetString() ?? img;
                }

                double? pLat = null, pLon = null;
                if (val.TryGetProperty("coordinates", out var coords) && coords.GetArrayLength() > 0)
                {
                    var c0 = coords[0];
                    if (c0.TryGetProperty("lat", out var clat)) pLat = clat.GetDouble();
                    if (c0.TryGetProperty("lon", out var clon)) pLon = clon.GetDouble();
                }

                items.Add(new NearbyMediaItem
                {
                    Title = title,
                    ImageUrl = img,
                    Source = "Wikipedia Geosearch",
                    Description = "Konuma yakın kültürel / tarihi nokta",
                    Latitude = pLat,
                    Longitude = pLon
                });
            }
        }
        catch
        {
            // Ignore transient failures
        }
        return items;
    }

    private async Task<List<NearbyMediaItem>> FetchOverpassPoisAsync(double lat, double lon, CancellationToken ct)
    {
        var items = new List<NearbyMediaItem>();
        try
        {
            var latStr = lat.ToString(CultureInfo.InvariantCulture);
            var lonStr = lon.ToString(CultureInfo.InvariantCulture);
            // Query popular public places (parks, cafes, libraries, museums, universities, monuments) within 1.8km
            var query = $"[out:json][timeout:4];(node[\"name\"][\"amenity\"~\"cafe|library|museum|university|theatre|arts_centre\"](around:1800,{latStr},{lonStr});node[\"name\"][\"tourism\"~\"attraction|museum|viewpoint\"](around:1800,{latStr},{lonStr});node[\"name\"][\"leisure\"=\"park\"](around:1800,{latStr},{lonStr}););out body 12;";
            var content = new FormUrlEncodedContent(new[] { new KeyValuePair<string, string>("data", query) });

            using var resp = await _http.PostAsync("https://overpass-api.de/api/interpreter", content, ct);
            if (!resp.IsSuccessStatusCode) return items;

            await using var stream = await resp.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            if (!doc.RootElement.TryGetProperty("elements", out var elements)) return items;

            foreach (var el in elements.EnumerateArray())
            {
                if (!el.TryGetProperty("lat", out var elLat) || !el.TryGetProperty("lon", out var elLon))
                    continue;
                if (!el.TryGetProperty("tags", out var tags) || !tags.TryGetProperty("name", out var nameEl))
                    continue;

                string name = nameEl.GetString() ?? "";
                if (string.IsNullOrWhiteSpace(name)) continue;

                string kind = tags.TryGetProperty("amenity", out var am) ? am.GetString() ?? "Mekan"
                    : tags.TryGetProperty("tourism", out var tr) ? tr.GetString() ?? "Gezi Noktası"
                    : tags.TryGetProperty("leisure", out var ls) ? ls.GetString() ?? "Park"
                    : "Popüler Nokta";

                string imageUrl = kind switch
                {
                    "cafe" => "https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg",
                    "university" or "library" => "https://upload.wikimedia.org/wikipedia/commons/1/1e/Istanbul_University_campus_March_2008c.JPG",
                    "museum" or "attraction" => "https://upload.wikimedia.org/wikipedia/commons/2/2b/S%C3%BCleymaniye_Camii.jpg",
                    _ => "https://upload.wikimedia.org/wikipedia/commons/b/b3/K%C4%B1zKulesi.jpg"
                };

                items.Add(new NearbyMediaItem
                {
                    Title = name,
                    ImageUrl = imageUrl,
                    Source = $"OpenStreetMap ({kind})",
                    Description = $"Çevrenizdeki popüler nokta ({kind})",
                    Latitude = elLat.GetDouble(),
                    Longitude = elLon.GetDouble()
                });
            }
        }
        catch
        {
            // Overpass rate limit / offline fallback handled cleanly
        }
        return items;
    }

    private static NearbyMediaItem? ParseCommonsPage(JsonElement page)
    {
        if (!page.TryGetProperty("imageinfo", out var infoArr) || infoArr.GetArrayLength() == 0)
            return null;

        var info = infoArr[0];
        string mime = info.TryGetProperty("mime", out var m) ? m.GetString() ?? "" : "";
        if (!mime.StartsWith("image/", StringComparison.OrdinalIgnoreCase) || mime.Contains("svg"))
            return null;

        string? imgUrl = info.TryGetProperty("thumburl", out var thumb)
            ? thumb.GetString()
            : (info.TryGetProperty("url", out var raw) ? raw.GetString() : null);

        if (string.IsNullOrWhiteSpace(imgUrl)) return null;

        string title = page.TryGetProperty("title", out var t) ? (t.GetString() ?? "Görsel").Replace("File:", "") : "Görsel";
        int dotIdx = title.LastIndexOf('.');
        if (dotIdx > 0) title = title[..dotIdx];

        return new NearbyMediaItem
        {
            Title = title.Replace('_', ' '),
            ImageUrl = imgUrl,
            Source = "Wikimedia Commons",
            Description = "Wikimedia Commons açık lisanslı mekan fotoğrafı"
        };
    }
}
