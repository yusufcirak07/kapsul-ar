class TimeCapsule {
  final String id;
  final String title;
  final String description;
  final String category;
  final String contentType; // note | photo | pixelArt | audio
  final double latitude;
  final double longitude;
  final double unlockRadiusMeters;
  final double arTriggerRadiusMeters;
  final String locationName;
  final String? imageUrl;
  final String? noteText;
  final List<int>? pixelArtGrid;
  final int? audioDurationSec;
  final List<double>? audioWaveform;
  final String visualSignature;
  final double anchorHeadingDeg;
  final String spatialSealHash;
  final bool isEncrypted;
  final String? passcodeHint;
  final String createdBy;
  final DateTime createdAt;
  final int unlockCount;
  final String geohash;
  final double distanceMeters;
  final bool inArRange;
  final bool inUnlockRange;

  const TimeCapsule({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.contentType,
    required this.latitude,
    required this.longitude,
    required this.unlockRadiusMeters,
    required this.arTriggerRadiusMeters,
    required this.locationName,
    this.imageUrl,
    this.noteText,
    this.pixelArtGrid,
    this.audioDurationSec,
    this.audioWaveform,
    required this.visualSignature,
    this.anchorHeadingDeg = 0,
    this.spatialSealHash = '',
    required this.isEncrypted,
    this.passcodeHint,
    required this.createdBy,
    required this.createdAt,
    required this.unlockCount,
    required this.geohash,
    this.distanceMeters = 0,
    this.inArRange = false,
    this.inUnlockRange = false,
  });

  factory TimeCapsule.fromJson(Map<String, dynamic> json) {
    return TimeCapsule(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? 'Kültürel Miras').toString(),
      contentType: (json['contentType'] ?? 'note').toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 41.0121,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 28.9637,
      unlockRadiusMeters: (json['unlockRadiusMeters'] as num?)?.toDouble() ?? 5.0,
      arTriggerRadiusMeters: (json['arTriggerRadiusMeters'] as num?)?.toDouble() ?? 15.0,
      locationName: (json['locationName'] ?? '').toString(),
      imageUrl: json['imageUrl'] as String?,
      noteText: json['noteText'] as String?,
      pixelArtGrid: (json['pixelArtGrid'] as List?)?.map((e) => (e as num).toInt()).toList(),
      audioDurationSec: (json['audioDurationSec'] as num?)?.toInt(),
      audioWaveform: (json['audioWaveform'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      visualSignature: (json['visualSignature'] ?? 'a4c8e2f09b7531d6').toString(),
      anchorHeadingDeg: (json['anchorHeadingDeg'] as num?)?.toDouble() ?? 0,
      spatialSealHash: (json['spatialSealHash'] ?? '').toString(),
      isEncrypted: (json['isEncrypted'] as bool?) ?? false,
      passcodeHint: json['passcodeHint'] as String?,
      createdBy: (json['createdBy'] ?? 'Gezgin').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
      unlockCount: (json['unlockCount'] as num?)?.toInt() ?? 0,
      geohash: (json['geohash'] ?? '').toString(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      inArRange: (json['inArRange'] as bool?) ?? false,
      inUnlockRange: (json['inUnlockRange'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category,
        'contentType': contentType,
        'latitude': latitude,
        'longitude': longitude,
        'unlockRadiusMeters': unlockRadiusMeters,
        'arTriggerRadiusMeters': arTriggerRadiusMeters,
        'locationName': locationName,
        'imageUrl': imageUrl,
        'noteText': noteText,
        'pixelArtGrid': pixelArtGrid,
        'audioDurationSec': audioDurationSec,
        'audioWaveform': audioWaveform,
        'visualSignature': visualSignature,
        'isEncrypted': isEncrypted,
        'passcodeHint': passcodeHint,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'unlockCount': unlockCount,
        'geohash': geohash,
        'distanceMeters': distanceMeters,
        'inArRange': inArRange,
        'inUnlockRange': inUnlockRange,
      };

  String get contentTypeLabel {
    switch (contentType) {
      case 'audio':
        return 'Sesli Anı';
      case 'pixelArt':
        return 'Piksel Sanat';
      case 'photo':
        return 'Fotoğraf';
      default:
        return isEncrypted ? 'Şifreli Not' : 'Not';
    }
  }
}

class TelemetrySample {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double altitudeMeters;
  final double reportedSpeedMps;
  final double headingDeg;
  final bool isMocked;
  final int timestampMs;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double gyroAlpha;
  final double gyroBeta;
  final double gyroGamma;

  const TelemetrySample({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.altitudeMeters = 0.0,
    this.reportedSpeedMps = 0.0,
    this.headingDeg = 0.0,
    this.isMocked = false,
    required this.timestampMs,
    this.accelX = 0.0,
    this.accelY = 0.0,
    this.accelZ = 9.81,
    this.gyroAlpha = 0.0,
    this.gyroBeta = 0.0,
    this.gyroGamma = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'altitudeMeters': altitudeMeters,
        'reportedSpeedMps': reportedSpeedMps,
        'headingDeg': headingDeg,
        'isMocked': isMocked,
        'timestampMs': timestampMs,
        'accelX': accelX,
        'accelY': accelY,
        'accelZ': accelZ,
        'gyroAlpha': gyroAlpha,
        'gyroBeta': gyroBeta,
        'gyroGamma': gyroGamma,
      };
}

class VerificationLayerResult {
  final String name;
  final bool passed;
  final double score;
  final String detail;

  const VerificationLayerResult({
    required this.name,
    required this.passed,
    required this.score,
    required this.detail,
  });

  factory VerificationLayerResult.fromJson(Map<String, dynamic> json) {
    return VerificationLayerResult(
      name: (json['name'] ?? '').toString(),
      passed: (json['passed'] as bool?) ?? false,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      detail: (json['detail'] ?? '').toString(),
    );
  }
}

class AntiSpoofingReport {
  final bool passed;
  final double trustScore;
  final double maxObservedSpeedMps;
  final double maxObservedAccelerationMps2;
  final bool impossibleJumpDetected;
  final bool sensorFusionConsistent;
  final bool mockProviderDetected;
  final double signalJitterStdDev;
  final double kalmanInnovationMeters;
  final int sampleCount;
  final String reason;
  final List<VerificationLayerResult> layers;

  const AntiSpoofingReport({
    required this.passed,
    required this.trustScore,
    required this.maxObservedSpeedMps,
    required this.maxObservedAccelerationMps2,
    required this.impossibleJumpDetected,
    required this.sensorFusionConsistent,
    this.mockProviderDetected = false,
    this.signalJitterStdDev = 0,
    this.kalmanInnovationMeters = 0,
    required this.sampleCount,
    required this.reason,
    this.layers = const [],
  });

  factory AntiSpoofingReport.fromJson(Map<String, dynamic> json) {
    return AntiSpoofingReport(
      passed: (json['passed'] as bool?) ?? false,
      trustScore: (json['trustScore'] as num?)?.toDouble() ?? 0,
      maxObservedSpeedMps: (json['maxObservedSpeedMps'] as num?)?.toDouble() ?? 0,
      maxObservedAccelerationMps2: (json['maxObservedAccelerationMps2'] as num?)?.toDouble() ?? 0,
      impossibleJumpDetected: (json['impossibleJumpDetected'] as bool?) ?? false,
      sensorFusionConsistent: (json['sensorFusionConsistent'] as bool?) ?? true,
      mockProviderDetected: (json['mockProviderDetected'] as bool?) ?? false,
      signalJitterStdDev: (json['signalJitterStdDev'] as num?)?.toDouble() ?? 0,
      kalmanInnovationMeters: (json['kalmanInnovationMeters'] as num?)?.toDouble() ?? 0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      reason: (json['reason'] ?? '').toString(),
      layers: ((json['layers'] as List?) ?? [])
          .map((e) => VerificationLayerResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class UnlockAttemptResult {
  final bool unlocked;
  final bool arReady;
  final double distanceMeters;
  final double visualMatchScore;
  final double headingAlignmentScore;
  final bool spatialSealVerified;
  final AntiSpoofingReport antiSpoofing;
  final String message;
  final TimeCapsule? capsule;

  const UnlockAttemptResult({
    required this.unlocked,
    required this.arReady,
    required this.distanceMeters,
    required this.visualMatchScore,
    this.headingAlignmentScore = 0,
    this.spatialSealVerified = false,
    required this.antiSpoofing,
    required this.message,
    this.capsule,
  });

  factory UnlockAttemptResult.fromJson(Map<String, dynamic> json) {
    return UnlockAttemptResult(
      unlocked: (json['unlocked'] as bool?) ?? false,
      arReady: (json['arReady'] as bool?) ?? false,
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      visualMatchScore: (json['visualMatchScore'] as num?)?.toDouble() ?? 0,
      headingAlignmentScore: (json['headingAlignmentScore'] as num?)?.toDouble() ?? 0,
      spatialSealVerified: (json['spatialSealVerified'] as bool?) ?? false,
      antiSpoofing: AntiSpoofingReport.fromJson(
        (json['antiSpoofing'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
      message: (json['message'] ?? '').toString(),
      capsule: json['capsule'] != null
          ? TimeCapsule.fromJson(json['capsule'] as Map<String, dynamic>)
          : null,
    );
  }
}

class SpatialStrategyMetric {
  final String strategy;
  final String description;
  final double avgQueryMs;
  final double p95QueryMs;
  final int avgCandidatesScanned;
  final int matchesFound;
  final double estimatedMemoryKb;

  const SpatialStrategyMetric({
    required this.strategy,
    required this.description,
    required this.avgQueryMs,
    required this.p95QueryMs,
    required this.avgCandidatesScanned,
    required this.matchesFound,
    required this.estimatedMemoryKb,
  });

  factory SpatialStrategyMetric.fromJson(Map<String, dynamic> json) {
    return SpatialStrategyMetric(
      strategy: (json['strategy'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      avgQueryMs: (json['avgQueryMs'] as num?)?.toDouble() ?? 0,
      p95QueryMs: (json['p95QueryMs'] as num?)?.toDouble() ?? 0,
      avgCandidatesScanned: (json['avgCandidatesScanned'] as num?)?.toInt() ?? 0,
      matchesFound: (json['matchesFound'] as num?)?.toInt() ?? 0,
      estimatedMemoryKb: (json['estimatedMemoryKb'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SpatialBenchmarkData {
  final int syntheticPointCount;
  final int queryIterations;
  final double queryRadiusMeters;
  final List<SpatialStrategyMetric> results;

  const SpatialBenchmarkData({
    required this.syntheticPointCount,
    required this.queryIterations,
    required this.queryRadiusMeters,
    required this.results,
  });

  factory SpatialBenchmarkData.fromJson(Map<String, dynamic> json) {
    return SpatialBenchmarkData(
      syntheticPointCount: (json['syntheticPointCount'] as num?)?.toInt() ?? 0,
      queryIterations: (json['queryIterations'] as num?)?.toInt() ?? 0,
      queryRadiusMeters: (json['queryRadiusMeters'] as num?)?.toDouble() ?? 5,
      results: ((json['results'] as List?) ?? [])
          .map((e) => SpatialStrategyMetric.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ExperimentSummary {
  final int totalCapsules;
  final int totalUnlocks;
  final int blockedSpoofAttempts;
  final double spoofBlockRatePercent;
  final int totalStepsLogged;
  final double totalDistanceKm;
  final int susResponsesCount;
  final double averageSusScore;
  final double averageTamUsefulness;
  final double averageTamEaseOfUse;
  final int totalRoutes;
  final int totalRouteCompletions;
  final int totalRouteRatings;
  final double averageWellBeingScore;

  const ExperimentSummary({
    required this.totalCapsules,
    required this.totalUnlocks,
    required this.blockedSpoofAttempts,
    required this.spoofBlockRatePercent,
    required this.totalStepsLogged,
    required this.totalDistanceKm,
    required this.susResponsesCount,
    required this.averageSusScore,
    required this.averageTamUsefulness,
    required this.averageTamEaseOfUse,
    this.totalRoutes = 4,
    this.totalRouteCompletions = 120,
    this.totalRouteRatings = 6,
    this.averageWellBeingScore = 4.4,
  });

  factory ExperimentSummary.fromJson(Map<String, dynamic> json) {
    return ExperimentSummary(
      totalCapsules: (json['totalCapsules'] as num?)?.toInt() ?? 0,
      totalUnlocks: (json['totalUnlocks'] as num?)?.toInt() ?? 0,
      blockedSpoofAttempts: (json['blockedSpoofAttempts'] as num?)?.toInt() ?? 0,
      spoofBlockRatePercent: (json['spoofBlockRatePercent'] as num?)?.toDouble() ?? 100,
      totalStepsLogged: (json['totalStepsLogged'] as num?)?.toInt() ?? 0,
      totalDistanceKm: (json['totalDistanceKm'] as num?)?.toDouble() ?? 0,
      susResponsesCount: (json['susResponsesCount'] as num?)?.toInt() ?? 0,
      averageSusScore: (json['averageSusScore'] as num?)?.toDouble() ?? 82.5,
      averageTamUsefulness: (json['averageTamUsefulness'] as num?)?.toDouble() ?? 4.35,
      averageTamEaseOfUse: (json['averageTamEaseOfUse'] as num?)?.toDouble() ?? 4.48,
      totalRoutes: (json['totalRoutes'] as num?)?.toInt() ?? 4,
      totalRouteCompletions: (json['totalRouteCompletions'] as num?)?.toInt() ?? 0,
      totalRouteRatings: (json['totalRouteRatings'] as num?)?.toInt() ?? 0,
      averageWellBeingScore: (json['averageWellBeingScore'] as num?)?.toDouble() ?? 4.4,
    );
  }
}

class RouteWaypoint {
  final int order;
  final String name;
  final double latitude;
  final double longitude;
  final String hint;

  const RouteWaypoint({
    required this.order,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.hint = '',
  });

  factory RouteWaypoint.fromJson(Map<String, dynamic> json) {
    return RouteWaypoint(
      order: (json['order'] as num?)?.toInt() ?? 1,
      name: (json['name'] ?? '').toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 41.0121,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 28.9637,
      hint: (json['hint'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'order': order,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'hint': hint,
      };
}

class RouteRating {
  final String id;
  final String userName;
  final int stars;
  final String comment;
  final int moodBoostScore;
  final DateTime createdAt;

  const RouteRating({
    required this.id,
    required this.userName,
    required this.stars,
    required this.comment,
    this.moodBoostScore = 5,
    required this.createdAt,
  });

  factory RouteRating.fromJson(Map<String, dynamic> json) {
    return RouteRating(
      id: (json['id'] ?? '').toString(),
      userName: (json['userName'] ?? 'Gezgin').toString(),
      stars: (json['stars'] as num?)?.toInt() ?? 5,
      comment: (json['comment'] ?? '').toString(),
      moodBoostScore: (json['moodBoostScore'] as num?)?.toInt() ?? 5,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userName': userName,
        'stars': stars,
        'comment': comment,
        'moodBoostScore': moodBoostScore,
        'createdAt': createdAt.toIso8601String(),
      };
}

class WalkingRoute {
  final String id;
  final String title;
  final String description;
  final String cityDistrict;
  final String routeCategory; // Ham Rota | Topluluk Rotası | Otomatik Çevre Rotası
  final String difficulty; // Kolay | Orta | Zor
  final String socialTag;
  final bool isRawPreset;
  final String createdBy;
  final DateTime createdAt;
  final double distanceKm;
  final int estimatedMinutes;
  final int estimatedSteps;
  final double averageRating;
  final int ratingCount;
  final int completionCount;
  final double distanceFromUserKm;
  final List<RouteWaypoint> waypoints;
  final List<RouteRating> ratings;

  const WalkingRoute({
    required this.id,
    required this.title,
    required this.description,
    required this.cityDistrict,
    required this.routeCategory,
    required this.difficulty,
    required this.socialTag,
    required this.isRawPreset,
    required this.createdBy,
    required this.createdAt,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.estimatedSteps,
    required this.averageRating,
    required this.ratingCount,
    required this.completionCount,
    this.distanceFromUserKm = 0,
    required this.waypoints,
    this.ratings = const [],
  });

  factory WalkingRoute.fromJson(Map<String, dynamic> json) {
    return WalkingRoute(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      cityDistrict: (json['cityDistrict'] ?? 'Yerel İlçe').toString(),
      routeCategory: (json['routeCategory'] ?? 'Topluluk Rotası').toString(),
      difficulty: (json['difficulty'] ?? 'Kolay').toString(),
      socialTag: (json['socialTag'] ?? 'Üni Öğrenci Buluşması').toString(),
      isRawPreset: (json['isRawPreset'] as bool?) ?? false,
      createdBy: (json['createdBy'] ?? 'Gezgin').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 15,
      estimatedSteps: (json['estimatedSteps'] as num?)?.toInt() ?? 1500,
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      completionCount: (json['completionCount'] as num?)?.toInt() ?? 0,
      distanceFromUserKm: (json['distanceFromUserKm'] as num?)?.toDouble() ?? 0,
      waypoints: ((json['waypoints'] as List?) ?? [])
          .map((e) => RouteWaypoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      ratings: ((json['ratings'] as List?) ?? [])
          .map((e) => RouteRating.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'cityDistrict': cityDistrict,
        'routeCategory': routeCategory,
        'difficulty': difficulty,
        'socialTag': socialTag,
        'isRawPreset': isRawPreset,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'distanceKm': distanceKm,
        'estimatedMinutes': estimatedMinutes,
        'estimatedSteps': estimatedSteps,
        'averageRating': averageRating,
        'ratingCount': ratingCount,
        'completionCount': completionCount,
        'distanceFromUserKm': distanceFromUserKm,
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'ratings': ratings.map((r) => r.toJson()).toList(),
      };
}

class NearbyMediaItem {
  final String title;
  final String imageUrl;
  final String source;
  final String description;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;

  const NearbyMediaItem({
    required this.title,
    required this.imageUrl,
    required this.source,
    required this.description,
    this.latitude,
    this.longitude,
    this.distanceMeters,
  });

  factory NearbyMediaItem.fromJson(Map<String, dynamic> json) {
    return NearbyMediaItem(
      title: (json['title'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      source: (json['source'] ?? 'Wikimedia Commons').toString(),
      description: (json['description'] ?? '').toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
    );
  }
}
