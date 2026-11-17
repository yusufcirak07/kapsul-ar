import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';
import '../models/capsule_models.dart';
import '../services/api_client.dart';
import '../services/location_sensor_service.dart';

class RouteBuilderPanel extends StatefulWidget {
  final ApiClient api;
  final LocationSensorService locationService;
  final ThemeController themeController;
  final ValueChanged<WalkingRoute> onRouteCreated;

  const RouteBuilderPanel({
    super.key,
    required this.api,
    required this.locationService,
    required this.themeController,
    required this.onRouteCreated,
  });

  @override
  State<RouteBuilderPanel> createState() => _RouteBuilderPanelState();
}

class _RouteBuilderPanelState extends State<RouteBuilderPanel> {
  final _titleController = TextEditingController();
  final _cityController = TextEditingController(text: 'Kampüs / İlçe Merkezi');
  final _descController = TextEditingController();
  final _waypointNameController = TextEditingController();
  final MapController _mapController = MapController();

  final List<RouteWaypoint> _waypoints = [];
  List<NearbyMediaItem> _nearbyPlaces = [];
  String _difficulty = 'Kolay';
  String _socialTag = 'Üni Öğrenci Buluşması';
  bool _isRawPreset = false;
  bool _submitting = false;

  static const List<String> _difficulties = ['Kolay', 'Orta', 'Zor'];
  static const List<String> _socialTags = [
    'Üni Öğrenci Buluşması',
    'Halk Akşam Yürüyüşü',
    'Doğa & Kültür Keşfi',
    'Yalnızlara İyi Gelen Keşif',
  ];

  @override
  void initState() {
    super.initState();
    _loadNearbyPlaces();
  }

  Future<void> _loadNearbyPlaces() async {
    final items = await widget.api.fetchNearbyPopularPlaces(
      lat: widget.locationService.latitude,
      lon: widget.locationService.longitude,
    );
    if (!mounted) return;
    setState(() => _nearbyPlaces = items);
  }

  void _addWaypoint(double lat, double lon, {String? customName, String hint = ''}) {
    final idx = _waypoints.length + 1;
    final typed = _waypointNameController.text.trim();
    final name = customName ?? (typed.isNotEmpty ? typed : 'Durak $idx');
    setState(() {
      _waypoints.add(RouteWaypoint(
        order: idx,
        name: name,
        latitude: lat,
        longitude: lon,
        hint: hint,
      ));
      _waypointNameController.clear();
    });
  }

  void _removeLastWaypoint() {
    if (_waypoints.isEmpty) return;
    setState(() => _waypoints.removeLast());
  }

  double get _totalDistanceMeters => ApiClient.computeRouteDistanceMeters(_waypoints);
  double get _totalKm => _totalDistanceMeters / 1000.0;
  int get _estMinutes => (_totalKm / 4.2 * 60).round().clamp(5, 999);
  int get _estSteps => (_totalDistanceMeters / 0.72).round();

