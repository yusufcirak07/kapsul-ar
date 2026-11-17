import 'dart:convert';
import 'dart:math';

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
    double? observedHeadingDeg,
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
              if (observedHeadingDeg != null) 'observedHeadingDeg': observedHeadingDeg,
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

  Future<List<WalkingRoute>> fetchRoutes({
    required double lat,
    required double lon,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/routes').replace(queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        isBackendOnline = true;
        final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
        final routes = data
            .map((e) => WalkingRoute.fromJson(e as Map<String, dynamic>))
            .toList();
        await _cacheRoutes(routes);
        return routes;
      }
    } catch (_) {
      isBackendOnline = false;
    }
    return _loadCachedOrSeededRoutes(lat, lon);
  }

  Future<WalkingRoute?> createRoute({
    required String title,
    required String description,
    required String cityDistrict,
    required String difficulty,
    required String socialTag,
    required bool isRawPreset,
    required String createdBy,
    required List<RouteWaypoint> waypoints,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/routes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': title,
              'description': description,
              'cityDistrict': cityDistrict,
              'difficulty': difficulty,
              'socialTag': socialTag,
              'isRawPreset': isRawPreset,
              'createdBy': createdBy,
              'waypoints': waypoints.map((w) => w.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 201 || resp.statusCode == 200) {
        isBackendOnline = true;
        final created = WalkingRoute.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        final current = await _loadCachedOrSeededRoutes(
          waypoints.first.latitude,
          waypoints.first.longitude,
        );
        await _cacheRoutes([created, ...current.where((r) => r.id != created.id)]);
        return created;
      }
    } catch (_) {
      isBackendOnline = false;
    }

    // Offline fallback: save locally so zero-to-one route creation always works
    final totalMeters = computeRouteDistanceMeters(waypoints);
    final distKm = double.parse((totalMeters / 1000.0).toStringAsFixed(2));
    final localRoute = WalkingRoute(
      id: 'rt-local-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      description: description,
      cityDistrict: cityDistrict,
      routeCategory: isRawPreset ? 'Ham Rota' : 'Topluluk Rotası',
      difficulty: difficulty,
      socialTag: socialTag,
      isRawPreset: isRawPreset,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      distanceKm: distKm,
      estimatedMinutes: max(8, (distKm / 4.2 * 60).round()),
      estimatedSteps: max(150, (totalMeters / 0.72).round()),
      averageRating: 0,
      ratingCount: 0,
      completionCount: 0,
      waypoints: waypoints,
    );
    final current = await _loadCachedOrSeededRoutes(
      waypoints.first.latitude,
      waypoints.first.longitude,
    );
    await _cacheRoutes([localRoute, ...current]);
    return localRoute;
  }

  Future<WalkingRoute?> rateRoute({
    required String routeId,
    required String userName,
    required int stars,
    required String comment,
    required int moodBoostScore,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/routes/$routeId/rate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userName': userName,
              'stars': stars,
              'comment': comment,
              'moodBoostScore': moodBoostScore,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        isBackendOnline = true;
        final updated = WalkingRoute.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        await _replaceCachedRoute(updated);
        return updated;
      }
    } catch (_) {
      isBackendOnline = false;
    }

    // Offline rating fallback
    final current = await _loadCachedOrSeededRoutes(AppConfig.defaultLat, AppConfig.defaultLon);
    final idx = current.indexWhere((r) => r.id == routeId);
    if (idx < 0) return null;
    final target = current[idx];
    final newRatings = [
      RouteRating(
        id: 'rate-${DateTime.now().millisecondsSinceEpoch}',
        userName: userName,
        stars: stars.clamp(1, 5),
        comment: comment,
        moodBoostScore: moodBoostScore.clamp(1, 5),
        createdAt: DateTime.now(),
      ),
      ...target.ratings,
    ];
    final avg = newRatings.map((e) => e.stars).reduce((a, b) => a + b) / newRatings.length;
    final updated = WalkingRoute(
      id: target.id,
      title: target.title,
      description: target.description,
      cityDistrict: target.cityDistrict,
      routeCategory: target.routeCategory,
      difficulty: target.difficulty,
      socialTag: target.socialTag,
      isRawPreset: target.isRawPreset,
      createdBy: target.createdBy,
      createdAt: target.createdAt,
      distanceKm: target.distanceKm,
      estimatedMinutes: target.estimatedMinutes,
      estimatedSteps: target.estimatedSteps,
      averageRating: double.parse(avg.toStringAsFixed(1)),
      ratingCount: newRatings.length,
      completionCount: target.completionCount,
      distanceFromUserKm: target.distanceFromUserKm,
      waypoints: target.waypoints,
      ratings: newRatings,
    );
    current[idx] = updated;
    await _cacheRoutes(current);
    return updated;
  }

  Future<WalkingRoute?> completeRoute({
    required String routeId,
    int? moodBoostScore,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/routes/$routeId/complete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': 'pwa-user',
              if (moodBoostScore != null) 'moodBoostScore': moodBoostScore,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        isBackendOnline = true;
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        if (map['route'] != null) {
          final updated = WalkingRoute.fromJson(map['route'] as Map<String, dynamic>);
          await _replaceCachedRoute(updated);
          return updated;
        }
      }
    } catch (_) {
      isBackendOnline = false;
    }

    final current = await _loadCachedOrSeededRoutes(AppConfig.defaultLat, AppConfig.defaultLon);
    final idx = current.indexWhere((r) => r.id == routeId);
    if (idx < 0) return null;
    final t = current[idx];
    final updated = WalkingRoute(
      id: t.id,
      title: t.title,
      description: t.description,
      cityDistrict: t.cityDistrict,
      routeCategory: t.routeCategory,
      difficulty: t.difficulty,
      socialTag: t.socialTag,
      isRawPreset: t.isRawPreset,
      createdBy: t.createdBy,
      createdAt: t.createdAt,
      distanceKm: t.distanceKm,
      estimatedMinutes: t.estimatedMinutes,
      estimatedSteps: t.estimatedSteps,
      averageRating: t.averageRating,
      ratingCount: t.ratingCount,
      completionCount: t.completionCount + 1,
      distanceFromUserKm: t.distanceFromUserKm,
      waypoints: t.waypoints,
      ratings: t.ratings,
    );
    current[idx] = updated;
    await _cacheRoutes(current);
    return updated;
  }

  Future<WalkingRoute> suggestLocalRoute({
    required double lat,
    required double lon,
    List<NearbyMediaItem> nearbyPlaces = const [],
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/routes/suggest').replace(queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        isBackendOnline = true;
        final created = WalkingRoute.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        final current = await _loadCachedOrSeededRoutes(lat, lon);
        await _cacheRoutes([created, ...current.where((r) => r.id != created.id)]);
        return created;
      }
    } catch (_) {
      isBackendOnline = false;
    }

    // Offline smart local loop generator for any small town/district
    final waypoints = <RouteWaypoint>[
      RouteWaypoint(
        order: 1,
        name: 'Başlangıç Konumunuz',
        latitude: lat,
        longitude: lon,
        hint: 'Yürüyüş başlangıç noktası',
      ),
    ];

    final validPlaces = nearbyPlaces
        .where((p) => p.latitude != null && p.longitude != null)
        .where((p) {
          final d = LocationSensorService.distanceMeters(lat, lon, p.latitude!, p.longitude!);
          return d >= 40 && d <= 2500;
        })
        .take(3)
        .toList();

    if (validPlaces.length >= 2) {
      for (int i = 0; i < validPlaces.length; i++) {
        waypoints.add(RouteWaypoint(
          order: i + 2,
          name: validPlaces[i].title,
          latitude: validPlaces[i].latitude!,
          longitude: validPlaces[i].longitude!,
          hint: validPlaces[i].description,
        ));
      }
    } else {
      final cosLat = max(cos(lat * pi / 180.0), 0.1);
      double dLat(double m) => m / 111320.0;
      double dLon(double m) => m / (111320.0 * cosLat);
      waypoints.addAll([
        RouteWaypoint(
          order: 2,
          name: 'Mahalle / Kampüs Park Durağı',
          latitude: lat + dLat(260),
          longitude: lon + dLon(190),
          hint: 'Temiz hava ve esneme molası',
        ),
        RouteWaypoint(
          order: 3,
          name: 'Sosyal Buluşma & Seyir Noktası',
          latitude: lat + dLat(120),
          longitude: lon + dLon(420),
          hint: 'Zaman kapsülü bırakma noktası',
        ),
        RouteWaypoint(
          order: 4,
          name: 'Dönüş & Bitiş Çemberi',
          latitude: lat - dLat(90),
          longitude: lon + dLon(180),
          hint: 'Yaklaşık 1.3 km sosyal yürüyüş bitişi',
        ),
      ]);
    }

    final totalMeters = computeRouteDistanceMeters(waypoints);
    final distKm = double.parse((totalMeters / 1000.0).toStringAsFixed(2));
    final generated = WalkingRoute(
      id: 'rt-auto-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Konumuma Özel Sosyal Keşif Rotası',
      description:
          'Çevrenizdeki açık alan ve mekanlardan otomatik üretilen başlangıç rotası.',
      cityDistrict: 'Yakın Çevrem',
      routeCategory: 'Otomatik Çevre Rotası',
      difficulty: 'Kolay',
      socialTag: 'Hareketsizliği Kıran Keşif',
      isRawPreset: false,
      createdBy: 'Otomatik Rota Motoru',
      createdAt: DateTime.now(),
      distanceKm: distKm,
      estimatedMinutes: max(8, (distKm / 4.2 * 60).round()),
      estimatedSteps: max(200, (totalMeters / 0.72).round()),
      averageRating: 0,
      ratingCount: 0,
      completionCount: 0,
      waypoints: waypoints,
    );
    final current = await _loadCachedOrSeededRoutes(lat, lon);
    await _cacheRoutes([generated, ...current]);
    return generated;
  }

  Future<void> submitWellBeing({
    required int moodScore,
    required int socialConnectedness,
    String? routeId,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/api/experiments/wellbeing'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': 'pwa-user',
              'moodScore': moodScore,
              'socialConnectedness': socialConnectedness,
              if (routeId != null) 'routeId': routeId,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  static double computeRouteDistanceMeters(List<RouteWaypoint> waypoints) {
    double total = 0;
    for (int i = 1; i < waypoints.length; i++) {
      total += LocationSensorService.distanceMeters(
        waypoints[i - 1].latitude,
        waypoints[i - 1].longitude,
        waypoints[i].latitude,
        waypoints[i].longitude,
      );
    }
    return total;
  }

  Future<void> _cacheRoutes(List<WalkingRoute> routes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cached_routes_v1',
      jsonEncode(routes.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> _replaceCachedRoute(WalkingRoute updated) async {
    final current = await _loadCachedOrSeededRoutes(AppConfig.defaultLat, AppConfig.defaultLon);
    final idx = current.indexWhere((r) => r.id == updated.id);
    if (idx >= 0) {
      current[idx] = updated;
    } else {
      current.insert(0, updated);
    }
    await _cacheRoutes(current);
  }

  Future<List<WalkingRoute>> _loadCachedOrSeededRoutes(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_routes_v1');
    List<WalkingRoute> routes;
    if (raw != null) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      routes = decoded
          .map((e) => WalkingRoute.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      routes = _fallbackSeededRoutes();
    }
    return routes.map((r) {
      final distKm = r.waypoints.isNotEmpty
          ? double.parse((LocationSensorService.distanceMeters(
                    lat,
                    lon,
                    r.waypoints.first.latitude,
                    r.waypoints.first.longitude,
                  ) /
                  1000.0)
              .toStringAsFixed(2))
          : 0.0;
      return WalkingRoute(
        id: r.id,
        title: r.title,
        description: r.description,
        cityDistrict: r.cityDistrict,
        routeCategory: r.routeCategory,
        difficulty: r.difficulty,
        socialTag: r.socialTag,
        isRawPreset: r.isRawPreset,
        createdBy: r.createdBy,
        createdAt: r.createdAt,
        distanceKm: r.distanceKm,
        estimatedMinutes: r.estimatedMinutes,
        estimatedSteps: r.estimatedSteps,
        averageRating: r.averageRating,
        ratingCount: r.ratingCount,
        completionCount: r.completionCount,
        distanceFromUserKm: distKm,
        waypoints: r.waypoints,
        ratings: r.ratings,
      );
    }).toList();
  }

  static List<WalkingRoute> _fallbackSeededRoutes() {
    return [
      WalkingRoute(
        id: 'rt-likya',
        title: 'Likya Yolu: Ovacık – Faralya – Kabak Ham Rotası',
        description:
            'Likya Yolu başlangıç etabının ham GPS duraklı rotası. Doğa yürüyüşü ve grup sosyalleşmesi için referans parkur.',
        cityDistrict: 'Muğla / Fethiye',
        routeCategory: 'Ham Rota',
        difficulty: 'Orta',
        socialTag: 'Doğa & Kültür Keşfi',
        isRawPreset: true,
        createdBy: 'Likya Ham Rota Arşivi',
        createdAt: DateTime.now(),
        distanceKm: 12.6,
        estimatedMinutes: 180,
        estimatedSteps: 17500,
        averageRating: 5.0,
        ratingCount: 2,
        completionCount: 34,
        waypoints: const [
          RouteWaypoint(order: 1, name: 'Ovacık Likya Başlangıç Kapısı', latitude: 36.5718, longitude: 29.1536),
          RouteWaypoint(order: 2, name: 'Kozağaç Çeşmesi', latitude: 36.5542, longitude: 29.1465),
          RouteWaypoint(order: 3, name: 'Kirme Köyü Sırtı', latitude: 36.5356, longitude: 29.1394),
          RouteWaypoint(order: 4, name: 'Faralya – Kelebekler Vadisi Üstü', latitude: 36.4945, longitude: 29.1328),
          RouteWaypoint(order: 5, name: 'Kabak Koyu İniş Patikası', latitude: 36.4648, longitude: 29.1241),
        ],
        ratings: [
          RouteRating(
            id: 'r1',
            userName: 'Zeynep K.',
            stars: 5,
            moodBoostScore: 5,
            comment: 'Ham duraklar net olduğu için yalnız gelenlerle Faralya\'da yürüyüş grubu kurduk.',
            createdAt: DateTime.now(),
          ),
        ],
      ),
      WalkingRoute(
        id: 'rt-oltu',
        title: 'Küçük İlçe Keşif: Oltu Kalesi – Çoruh Kenarı Öğrenci Hattı',
        description:
            'Küçük ilçede okuyan üniversite öğrencilerinin kampüs dışına çıkıp sosyalleşebileceği akşamüstü rotası.',
        cityDistrict: 'Erzurum / Oltu',
        routeCategory: 'Ham Rota',
        difficulty: 'Kolay',
        socialTag: 'Üni Öğrenci Buluşması',
        isRawPreset: true,
        createdBy: 'İlçe Gençlik Yürüyüşü',
        createdAt: DateTime.now(),
        distanceKm: 1.45,
        estimatedMinutes: 21,
        estimatedSteps: 2010,
        averageRating: 4.5,
        ratingCount: 1,
        completionCount: 19,
        waypoints: const [
          RouteWaypoint(order: 1, name: 'Oltu Kampüs / MYO Çıkışı', latitude: 40.5468, longitude: 41.9942),
          RouteWaypoint(order: 2, name: 'Oltu Kalesi Çevresi', latitude: 40.5495, longitude: 41.9963),
          RouteWaypoint(order: 3, name: 'Kültür Parkı & Kütüphane Önü', latitude: 40.5512, longitude: 41.9990),
          RouteWaypoint(order: 4, name: 'Oltu Çayı Yürüyüş Bandı', latitude: 40.5477, longitude: 42.0028),
        ],
      ),
      WalkingRoute(
        id: 'rt-beyazit',
        title: 'Beyazıt – Süleymaniye Sosyal & Kültür Yürüyüşü',
        description:
            'Kampüste hareketsiz kalan öğrenciler için tarihi durakları ve kitapçıları bağlayan sosyalleşme rotası.',
        cityDistrict: 'İstanbul / Fatih',
        routeCategory: 'Topluluk Rotası',
        difficulty: 'Kolay',
        socialTag: 'Üni Öğrenci Buluşması',
        isRawPreset: false,
        createdBy: 'SOY Tech Keşif Ekibi',
        createdAt: DateTime.now(),
        distanceKm: 0.72,
        estimatedMinutes: 12,
        estimatedSteps: 1000,
        averageRating: 4.5,
        ratingCount: 2,
        completionCount: 46,
        waypoints: const [
          RouteWaypoint(order: 1, name: 'İ.Ü. Tarihi Ana Kapı', latitude: 41.0119, longitude: 28.9639),
          RouteWaypoint(order: 2, name: 'Merkez Kampüs Bahçesi', latitude: 41.0124, longitude: 28.9634),
          RouteWaypoint(order: 3, name: 'Sahaflar & Kitabevi Sokağı', latitude: 41.0132, longitude: 28.9651),
          RouteWaypoint(order: 4, name: 'Süleymaniye Külliyesi Avlusu', latitude: 41.0161, longitude: 28.9642),
        ],
      ),
    ];
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
