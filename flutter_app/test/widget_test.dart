import 'package:flutter_test/flutter_test.dart';
import 'package:kapsul_ar/models/capsule_models.dart';
import 'package:kapsul_ar/services/api_client.dart';
import 'package:kapsul_ar/services/location_sensor_service.dart';

void main() {
  test('Haversine distance computes accurate meter distance', () {
    final dist = LocationSensorService.distanceMeters(
      41.0119,
      28.9639,
      41.0124,
      28.9639,
    );
    expect(dist, greaterThan(50));
    expect(dist, lessThan(62));
  });

  test('TimeCapsule parses JSON payload properly', () {
    final cap = TimeCapsule.fromJson({
      'id': 'c1',
      'title': 'Kampüs Anısı',
      'description': 'Test',
      'category': 'Kampüs Yaşamı',
      'contentType': 'pixelArt',
      'latitude': 41.012,
      'longitude': 28.963,
      'unlockRadiusMeters': 5.0,
      'arTriggerRadiusMeters': 15.0,
      'locationName': 'Bahçe',
      'visualSignature': 'abcd1234',
      'isEncrypted': false,
      'createdBy': 'Yusuf',
      'unlockCount': 3,
      'geohash': 'sxk97b2',
      'distanceMeters': 4.2,
      'inArRange': true,
      'inUnlockRange': true,
    });

    expect(cap.contentTypeLabel, 'Piksel Sanat');
    expect(cap.inUnlockRange, isTrue);
  });

  test('Bearing degrees returns expected cardinal directions', () {
    final north = LocationSensorService.bearingDegrees(41.0, 29.0, 41.01, 29.0);
    final east = LocationSensorService.bearingDegrees(41.0, 29.0, 41.0, 29.01);
    expect(north, closeTo(0.0, 0.5));
    expect(east, closeTo(90.0, 0.5));
  });

  test('WalkingRoute parses JSON and computes polyline distance', () {
    final route = WalkingRoute.fromJson({
      'id': 'rt-test',
      'title': 'Likya Ham Etabı',
      'description': 'Test rota',
      'cityDistrict': 'Muğla / Fethiye',
      'routeCategory': 'Ham Rota',
      'difficulty': 'Orta',
      'socialTag': 'Doğa & Kültür Keşfi',
      'isRawPreset': true,
      'createdBy': 'Test',
      'distanceKm': 2.5,
      'estimatedMinutes': 35,
      'estimatedSteps': 3400,
      'averageRating': 4.8,
      'ratingCount': 5,
      'completionCount': 12,
      'waypoints': [
        {'order': 1, 'name': 'Başlangıç', 'latitude': 36.5718, 'longitude': 29.1536},
        {'order': 2, 'name': 'Durak 2', 'latitude': 36.5542, 'longitude': 29.1465},
      ],
    });

    expect(route.isRawPreset, isTrue);
    expect(route.waypoints.length, 2);
    expect(route.averageRating, 4.8);
    final meters = ApiClient.computeRouteDistanceMeters(route.waypoints);
    expect(meters, greaterThan(1800));
  });
}