  Future<void> _submitRoute() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen rota için bir başlık yazın.')),
      );
      return;
    }
    if (_waypoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Haritaya dokunarak en az 2 yürüyüş durağı ekleyin.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final created = await widget.api.createRoute(
      title: _titleController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? 'Topluluk tarafından sıfırdan oluşturulan açık hava sosyal yürüyüş rotası.'
          : _descController.text.trim(),
      cityDistrict: _cityController.text.trim().isEmpty
          ? 'Yerel İlçe'
          : _cityController.text.trim(),
      difficulty: _difficulty,
      socialTag: _socialTag,
      isRawPreset: _isRawPreset,
      createdBy: widget.themeController.displayName,
      waypoints: _waypoints,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (created != null) {
      _titleController.clear();
      _descController.clear();
      setState(() => _waypoints.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${created.title}" yayınlandı! Diğer kullanıcılar artık puanlayabilir.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onRouteCreated(created);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _cityController.dispose();
    _descController.dispose();
    _waypointNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final loc = widget.locationService;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '0\'dan Yürüyüş Rotası Oluştur',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: p.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Gezilecek yer yok sanılan ilçe ve kampüslerde yeni yürüyüş durakları çizin; topluluk yürüyüp puanlasın.',
          style: TextStyle(fontSize: 12.5, color: p.textSecondary),
        ),
        const SizedBox(height: 14),

        // Harita Üzerinde Durak Çizimi
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.route_rounded, color: p.accentSecondary, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Haritaya Dokunarak Durak Ekle (${_waypoints.length} durak)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: p.textPrimary),
                    ),
                  ),
                  if (_waypoints.length >= 2)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.accentSecondary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_totalKm.toStringAsFixed(2)} km • $_estMinutes dk',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: p.accentSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _waypointNameController,
                decoration: InputDecoration(
                  hintText: 'Sonraki durak adı (opsiyonel, örn: Park Girişi)',
                  isDense: true,
                  filled: true,
                  fillColor: p.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 210,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: loc.currentLatLng,
                      initialZoom: 15.2,
                      onTap: (_, latlng) => _addWaypoint(latlng.latitude, latlng.longitude),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'tr.edu.kapsular.app',
                      ),
                      if (_waypoints.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _waypoints
                                  .map((w) => LatLng(w.latitude, w.longitude))
                                  .toList(),
                              strokeWidth: 4.5,
                              color: p.accentSecondary,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: loc.currentLatLng,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                          ..._waypoints.map((w) => Marker(
                                point: LatLng(w.latitude, w.longitude),
                                width: 30,
                                height: 30,
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: p.accentPrimary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Text(
                                    '${w.order}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _addWaypoint(
                      loc.latitude,
                      loc.longitude,
                      customName: _waypoints.isEmpty ? 'Başlangıç Konumum' : 'Ara Durak ${_waypoints.length + 1}',
                    ),
                    icon: const Icon(Icons.my_location_rounded, size: 16),
                    label: const Text('Konumumu Ekle'),
                  ),
                  if (_waypoints.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _removeLastWaypoint,
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text('Geri Al'),
                    ),
                  if (_waypoints.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _waypoints.clear()),
                      child: const Text('Temizle'),
                    ),
                ],
              ),
              if (_nearbyPlaces.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Yakındaki Açık Alanları Durak Olarak Ekle:',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textSecondary),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _nearbyPlaces.take(6).length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, idx) {
                      final poi = _nearbyPlaces[idx];
                      return ActionChip(
                        avatar: Icon(Icons.add_location_alt_rounded, size: 14, color: p.accentPrimary),
                        label: Text(poi.title, style: const TextStyle(fontSize: 11)),
                        onPressed: poi.latitude != null && poi.longitude != null
                            ? () {
                                _addWaypoint(
                                  poi.latitude!,
                                  poi.longitude!,
                                  customName: poi.title,
                                  hint: poi.description,
                                );
                                _mapController.move(LatLng(poi.latitude!, poi.longitude!), 15.5);
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Rota Bilgileri Formu
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Rota Adı',
                  hintText: 'Örn: Yurt Önü – Gölet Akşam Sosyalleşme Rotası',
                  filled: true,
                  fillColor: p.surfaceMuted,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cityController,
                decoration: InputDecoration(
                  labelText: 'Şehir / İlçe',
                  hintText: 'Örn: Burdur / Merkez veya Antalya / Kaş',
                  filled: true,
                  fillColor: p.surfaceMuted,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Açıklama & Sosyalleşme Notu',
                  hintText: 'Kimler katılabilir, buluşma saatleri veya durak ipuçları...',
                  filled: true,
                  fillColor: p.surfaceMuted,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              Text('Zorluk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: _difficulties.map((d) {
                  final sel = _difficulty == d;
                  return ChoiceChip(
                    label: Text(d),
                    selected: sel,
                    onSelected: (_) => setState(() => _difficulty = d),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Text('Sosyalleşme & Hedef Etiketi',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _socialTags.map((tag) {
                  final sel = _socialTag == tag;
                  return ChoiceChip(
                    label: Text(tag, style: const TextStyle(fontSize: 11.5)),
                    selected: sel,
                    onSelected: (_) => setState(() => _socialTag = tag),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ham Rota Şablonu Olarak Yayınla', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text(
                  'Likya Yolu gibi başlangıç-bitiş duraklı ham parkur olarak işaretler',
                  style: TextStyle(fontSize: 11),
                ),
                value: _isRawPreset,
                onChanged: (v) => setState(() => _isRawPreset = v),
              ),
              if (_waypoints.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Tahmini Çıktı: ${_totalKm.toStringAsFixed(2)} km • $_estMinutes dk • ~$_estSteps adım',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accentSecondary),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submitRoute,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accentPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.publish_rounded),
                  label: Text(_submitting ? 'Kaydediliyor...' : 'Rotayı Yayınla ve Puanlamaya Aç'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
