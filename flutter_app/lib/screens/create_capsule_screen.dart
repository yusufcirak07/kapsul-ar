import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/capsule_models.dart';
import '../services/api_client.dart';
import '../services/location_sensor_service.dart';
import '../widgets/audio_note_widget.dart';
import '../widgets/pixel_art_editor.dart';
import '../widgets/route_builder_panel.dart';
import 'ar_seal_screen.dart';

class CreateCapsuleScreen extends StatefulWidget {
  final ApiClient api;
  final LocationSensorService locationService;
  final ThemeController themeController;
  final NearbyMediaItem? prefilledPlace;
  final bool initialRouteMode;
  final VoidCallback onCreated;
  final ValueChanged<WalkingRoute>? onRouteCreated;

  const CreateCapsuleScreen({
    super.key,
    required this.api,
    required this.locationService,
    required this.themeController,
    this.prefilledPlace,
    this.initialRouteMode = false,
    required this.onCreated,
    this.onRouteCreated,
  });

  @override
  State<CreateCapsuleScreen> createState() => _CreateCapsuleScreenState();
}

class _CreateCapsuleScreenState extends State<CreateCapsuleScreen> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController(text: 'Kampüs Yürüyüş Noktası');
  final _noteController = TextEditingController();
  final _mediaSearchController = TextEditingController(text: 'Istanbul');

  String _contentType = 'note';
  String _category = 'Kampüs Yaşamı';
  late double _unlockRadius;
  bool _isEncrypted = true;
  bool _submitting = false;
  bool _loadingMedia = false;
  bool _routeMode = false;
  ArSealResult? _arSeal;

  List<NearbyMediaItem> _mediaSuggestions = [];
  String? _selectedImageUrl;
  List<int> _pixelArtGrid = List.filled(256, 0);
  int _audioDuration = 0;
  List<double> _audioWaveform = [];

  @override
  void initState() {
    super.initState();
    _routeMode = widget.initialRouteMode;
    _unlockRadius = widget.themeController.defaultRadius;
    _applyPrefilledPlace();
    _loadMediaSuggestions();
  }

  @override
  void didUpdateWidget(covariant CreateCapsuleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRouteMode != oldWidget.initialRouteMode) {
      _routeMode = widget.initialRouteMode;
    }
    if (widget.prefilledPlace != oldWidget.prefilledPlace && widget.prefilledPlace != null) {
      _routeMode = false;
      _applyPrefilledPlace();
    }
  }

  void _applyPrefilledPlace() {
    final place = widget.prefilledPlace;
    if (place == null) return;
    _locationController.text = place.title;
    if (place.imageUrl.isNotEmpty) {
      _selectedImageUrl = place.imageUrl;
    }
  }

  Future<void> _loadMediaSuggestions() async {
    setState(() => _loadingMedia = true);
    final items = await widget.api.fetchNearbyOrSearchMedia(
      query: _mediaSearchController.text,
      lat: widget.locationService.latitude,
      lon: widget.locationService.longitude,
    );
    if (!mounted) return;
    setState(() {
      _mediaSuggestions = items;
      _selectedImageUrl ??= items.isNotEmpty ? items.first.imageUrl : null;
      _loadingMedia = false;
    });
  }

  Future<void> _captureArSeal() async {
    final seal = await Navigator.of(context).push<ArSealResult>(
      MaterialPageRoute(
        builder: (_) => ArSealScreen(
          locationService: widget.locationService,
          previewImageUrl: _selectedImageUrl,
        ),
      ),
    );
    if (seal != null && mounted) {
      setState(() => _arSeal = seal);
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen kapsül için kısa bir başlık yazın.')),
      );
      return;
    }

    if (_arSeal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konumu onaylamak için önce "AR ile Konumu Şifrele" adımını tamamlayın.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _captureArSeal();
      if (_arSeal == null) return;
    }

    setState(() => _submitting = true);

    final seal = _arSeal!;
    final targetLat = widget.prefilledPlace?.latitude ?? seal.latitude;
    final targetLon = widget.prefilledPlace?.longitude ?? seal.longitude;

    final payload = {
      'title': _titleController.text.trim(),
      'description': _noteController.text.trim().isEmpty
          ? 'Konum kilitli dijital zaman kapsülü.'
          : _noteController.text.trim(),
      'category': _category,
      'contentType': _contentType,
      'latitude': targetLat,
      'longitude': targetLon,
      'unlockRadiusMeters': _unlockRadius,
      'arTriggerRadiusMeters': 15.0,
      'locationName': _locationController.text.trim(),
      'imageUrl': _selectedImageUrl,
      'noteText': _noteController.text.trim(),
      if (_contentType == 'pixelArt') 'pixelArtGrid': _pixelArtGrid,
      if (_contentType == 'audio') 'audioDurationSec': _audioDuration > 0 ? _audioDuration : 12,
      if (_contentType == 'audio')
        'audioWaveform': _audioWaveform.isNotEmpty
            ? _audioWaveform
            : [0.3, 0.6, 0.8, 0.5, 0.9, 0.4, 0.7, 0.5],
      'visualSignature': seal.visualSignature,
      'anchorHeadingDeg': seal.anchorHeadingDeg,
      'clientSealProof': seal.clientSealProof,
      'isEncrypted': _isEncrypted,
      'createdBy': widget.themeController.displayName,
    };

    final created = await widget.api.createCapsule(payload);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (created != null) {
      _titleController.clear();
      _noteController.clear();
      setState(() => _arSeal = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${created.title}" AR konumuyla şifrelenip haritaya bırakıldı!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onCreated();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sunucuya ulaşılamadı; backend bağlantısını kontrol edin.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    _mediaSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final loc = widget.locationService;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _routeMode = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_routeMode ? p.accentPrimary : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Zaman Kapsülü',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: !_routeMode ? Colors.white : p.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _routeMode = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _routeMode ? p.accentSecondary : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '0\'dan Rota Oluştur',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _routeMode ? Colors.white : p.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_routeMode)
            RouteBuilderPanel(
              api: widget.api,
              locationService: widget.locationService,
              themeController: widget.themeController,
              onRouteCreated: (route) {
                if (widget.onRouteCreated != null) {
                  widget.onRouteCreated!(route);
                } else {
                  widget.onCreated();
                }
              },
            )
          else ...[
            Text(
              'Zaman Kapsülü Bırak',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Bulunduğunuz noktaya (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}) dijital bir iz bırakın.',
            style: TextStyle(fontSize: 12.5, color: p.textSecondary),
          ),
          const SizedBox(height: 16),

          // ADIM 1: Tür Seçimi
          _stepCard(
            p: p,
            step: '1',
            title: 'Ne Bırakmak İstersin?',
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: [
                _typeOption(p, 'note', 'Not / Anı', Icons.auto_stories_rounded),
                _typeOption(p, 'photo', 'Fotoğraf', Icons.photo_camera_back_rounded),
                _typeOption(p, 'pixelArt', 'Piksel Sanat', Icons.grid_view_rounded),
                _typeOption(p, 'audio', 'Sesli Anı', Icons.graphic_eq_rounded),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ADIM 2: İçerik ve Mekan Görseli
          _stepCard(
            p: p,
            step: '2',
            title: 'İçeriğini Oluştur',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: _inputDeco(p, 'Başlık', 'Örn: Çınar Altı Hatırası'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: _inputDeco(p, 'Kategori', ''),
                        items: const [
                          DropdownMenuItem(value: 'Kampüs Yaşamı', child: Text('Kampüs Yaşamı')),
                          DropdownMenuItem(value: 'Kültürel Miras', child: Text('Kültürel Miras')),
                          DropdownMenuItem(
                              value: 'Fiziksel Aktivite', child: Text('Fiziksel Aktivite')),
                          DropdownMenuItem(value: 'Yerel İşletme', child: Text('Yerel İşletme')),
                        ],
                        onChanged: (v) => setState(() => _category = v ?? 'Kampüs Yaşamı'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _locationController,
                        decoration: _inputDeco(p, 'Mekan Adı', 'Örn: Kütüphane'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: _inputDeco(
                    p,
                    'Mesajın',
                    'Bu noktaya yürüyenlere bırakacağın not...',
                  ),
                ),
                if (_contentType == 'pixelArt') ...[
                  const SizedBox(height: 14),
                  PixelArtEditor(
                    initialGrid: _pixelArtGrid,
                    onChanged: (grid) => _pixelArtGrid = grid,
                  ),
                ],
                if (_contentType == 'audio') ...[
                  const SizedBox(height: 14),
                  AudioNoteRecorder(
                    onRecorded: (res) {
                      setState(() {
                        _audioDuration = res.$1;
                        _audioWaveform = res.$2;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Mekan Görseli Seç (Wikimedia)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _mediaSearchController,
                        decoration: _inputDeco(p, 'Görsel Ara', 'Galata, Kampüs...'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _loadingMedia ? null : _loadMediaSuggestions,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accentSecondary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.image_search_rounded, size: 18),
                      label: const Text('Çek'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loadingMedia)
                  const LinearProgressIndicator()
                else if (_mediaSuggestions.isNotEmpty)
                  SizedBox(
                    height: 82,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _mediaSuggestions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) {
                        final item = _mediaSuggestions[idx];
                        final selected = _selectedImageUrl == item.imageUrl;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedImageUrl = item.imageUrl),
                          child: Container(
                            width: 106,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected ? p.accentPrimary : p.border,
                                width: selected ? 2.5 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  item.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.broken_image_outlined,
                                    color: p.textSecondary,
                                  ),
                                ),
                                if (selected)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: CircleAvatar(
                                      radius: 10,
                                      backgroundColor: p.accentPrimary,
                                      child: const Icon(Icons.check, size: 13, color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ADIM 3: AR Konum Şifreleme & Bırak
          _stepCard(
            p: p,
            step: '3',
            title: 'AR Konum Mührü ve Kilit',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [5.0, 10.0, 15.0].map((r) {
                    final selected = _unlockRadius == r;
                    return ChoiceChip(
                      label: Text(
                        '${r.toInt()} metre',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : p.textPrimary,
                        ),
                      ),
                      selected: selected,
                      showCheckmark: false,
                      selectedColor: p.accentPrimary,
                      backgroundColor: p.surfaceMuted,
                      onSelected: (_) => setState(() => _unlockRadius = r),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'AES-256-GCM Konum Şifrelemesi',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Kapsül içeriği yalnızca AR konumu doğrulandığında çözülür.',
                    style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                  ),
                  value: _isEncrypted,
                  activeThumbColor: p.accentPrimary,
                  onChanged: (v) => setState(() => _isEncrypted = v),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _arSeal != null
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : p.surfaceMuted,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _arSeal != null ? const Color(0xFF10B981) : p.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _arSeal != null ? Icons.verified_user_rounded : Icons.view_in_ar_rounded,
                        color: _arSeal != null ? const Color(0xFF10B981) : p.accentPrimary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _arSeal != null
                                  ? 'AR Konum Mührü Onaylandı'
                                  : 'AR Konum Mührü Gerekli',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary,
                              ),
                            ),
                            Text(
                              _arSeal != null
                                  ? '${_arSeal!.shortCode} • Yön ${_arSeal!.anchorHeadingDeg.round()}°'
                                  : 'Bulunduğunuz noktayı AR kamera ile şifreleyin.',
                              style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _captureArSeal,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accentSecondary.withValues(alpha: 0.16),
                          foregroundColor: p.accentSecondary,
                        ),
                        child: Text(_arSeal != null ? 'Yenile' : 'AR Tara'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // %10 Accent Renk Kuralı: Belirgin Ana Buton
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: p.accentPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.rocket_launch_rounded),
              label: Text(
                _submitting ? 'Kapsül Yerleştiriliyor...' : 'Kapsülü Konuma Bırak',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          ],
        ],
      ),
    );
  }

  Widget _stepCard({
    required AppPalette p,
    required String step,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              CircleAvatar(
                radius: 13,
                backgroundColor: p.accentPrimary,
                child: Text(
                  step,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _typeOption(AppPalette p, String value, String label, IconData icon) {
    final selected = _contentType == value;
    return GestureDetector(
      onTap: () => setState(() => _contentType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? p.accentPrimary : p.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? p.accentPrimary : p.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : p.accentPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : p.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(AppPalette p, String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: p.surfaceMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.border),
      ),
    );
  }
}
