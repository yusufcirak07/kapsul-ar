import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/capsule_models.dart';

class LocationSensorService extends ChangeNotifier {
  double _latitude = AppConfig.defaultLat;
  double _longitude = AppConfig.defaultLon;
  double _filteredLat = AppConfig.defaultLat;
  double _filteredLon = AppConfig.defaultLon;
  double _accuracyMeters = 5.0;
  double _altitudeMeters = 40.0;
  double _reportedSpeedMps = 0.0;
  double _headingDeg = 0.0;
  bool _isMocked = false;
  bool _isSimulated = true;
  bool _hasRealGpsFix = false;
  int _fixSequence = 0;
  String _statusLabel = 'Konum aranıyor...';

  // Raw + gravity-filtered linear IMU state
  double _ax = 0.08, _ay = -0.12, _az = 9.82;
  double _gx = 0.01, _gy = 0.02, _gz = 0.0;
  double _gravityMag = 9.81;
  double _dynamicLinearAccel = 0.0;

  int _stepsToday = 1420;
  double _distanceMetersToday = 980.0;
  final Set<String> _unlockedIds = {};

  final List<TelemetrySample> _telemetryWindow = [];
  Timer? _sampleTimer;
  Timer? _walkTimer;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  DateTime _lastHeadingNotify = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hasMagnetometer = false;
  final Random _rng = Random();

  double get latitude => _filteredLat;
  double get longitude => _filteredLon;
  double get rawLatitude => _latitude;
  double get rawLongitude => _longitude;
  LatLng get currentLatLng => LatLng(_filteredLat, _filteredLon);
  double get accuracyMeters => _accuracyMeters;
  double get headingDeg => _headingDeg;
  bool get hasMagnetometer => _hasMagnetometer;
  bool get isSimulated => _isSimulated;
  bool get hasRealGpsFix => _hasRealGpsFix;
  bool get isMocked => _isMocked;
  int get fixSequence => _fixSequence;
  String get statusLabel => _statusLabel;
  int get stepsToday => _stepsToday;
  double get distanceMetersToday => _distanceMetersToday;
  Set<String> get unlockedIds => Set.unmodifiable(_unlockedIds);
  List<TelemetrySample> get telemetryWindow => List.unmodifiable(_telemetryWindow);

  double get currentAccelMagnitude => sqrt(_ax * _ax + _ay * _ay + _az * _az);
  double get dynamicLinearAccel => _dynamicLinearAccel;
  double get currentGyroActivity => _gx.abs() + _gy.abs() + _gz.abs();

  String get compassCardinalLabel {
    const dirs = ['K', 'KD', 'D', 'GD', 'G', 'GB', 'B', 'KB'];
    final idx = (((_headingDeg % 360) + 360) % 360 / 45.0).round() % 8;
    return '${dirs[idx]} ${_headingDeg.round()}°';
  }

  Future<void> initialize() async {
    await _loadLocalStats();
    _seedInitialWindow();
    _startTelemetrySampler();
    _tryStartImuListeners();
    // Uygulama açılır açılmaz kullanıcının gerçek GPS konumunu almayı dene
    await enableRealGps();
  }

  Future<void> _loadLocalStats() async {
    final prefs = await SharedPreferences.getInstance();
    _stepsToday = prefs.getInt('steps_today') ?? 1420;
    _distanceMetersToday = prefs.getDouble('distance_today') ?? 980.0;
    final saved = prefs.getStringList('unlocked_ids') ?? [];
    _unlockedIds.addAll(saved);
    notifyListeners();
  }

  Future<void> markCapsuleUnlocked(String id) async {
    _unlockedIds.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('unlocked_ids', _unlockedIds.toList());
    notifyListeners();
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('steps_today', _stepsToday);
    await prefs.setDouble('distance_today', _distanceMetersToday);
  }

