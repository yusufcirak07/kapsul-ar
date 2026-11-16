import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../models/capsule_models.dart';
import '../services/api_client.dart';
import '../services/location_sensor_service.dart';
import '../widgets/capsule_card.dart';
import '../widgets/story_strip.dart';
import 'ar_unlock_screen.dart';

class ExploreScreen extends StatefulWidget {
  final ApiClient api;
  final LocationSensorService locationService;
  final VoidCallback onGoToCreate;
  final ValueChanged<NearbyMediaItem>? onCreateAtPlace;

  const ExploreScreen({
    super.key,
    required this.api,
    required this.locationService,
    required this.onGoToCreate,
    this.onCreateAtPlace,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final MapController _mapController = MapController();
  List<TimeCapsule> _capsules = [];
  List<NearbyMediaItem> _popularPlaces = [];
  String _selectedCategory = 'Tümü';
  bool _loading = true;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastFixSeq = -1;
  double _lastQueryLat = 0;
  double _lastQueryLon = 0;

  @override
  void initState() {
    super.initState();
    _lastFixSeq = widget.locationService.fixSequence;
    _lastQueryLat = widget.locationService.latitude;
    _lastQueryLon = widget.locationService.longitude;
    widget.locationService.addListener(_onLocationChanged);
    _loadData();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    final loc = widget.locationService;
    final movedFromLastQuery = LocationSensorService.distanceMeters(
      _lastQueryLat,
      _lastQueryLon,
      loc.latitude,
      loc.longitude,
    );

    if (loc.fixSequence != _lastFixSeq) {
      _lastFixSeq = loc.fixSequence;
      try {
        _mapController.move(loc.currentLatLng, 16.0);
      } catch (_) {}
      _loadData(silent: true);
    } else if (movedFromLastQuery > 60 &&
        DateTime.now().difference(_lastFetch).inSeconds >= 4) {
      _loadData(silent: true);
    }

    setState(() {
      _capsules = _capsules.map((c) {
        final d = LocationSensorService.distanceMeters(
          loc.latitude,
          loc.longitude,
          c.latitude,
          c.longitude,
        );
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
      }).toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    });
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    _lastFetch = DateTime.now();
    _lastQueryLat = widget.locationService.latitude;
    _lastQueryLon = widget.locationService.longitude;

    final results = await Future.wait([
      widget.api.fetchNearbyCapsules(
        lat: widget.locationService.latitude,
        lon: widget.locationService.longitude,
        category: _selectedCategory,
      ),
      widget.api.fetchNearbyPopularPlaces(
        lat: widget.locationService.latitude,
        lon: widget.locationService.longitude,
      ),
    ]);

    if (!mounted) return;
    setState(() {
      _capsules = results[0] as List<TimeCapsule>;
      _popularPlaces = results[1] as List<NearbyMediaItem>;
      _loading = false;
    });
  }

  void _openArScreen(TimeCapsule capsule) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArUnlockScreen(
          capsule: capsule,
          api: widget.api,
          locationService: widget.locationService,
        ),
      ),
    );
    _loadData(silent: true);
  }

  void _startWalkTo(double lat, double lon, String title) {
    _mapController.move(LatLng(lat, lon), 17.2);
    widget.locationService.startDemoWalkToward(
      lat,
      lon,
      onArrived: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title noktasına ulaşıldı!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _showCapsuleStoryPreview(TimeCapsule cap) {
    final p = AppPalette.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (cap.imageUrl != null && cap.imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  cap.imageUrl!,
                  height: 165,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              cap.title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '${cap.locationName} • ${cap.distanceMeters.toStringAsFixed(0)} m',
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  if (cap.inArRange) {
                    _openArScreen(cap);
                  } else {
                    _startWalkTo(cap.latitude, cap.longitude, cap.title);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: cap.inArRange ? p.accentSecondary : p.accentPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: Icon(cap.inArRange ? Icons.view_in_ar_rounded : Icons.directions_walk_rounded),
                label: Text(cap.inArRange ? 'WebAR ile Aç' : 'Hedefe Yaklaş'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPopularPlaceSheet(NearbyMediaItem poi) {
    final p = AppPalette.of(context);
    final dist = poi.latitude != null && poi.longitude != null
        ? LocationSensorService.distanceMeters(
            widget.locationService.latitude,
            widget.locationService.longitude,
            poi.latitude!,
            poi.longitude!,
          )
        : (poi.distanceMeters ?? 0);

    showModalBottomSheet(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.star_rounded, color: p.accentAmber, size: 20),
                const SizedBox(width: 6),
                Text(
                  'Çevredeki Popüler Yer',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.accentAmber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (poi.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  poi.imageUrl,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              poi.title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Konumunuza ${dist.toStringAsFixed(0)} m • ${poi.source}',
              style: TextStyle(fontSize: 12.5, color: p.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (poi.latitude != null && poi.longitude != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _startWalkTo(poi.latitude!, poi.longitude!, poi.title);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.accentPrimary,
                        side: BorderSide(color: p.accentPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.directions_walk_rounded, size: 18),
                      label: const Text('Buraya Yürü'),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      if (widget.onCreateAtPlace != null) {
                        widget.onCreateAtPlace!(poi);
                      } else {
                        widget.onGoToCreate();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accentPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                    label: const Text('Kapsül Bırak'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.locationService.removeListener(_onLocationChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locationService;
    final p = AppPalette.of(context);
    final userPos = loc.currentLatLng;

    return Column(
      children: [
        // 1. Instagram Stories Tarzı Yuvarlak Paylaşım & Mekan Şeridi
        StoryStrip(
          capsules: _capsules.take(8).toList(),
          popularPlaces: _popularPlaces.take(6).toList(),
          unlockedIds: loc.unlockedIds,
          onAddTap: widget.onGoToCreate,
          onCapsuleTap: _showCapsuleStoryPreview,
          onPlaceTap: _showPopularPlaceSheet,
        ),

        // 2. Kompakt Konum & Kategori Çubuğu
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: p.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      loc.isSimulated ? Icons.explore_rounded : Icons.my_location_rounded,
                      size: 13,
                      color: loc.isSimulated ? p.accentPrimary : p.accentSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${loc.statusLabel} • ±${loc.accuracyMeters.toStringAsFixed(0)}m',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AppConfig.categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, idx) {
                      final cat = AppConfig.categories[idx];
                      final selected = cat == _selectedCategory;
                      return ChoiceChip(
                        label: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : p.textPrimary,
                          ),
                        ),
                        selected: selected,
                        showCheckmark: false,
                        selectedColor: p.accentPrimary,
                        backgroundColor: p.surface,
                        side: BorderSide(color: selected ? p.accentPrimary : p.border),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        onSelected: (_) {
                          setState(() => _selectedCategory = cat);
                          _loadData();
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. Yuvarlatılmış Etkileşimli Harita (Kapsüller + Popüler Yerler)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            height: 215,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: p.isDark ? 0.35 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: userPos,
                    initialZoom: 15.6,
                    minZoom: 4,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'tr.edu.kapsular.app',
                      tileBuilder: p.isDark ? _darkMapTileFilter : null,
                    ),
                    CircleLayer(
                      circles: [
                        // Kullanıcının anlık GPS doğruluk halkası
                        CircleMarker(
                          point: userPos,
                          radius: loc.accuracyMeters.clamp(8.0, 50.0),
                          useRadiusInMeter: true,
                          color: const Color(0xFF2563EB).withValues(alpha: 0.16),
                          borderColor: const Color(0xFF3B82F6).withValues(alpha: 0.7),
                          borderStrokeWidth: 1.5,
                        ),
                        ..._capsules.map((c) => CircleMarker(
                              point: LatLng(c.latitude, c.longitude),
                              radius: c.arTriggerRadiusMeters,
                              useRadiusInMeter: true,
                              color: c.inUnlockRange
                                  ? const Color(0xFF10B981).withValues(alpha: 0.22)
                                  : p.accentPrimary.withValues(alpha: 0.14),
                              borderColor: c.inUnlockRange
                                  ? const Color(0xFF10B981)
                                  : p.accentPrimary,
                              borderStrokeWidth: 1.5,
                            )),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // Çevredeki Popüler Yerler (Altın Yıldız İkonları)
                        ..._popularPlaces
                            .where((poi) => poi.latitude != null && poi.longitude != null)
                            .map((poi) => Marker(
                                  point: LatLng(poi.latitude!, poi.longitude!),
                                  width: 34,
                                  height: 34,
                                  child: GestureDetector(
                                    onTap: () => _showPopularPlaceSheet(poi),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: p.accentAmber,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.22),
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.star_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                )),
                        // Kullanıcı Konumu + Anlık Bakış Yönü Konisi & Oku
                        Marker(
                          point: userPos,
                          width: 96,
                          height: 96,
                          child: _UserHeadingMarker(headingDeg: loc.headingDeg),
                        ),
                        // Kapsül İşaretçileri
                        ..._capsules.map((c) {
                          final unlocked = loc.unlockedIds.contains(c.id);
                          return Marker(
                            point: LatLng(c.latitude, c.longitude),
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () => _showCapsuleStoryPreview(c),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: unlocked
                                      ? const Color(0xFF10B981)
                                      : (c.inArRange ? p.accentSecondary : p.accentPrimary),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2.5),
                                ),
                                child: Icon(
                                  unlocked
                                      ? Icons.lock_open_rounded
                                      : Icons.hourglass_bottom_rounded,
                                  color: Colors.white,
                                  size: 17,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
                // Harita sağ alt odak + GPS/Demo geçiş butonu
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Row(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'gps_toggle_btn',
                        backgroundColor: p.surface,
                        foregroundColor: p.accentPrimary,
                        onPressed: () async {
                          if (loc.isSimulated) {
                            await loc.enableRealGps();
                          } else {
                            loc.switchToCampusSimulation();
                          }
                          _mapController.move(loc.currentLatLng, 16.0);
                          _loadData(silent: true);
                        },
                        child: Icon(
                          loc.isSimulated ? Icons.gps_fixed_rounded : Icons.school_rounded,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'center_user_btn',
                        backgroundColor: p.accentPrimary,
                        foregroundColor: Colors.white,
                        onPressed: () => _mapController.move(loc.currentLatLng, 16.0),
                        child: const Icon(Icons.my_location_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
                // Anlık Pusula / Yön Göstergesi (Harita sağ üst)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: p.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.rotate(
                          angle: loc.headingDeg * math.pi / 180.0,
                          child: const Icon(
                            Icons.navigation_rounded,
                            size: 14,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          loc.compassCardinalLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Popüler yer sayısı etiketi
                if (_popularPlaces.isNotEmpty)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 14, color: p.accentAmber),
                          const SizedBox(width: 4),
                          Text(
                            '${_popularPlaces.length} popüler yer',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 4. Haritanın Altına Giderken Solarak Kayan Liste (ShaderMask)
        Expanded(
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0.0, -0.78),
                colors: [Colors.transparent, Colors.white],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 108),
                      children: [
                        if (_popularPlaces.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.local_fire_department_rounded,
                                  size: 16, color: p.accentAmber),
                              const SizedBox(width: 6),
                              Text(
                                'Yakındaki Popüler Noktalar',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 92,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _popularPlaces.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (_, idx) {
                                final poi = _popularPlaces[idx];
                                return GestureDetector(
                                  onTap: () => _showPopularPlaceSheet(poi),
                                  child: Container(
                                    width: 190,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: p.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: p.border),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            poi.imageUrl,
                                            width: 60,
                                            height: 74,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: 60,
                                              height: 74,
                                              color: p.surfaceMuted,
                                              child: Icon(Icons.place_rounded, color: p.accentAmber),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                poi.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: p.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${(poi.distanceMeters ?? 0).toStringAsFixed(0)} m',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: p.accentAmber,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          'Zaman Kapsülleri',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_capsules.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'Bu kategoride kapsül bulunamadı.',
                                style: TextStyle(color: p.textSecondary),
                              ),
                            ),
                          )
                        else
                          ..._capsules.map((cap) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: CapsuleCard(
                                  capsule: cap,
                                  isUnlocked: loc.unlockedIds.contains(cap.id),
                                  onOpenAr: () => _openArScreen(cap),
                                  onWalkHere: () =>
                                      _startWalkTo(cap.latitude, cap.longitude, cap.title),
                                ),
                              )),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _darkMapTileFilter(BuildContext context, Widget tileWidget, TileImage tile) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -0.85, 0, 0, 0, 235,
        0, -0.85, 0, 0, 240,
        0, 0, -0.78, 0, 248,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }
}

class _UserHeadingMarker extends StatelessWidget {
  final double headingDeg;

  const _UserHeadingMarker({required this.headingDeg});

  @override
  Widget build(BuildContext context) {
    final angleRad = headingDeg * math.pi / 180.0;
    return Transform.rotate(
      angle: angleRad,
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Görüş / Bakış Yönü Konisi (yukarı = 0° Kuzey)
            CustomPaint(
              size: const Size(96, 96),
              painter: _HeadingConePainter(),
            ),
            // Merkez mavi konum noktası + beyaz yön oku
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.55),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Colors.white,
                size: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // -90 deg in canvas coordinates is straight UP (0 deg North)
    const sweepRad = 70 * math.pi / 180.0;
    const startRad = -math.pi / 2 - sweepRad / 2;

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF3B82F6).withValues(alpha: 0.48),
          const Color(0xFF3B82F6).withValues(alpha: 0.0),
        ],
      ).createShader(rect);

    canvas.drawArc(rect, startRad, sweepRad, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
