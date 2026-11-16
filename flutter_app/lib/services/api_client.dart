import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/capsule_models.dart';
import 'location_sensor_service.dart';

class ApiClient {
  String baseUrl;
  bool isBackendOnline = false;

  ApiClient({String? initialUrl})
      : baseUrl = initialUrl ?? AppConfig.defaultApiBaseUrl;

  Future<List<TimeCapsule>> fetchNearbyCapsules({
    required double lat,
    required double lon,
    String category = 'Tümü',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/capsules').replace(queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'radiusMeters': '50000',
        if (category != 'Tümü') 'category': category,
      });

      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        isBackendOnline = true;
        final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
        final list = data
            .map((e) => TimeCapsule.fromJson(e as Map<String, dynamic>))
            .toList();
        await _cacheCapsules(resp.body);
        return list;
      }
    } catch (_) {
      isBackendOnline = false;
    }

    // Offline PWA Service Worker / Local Storage fallback
    return _loadCachedOrSeeded(lat, lon, category);
  }

  Future<TimeCapsule?> createCapsule(Map<String, dynamic> payload) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/capsules'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 201 || resp.statusCode == 200) {
        isBackendOnline = true;
        return TimeCapsule.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      isBackendOnline = false;
    }
    return null;
  }

  Future<UnlockAttemptResult> attemptUnlock({
    required String capsuleId,
    required List<TelemetrySample> telemetryWindow,
    required String visualSignature,
    bool bypassVisualInDemo = false,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/capsules/unlock'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': 'pwa-user',
              'capsuleId': capsuleId,
              'telemetryWindow': telemetryWindow.map((t) => t.toJson()).toList(),
              'visualSignature': visualSignature,
              'bypassVisualInDemo': bypassVisualInDemo,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        isBackendOnline = true;
        return UnlockAttemptResult.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      isBackendOnline = false;
    }

    return const UnlockAttemptResult(
      unlocked: false,
      arReady: false,
      distanceMeters: 0,
      visualMatchScore: 0,
      antiSpoofing: AntiSpoofingReport(
        passed: false,
        trustScore: 0,
        maxObservedSpeedMps: 0,
        maxObservedAccelerationMps2: 0,
        impossibleJumpDetected: false,
        sensorFusionConsistent: true,
        sampleCount: 0,
        reason: 'API sunucusuna ulaşılamadı. Backend bağlantısını kontrol edin.',
      ),
      message: 'Backend sunucusu çevrimdışı (localhost:5088).',
    );
  }

  Future<SpatialBenchmarkData?> runSpatialBenchmark({
    int count = 10000,
    double radius = 5.0,
    int iterations = 80,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/spatial/benchmark').replace(
        queryParameters: {
          'count': count.toString(),
          'radius': radius.toString(),
          'iterations': iterations.toString(),
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        isBackendOnline = true;
        return SpatialBenchmarkData.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      isBackendOnline = false;
    }
    return null;
  }

  Future<AntiSpoofingReport?> evaluateAntiSpoof(List<TelemetrySample> window) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/antispoof/evaluate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(window.map((e) => e.toJson()).toList()),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        isBackendOnline = true;
        return AntiSpoofingReport.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      isBackendOnline = false;
    }
    return null;
  }

  Future<List<NearbyMediaItem>> fetchNearbyOrSearchMedia({
    String? query,
    double? lat,
    double? lon,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/media/nearby').replace(
        queryParameters: {
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          if (lat != null) 'lat': lat.toString(),
          if (lon != null) 'lon': lon.toString(),
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final List<dynamic> list = jsonDecode(resp.body) as List<dynamic>;
        return list
            .map((e) => NearbyMediaItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Direct Wikimedia Commons client fallback when backend is not reachable
      try {
        final q = Uri.encodeQueryComponent(
          (query == null || query.trim().isEmpty) ? 'Istanbul University' : query.trim(),
        );
        final directUri = Uri.parse(
          'https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=$q&gsrnamespace=6&gsrlimit=6&prop=imageinfo&iiprop=url|mime&iiurlwidth=700&format=json&origin=*',
        );
        final resp = await http.get(directUri).timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final Map<String, dynamic> root = jsonDecode(resp.body) as Map<String, dynamic>;
          final pages = (root['query']?['pages'] as Map<String, dynamic>?) ?? {};
          final items = <NearbyMediaItem>[];
          for (final entry in pages.values) {
            final map = entry as Map<String, dynamic>;
            final infoList = (map['imageinfo'] as List?) ?? [];
            if (infoList.isEmpty) continue;
            final info = infoList.first as Map<String, dynamic>;
            final mime = (info['mime'] ?? '').toString();
            if (!mime.startsWith('image/') || mime.contains('svg')) continue;
            final url = (info['thumburl'] ?? info['url'] ?? '').toString();
            if (url.isEmpty) continue;
            items.add(NearbyMediaItem(
              title: (map['title'] ?? 'Wikimedia').toString().replaceFirst('File:', ''),
              imageUrl: url,
              source: 'Wikimedia Commons',
              description: 'Açık lisanslı mekan fotoğrafı',
            ));
          }
          if (items.isNotEmpty) return items;
        }
      } catch (_) {}
    }

    return const [
      NearbyMediaItem(
        title: 'İstanbul Üniversitesi Tarihi Kapı',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/a/aa/%C4%B0stanbul_%C3%9Cniversitesi.JPG',
        source: 'Wikimedia Commons',
        description: 'Beyazıt kampüsü giriş kapısı',
        latitude: 41.0119,
        longitude: 28.9639,
      ),
      NearbyMediaItem(
        title: 'Süleymaniye Külliyesi',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/2/2b/S%C3%BCleymaniye_Camii.jpg',
        source: 'Wikimedia Commons',
        description: 'Kültürel miras keşif noktası',
        latitude: 41.0161,
        longitude: 28.9642,
      ),
      NearbyMediaItem(
        title: 'Galata Kulesi',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg',
        source: 'Wikimedia Commons',
        description: 'Tarihi yürüyüş rotası',
        latitude: 41.0256,
        longitude: 28.9741,
      ),
    ];
  }

  Future<List<NearbyMediaItem>> fetchNearbyPopularPlaces({
    required double lat,
    required double lon,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/places/nearby').replace(
        queryParameters: {
          'lat': lat.toString(),
          'lon': lon.toString(),
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final List<dynamic> list = jsonDecode(resp.body) as List<dynamic>;
        final items = list
            .map((e) => NearbyMediaItem.fromJson(e as Map<String, dynamic>))
            .where((e) => e.latitude != null && e.longitude != null)
            .toList();
        if (items.isNotEmpty) return items;
      }
    } catch (_) {}

    // Direct Wikipedia Geosearch fallback for live nearby popular places
    try {
      final geoUri = Uri.parse(
        'https://tr.wikipedia.org/w/api.php?action=query&generator=geosearch'
        '&ggscoord=$lat|$lon&ggsradius=2500&ggslimit=10'
        '&prop=pageimages|coordinates&pithumbsize=600&format=json&origin=*',
      );
      final resp = await http.get(geoUri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final Map<String, dynamic> root = jsonDecode(resp.body) as Map<String, dynamic>;
        final pages = (root['query']?['pages'] as Map<String, dynamic>?) ?? {};
        final places = <NearbyMediaItem>[];
        for (final entry in pages.values) {
          final map = entry as Map<String, dynamic>;
          final coords = (map['coordinates'] as List?) ?? [];
          if (coords.isEmpty) continue;
          final c0 = coords.first as Map<String, dynamic>;
          final pLat = (c0['lat'] as num?)?.toDouble();
          final pLon = (c0['lon'] as num?)?.toDouble();
          if (pLat == null || pLon == null) continue;
          final thumb = (map['thumbnail']?['source'] ?? '').toString();
          final dist = LocationSensorService.distanceMeters(lat, lon, pLat, pLon);
          places.add(NearbyMediaItem(
            title: (map['title'] ?? 'Popüler Yer').toString(),
            imageUrl: thumb.isNotEmpty
                ? thumb
                : 'https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg',
            source: 'Wikipedia Geosearch',
            description: 'Konumunuza yakın popüler mekan',
            latitude: pLat,
            longitude: pLon,
            distanceMeters: double.parse(dist.toStringAsFixed(0)),
          ));
        }
        places.sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));
        if (places.isNotEmpty) return places;
      }
    } catch (_) {}

    return [
      NearbyMediaItem(
        title: 'İstanbul Üniversitesi Kapısı',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/a/aa/%C4%B0stanbul_%C3%9Cniversitesi.JPG',
        source: 'Popüler Nokta',
        description: 'Tarihi kampüs girişi',
        latitude: 41.0119,
        longitude: 28.9639,
        distanceMeters: LocationSensorService.distanceMeters(lat, lon, 41.0119, 28.9639).roundToDouble(),
      ),
      NearbyMediaItem(
        title: 'Süleymaniye Külliyesi',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/2/2b/S%C3%BCleymaniye_Camii.jpg',
        source: 'Popüler Nokta',
        description: 'Kültürel miras durağı',
        latitude: 41.0161,
        longitude: 28.9642,
        distanceMeters: LocationSensorService.distanceMeters(lat, lon, 41.0161, 28.9642).roundToDouble(),
      ),
      NearbyMediaItem(
        title: 'Galata Kulesi',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/6/60/Istanbul_Galata_%2854527446009%29.jpg',
        source: 'Popüler Nokta',
        description: 'Şehir manzara noktası',
        latitude: 41.0256,
        longitude: 28.9741,
        distanceMeters: LocationSensorService.distanceMeters(lat, lon, 41.0256, 28.9741).roundToDouble(),
      ),
    ];
  }

  Future<ExperimentSummary?> fetchExperimentSummary() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/api/experiments/summary'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        isBackendOnline = true;
        return ExperimentSummary.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      isBackendOnline = false;
    }
    return null;
  }

  Future<void> logActivity({required int stepsAdded, required double distanceAdded}) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/api/activity'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': 'pwa-user',
              'group': 'Deney Grubu (WebAR)',
              'stepsAdded': stepsAdded,
              'distanceMetersAdded': distanceAdded,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<double?> submitSusTam({
    required String group,
    required List<int> susAnswers,
    required double tamUsefulness,
    required double tamEaseOfUse,
    required double tamIntention,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/experiments/sus-tam'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': 'pwa-user',
              'group': group,
              'susAnswers': susAnswers,
              'tamPerceivedUsefulness': tamUsefulness,
              'tamEaseOfUse': tamEaseOfUse,
              'tamBehavioralIntention': tamIntention,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return (data['susScore'] as num?)?.toDouble();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _cacheCapsules(String rawJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_capsules_v1', rawJson);
  }

  Future<List<TimeCapsule>> _loadCachedOrSeeded(
    double lat,
    double lon,
    String category,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_capsules_v1');
    List<TimeCapsule> items;
    if (cached != null) {
      final List<dynamic> decoded = jsonDecode(cached) as List<dynamic>;
      items = decoded
          .map((e) => TimeCapsule.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      items = _fallbackSeededCapsules();
    }

    final filtered = category == 'Tümü'
        ? items
        : items.where((c) => c.category == category).toList();

    final computed = filtered.map((c) {
      final d = LocationSensorService.distanceMeters(lat, lon, c.latitude, c.longitude);
      return TimeCapsule(
        id: c.id,
        title: c.title,
        description: c.description,
        category: c.category,
        contentType: c.contentType,
        latitude: c.latitude,
        longitude: c.longitude,
        unlockRadiusMeters: c.unlockRadiusMeters,
        arTriggerRadiusMeters: c.arTriggerRadiusMeters,
        locationName: c.locationName,
        imageUrl: c.imageUrl,
        noteText: c.noteText,
        pixelArtGrid: c.pixelArtGrid,
        audioDurationSec: c.audioDurationSec,
        audioWaveform: c.audioWaveform,
        visualSignature: c.visualSignature,
        isEncrypted: c.isEncrypted,
        passcodeHint: c.passcodeHint,
        createdBy: c.createdBy,
        createdAt: c.createdAt,
        unlockCount: c.unlockCount,
        geohash: c.geohash,
        distanceMeters: double.parse(d.toStringAsFixed(1)),
        inArRange: d <= c.arTriggerRadiusMeters,
        inUnlockRange: d <= c.unlockRadiusMeters,
      );
    }).toList();

    computed.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return computed;
  }

  static List<TimeCapsule> _fallbackSeededCapsules() {
    return [
      TimeCapsule(
        id: 'cap-beyazit',
        title: '1933 Kampüs Hafızası',
        description: 'Tarihi ana kapı önünde üniversite tarihinden kısa bir sesli anı.',
        category: 'Kültürel Miras',
        contentType: 'audio',
        latitude: 41.0119,
        longitude: 28.9639,
        unlockRadiusMeters: 5.0,
        arTriggerRadiusMeters: 15.0,
        locationName: 'İstanbul Üniversitesi Tarihi Kapı',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/a/aa/%C4%B0stanbul_%C3%9Cniversitesi.JPG',
        noteText: 'Darülfünun\'dan günümüze bu taş kapıdan geçen binlerce öğrencinin ayak izi burada saklı.',
        audioDurationSec: 18,
        audioWaveform: const [0.2, 0.5, 0.8, 0.9, 0.6, 0.4, 0.85, 0.7, 0.5, 0.3],
        visualSignature: 'b8d2e4c19a7f5310',
        isEncrypted: false,
        createdBy: 'Tarih Kulübü',
        createdAt: DateTime.now(),
        unlockCount: 27,
        geohash: 'sxk97b2',
      ),
      TimeCapsule(
        id: 'cap-suleymaniye',
        title: 'Mimar Sinan Akustik Rotası',
        description: 'Süleymaniye avlusunda kubbe akustiğini anlatan görsel kapsül.',
        category: 'Kültürel Miras',
        contentType: 'photo',
        latitude: 41.0161,
        longitude: 28.9642,
        unlockRadiusMeters: 5.0,
        arTriggerRadiusMeters: 15.0,
        locationName: 'Süleymaniye Külliyesi Avlusu',
        imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/2/2b/S%C3%BCleymaniye_Camii.jpg',
        noteText: '650 metrelik kültür rotasının zirvesindesiniz.',
        visualSignature: 'c9e1f3a7b5d28460',
        isEncrypted: false,
        createdBy: 'Akıllı Turizm Ekibi',
        createdAt: DateTime.now(),
        unlockCount: 41,
        geohash: 'sxk97b8',
      ),
    ];
  }
}