  void _seedInitialWindow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _telemetryWindow.clear();
    for (int i = 4; i >= 0; i--) {
      _telemetryWindow.add(TelemetrySample(
        latitude: _filteredLat,
        longitude: _filteredLon,
        accuracyMeters: _accuracyMeters + (_rng.nextDouble() - 0.5) * 0.4,
        altitudeMeters: _altitudeMeters,
        timestampMs: now - i * 1500,
        accelX: _ax,
        accelY: _ay,
        accelZ: _az,
        gyroAlpha: _gx,
        gyroBeta: _gy,
        gyroGamma: _gz,
      ));
    }
  }

  void _startTelemetrySampler() {
    _sampleTimer?.cancel();
    _sampleTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_isSimulated) {
        _ax = (_rng.nextDouble() - 0.5) * 0.35;
        _ay = (_rng.nextDouble() - 0.5) * 0.35;
        _az = 9.81 + (_rng.nextDouble() - 0.5) * 0.25;
        _gx = (_rng.nextDouble() - 0.5) * 0.08;
        _gy = (_rng.nextDouble() - 0.5) * 0.08;
      }

      _telemetryWindow.add(TelemetrySample(
        latitude: _latitude,
        longitude: _longitude,
        accuracyMeters: _accuracyMeters,
        altitudeMeters: _altitudeMeters,
        reportedSpeedMps: _reportedSpeedMps,
        headingDeg: _headingDeg,
        isMocked: _isMocked,
        timestampMs: now,
        accelX: _ax,
        accelY: _ay,
        accelZ: _az,
        gyroAlpha: _gx,
        gyroBeta: _gy,
        gyroGamma: _gz,
      ));

      _telemetryWindow.removeWhere((s) => now - s.timestampMs > 30000);
      notifyListeners();
    });
  }

  void _tryStartImuListeners() {
    try {
      _accSub = accelerometerEventStream().listen(
        (e) {
          _ax = e.x;
          _ay = e.y;
          _az = e.z;
          final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
          // High-pass filter isolating physical walking motion from gravity
          _gravityMag = 0.85 * _gravityMag + 0.15 * mag;
          _dynamicLinearAccel = (mag - _gravityMag).abs();
        },
        onError: (_) {},
      );
      _gyroSub = gyroscopeEventStream().listen(
        (e) {
          _gx = e.x;
          _gy = e.y;
          _gz = e.z;
        },
        onError: (_) {},
      );
      _magSub = magnetometerEventStream().listen(
        (m) => _updateTiltCompensatedHeading(m.x, m.y, m.z),
        onError: (_) {},
      );
    } catch (_) {}
  }

  /// Computes tilt-compensated compass azimuth (0=North, 90=East, 180=South, 270=West)
  /// from magnetometer + accelerometer gravity vector using E = M x G, N = G x E.
  void _updateTiltCompensatedHeading(double mx, double my, double mz) {
    final gNorm = sqrt(_ax * _ax + _ay * _ay + _az * _az);
    final mNorm = sqrt(mx * mx + my * my + mz * mz);
    if (gNorm < 1.0 || mNorm < 1.0) return;

    final gx = _ax / gNorm;
    final gy = _ay / gNorm;
    final gz = _az / gNorm;

    // East = M x G
    double ex = my * gz - mz * gy;
    double ey = mz * gx - mx * gz;
    double ez = mx * gy - my * gx;
    final eNorm = sqrt(ex * ex + ey * ey + ez * ez);
    if (eNorm < 1e-4) return;
    ex /= eNorm;
    ey /= eNorm;
    ez /= eNorm;

    // North = G x E (we only need Y component for flat/tilted, or Z component for upright)
    final ny = gz * ex - gx * ez;

    // Forward axis of phone: +Y when held mostly flat, -Z when held upright
    final double eastProj;
    final double northProj;
    if (gz.abs() > 0.35) {
      eastProj = ey;
      northProj = ny;
    } else {
      eastProj = -ez;
      final nz = gx * ey - gy * ex;
      northProj = -nz;
    }

    var deg = atan2(eastProj, northProj) * 180.0 / pi;
    if (deg < 0) deg += 360.0;

    // Circular exponential smoothing to prevent compass jitter
    final prevRad = _headingDeg * pi / 180.0;
    final newRad = deg * pi / 180.0;
    final sinAvg = 0.78 * sin(prevRad) + 0.22 * sin(newRad);
    final cosAvg = 0.78 * cos(prevRad) + 0.22 * cos(newRad);
    var smoothed = atan2(sinAvg, cosAvg) * 180.0 / pi;
    if (smoothed < 0) smoothed += 360.0;

    final diff = ((smoothed - _headingDeg + 540) % 360) - 180;
    _hasMagnetometer = true;
    _headingDeg = smoothed;

    if (diff.abs() >= 2.5 &&
        DateTime.now().difference(_lastHeadingNotify).inMilliseconds >= 120) {
      _lastHeadingNotify = DateTime.now();
      notifyListeners();
    }
  }

  Future<bool> enableRealGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _statusLabel = 'Konum servisi kapalı (Demo aktif)';
        _isSimulated = true;
        notifyListeners();
        return false;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _statusLabel = 'Konum izni yok (Demo aktif)';
        _isSimulated = true;
        notifyListeners();
        return false;
      }

      // First grab last known position immediately so map snaps fast, then refine with current position
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _applyRealPosition(lastKnown, snapDirectly: true);
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _applyRealPosition(pos, snapDirectly: true);

      await _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      ).listen((p) {
        _applyRealPosition(p, snapDirectly: false);
      });

      return true;
    } catch (_) {
      if (!_hasRealGpsFix) {
        _isSimulated = true;
        _statusLabel = 'Kampüs Demo Modu';
        notifyListeners();
      }
      return false;
    }
  }

  void _applyRealPosition(Position pos, {required bool snapDirectly}) {
    _walkTimer?.cancel();
    _isSimulated = false;
    _hasRealGpsFix = true;
    _isMocked = pos.isMocked;
    _altitudeMeters = pos.altitude;
    _reportedSpeedMps = pos.speed.isFinite && pos.speed >= 0 ? pos.speed : 0.0;
    if (!_hasMagnetometer && pos.heading.isFinite && pos.heading >= 0 && _reportedSpeedMps > 0.4) {
      _headingDeg = pos.heading;
    }
    _statusLabel = pos.isMocked ? 'Mock GPS Uyarısı' : 'Canlı GPS Aktif';

    _updateCoordinates(
      pos.latitude,
      pos.longitude,
      pos.accuracy,
      recordMovement: !snapDirectly,
      snapDirectly: snapDirectly,
    );
  }

  void switchToCampusSimulation() {
    _posSub?.cancel();
    _walkTimer?.cancel();
    _isSimulated = true;
    _isMocked = false;
    _latitude = AppConfig.defaultLat;
    _longitude = AppConfig.defaultLon;
    _filteredLat = AppConfig.defaultLat;
    _filteredLon = AppConfig.defaultLon;
    _accuracyMeters = 4.2;
    _statusLabel = 'Kampüs Simülasyon Modu';
    _fixSequence++;
    _seedInitialWindow();
    notifyListeners();
  }

  void startDemoWalkToward(double targetLat, double targetLon, {VoidCallback? onArrived}) {
    _posSub?.cancel();
    _walkTimer?.cancel();
    _isSimulated = true;
    _isMocked = false;
    _statusLabel = 'Yürüyüş Simülasyonu (1.5 m/s)';

    _walkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final dist = distanceMeters(_filteredLat, _filteredLon, targetLat, targetLon);
      if (dist <= 3.0) {
        _reportedSpeedMps = 0.0;
        _updateCoordinates(targetLat, targetLon, 3.4, recordMovement: true, snapDirectly: true);
        _statusLabel = 'Hedef Konuma Ulaşıldı';
        timer.cancel();
        onArrived?.call();
        notifyListeners();
        return;
      }

      const stepMeters = 1.8;
      final fraction = (stepMeters / dist).clamp(0.0, 1.0);
      final nextLat = _filteredLat + (targetLat - _filteredLat) * fraction;
      final nextLon = _filteredLon + (targetLon - _filteredLon) * fraction;

      // Demo yürüyüşü sırasında yön okunu hedefe çevir
      if (!_hasMagnetometer) {
        _headingDeg = bearingDegrees(_filteredLat, _filteredLon, targetLat, targetLon);
      }

      _reportedSpeedMps = 1.6;
      _ax = (_rng.nextDouble() - 0.5) * 2.4;
      _ay = (_rng.nextDouble() - 0.5) * 1.9;
      _az = 9.81 + sin(timer.tick * 0.9) * 1.8;
      _gx = (_rng.nextDouble() - 0.5) * 0.45;
      _gy = (_rng.nextDouble() - 0.5) * 0.45;

      _updateCoordinates(
        nextLat,
        nextLon,
        3.6 + _rng.nextDouble() * 1.2,
        recordMovement: true,
        snapDirectly: true,
      );
    });
    notifyListeners();
  }

  void stopDemoWalk() {
    _walkTimer?.cancel();
    if (_isSimulated) {
      _statusLabel = 'Kampüs Simülasyon Modu';
      notifyListeners();
    }
  }

  void injectSpoofJump(double targetLat, double targetLon) {
    _walkTimer?.cancel();
    _isSimulated = true;
    _isMocked = true;
    _reportedSpeedMps = 0.0;
    _statusLabel = 'Test: Sahte GPS Sıçraması';
    _ax = 0.0;
    _ay = 0.0;
    _az = 9.81;
    _gx = 0.0;
    _gy = 0.0;
    _gz = 0.0;
    _updateCoordinates(targetLat, targetLon, 0.0, recordMovement: false, snapDirectly: true);
  }

  void _updateCoordinates(
    double lat,
    double lon,
    double acc, {
    required bool recordMovement,
    required bool snapDirectly,
  }) {
    final moved = distanceMeters(_filteredLat, _filteredLon, lat, lon);
    _latitude = lat;
    _longitude = lon;
    _accuracyMeters = acc > 0 ? acc : 0.0;

    if (snapDirectly || moved > 45.0) {
      _filteredLat = lat;
      _filteredLon = lon;
      _fixSequence++;
    } else {
      // Adaptive drift filter: trust high-accuracy readings more, damp noisy jumps
      final alpha = (1.0 / (1.0 + (_accuracyMeters / 8.0))).clamp(0.25, 0.75);
      _filteredLat = _filteredLat + alpha * (lat - _filteredLat);
      _filteredLon = _filteredLon + alpha * (lon - _filteredLon);
    }

    if (recordMovement && moved > 0.3 && moved < 50.0) {
      _distanceMetersToday += moved;
      _stepsToday += (moved / 0.72).round();
      _saveStats();
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _telemetryWindow.add(TelemetrySample(
      latitude: _latitude,
      longitude: _longitude,
      accuracyMeters: _accuracyMeters,
      altitudeMeters: _altitudeMeters,
      reportedSpeedMps: _reportedSpeedMps,
      headingDeg: _headingDeg,
      isMocked: _isMocked,
      timestampMs: now,
      accelX: _ax,
      accelY: _ay,
      accelZ: _az,
      gyroAlpha: _gx,
      gyroBeta: _gy,
      gyroGamma: _gz,
    ));
    _telemetryWindow.removeWhere((s) => now - s.timestampMs > 30000);
    notifyListeners();
  }

  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * pi / 180.0;

  static double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = _toRad(lat1);
    final phi2 = _toRad(lat2);
    final dLon = _toRad(lon2 - lon1);
    final y = sin(dLon) * cos(phi2);
    final x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLon);
    var deg = atan2(y, x) * 180.0 / pi;
    if (deg < 0) deg += 360.0;
    return deg;
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _walkTimer?.cancel();
    _posSub?.cancel();
    _accSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    super.dispose();
  }
}
