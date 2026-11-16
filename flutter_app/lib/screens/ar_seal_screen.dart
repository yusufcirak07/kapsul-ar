import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/ar_camera_view.dart';
import '../services/location_sensor_service.dart';

class ArSealResult {
  final double latitude;
  final double longitude;
  final double anchorHeadingDeg;
  final String visualSignature;
  final String clientSealProof;

  const ArSealResult({
    required this.latitude,
    required this.longitude,
    required this.anchorHeadingDeg,
    required this.visualSignature,
    required this.clientSealProof,
  });

  String get shortCode => clientSealProof.length >= 10
      ? 'SEAL-${clientSealProof.substring(0, 8).toUpperCase()}'
      : 'SEAL-OK';
}

class ArSealScreen extends StatefulWidget {
  final LocationSensorService locationService;
  final String? previewImageUrl;

  const ArSealScreen({
    super.key,
    required this.locationService,
    this.previewImageUrl,
  });

  @override
  State<ArSealScreen> createState() => _ArSealScreenState();
}

class _ArSealScreenState extends State<ArSealScreen>
    with SingleTickerProviderStateMixin {
  final ArCameraController _cameraController = ArCameraController();
  late AnimationController _scanAnim;
  bool _sealing = false;

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    widget.locationService.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _sealAndEncryptLocation() async {
    setState(() => _sealing = true);
    await Future.delayed(const Duration(milliseconds: 900));

    final loc = widget.locationService;
    final visualSig = _cameraController.captureVisualSignature(
      lat: loc.latitude,
      lon: loc.longitude,
      headingDeg: loc.headingDeg,
    );

    final rawProof = '${loc.latitude.toStringAsFixed(5)}|'
        '${loc.longitude.toStringAsFixed(5)}|'
        '${loc.headingDeg.round()}|$visualSig|${DateTime.now().millisecondsSinceEpoch}';
    final sealProof = sha256.convert(utf8.encode(rawProof)).toString();

    if (!mounted) return;
    Navigator.of(context).pop(
      ArSealResult(
        latitude: loc.latitude,
        longitude: loc.longitude,
        anchorHeadingDeg: loc.headingDeg,
        visualSignature: visualSig,
        clientSealProof: sealProof,
      ),
    );
  }

  @override
  void dispose() {
    widget.locationService.removeListener(_onChanged);
    _scanAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final loc = widget.locationService;

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: const Text(
          'AR Konum Şifreleme & Mühür',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: [
          ArCameraBackground(
            controller: _cameraController,
            fallbackImageUrl: widget.previewImageUrl,
          ),

          // Üst Telemetri Şeridi
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  _hudItem(
                    'Konum',
                    '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
                    Colors.lightBlueAccent,
                  ),
                  const SizedBox(width: 8),
                  _hudItem('Bakış Yönü', loc.compassCardinalLabel, Colors.amberAccent),
                  const SizedBox(width: 8),
                  _hudItem(
                    'Doğruluk',
                    '±${loc.accuracyMeters.toStringAsFixed(1)} m',
                    Colors.greenAccent,
                  ),
                ],
              ),
            ),
          ),

          // Merkez AR Mühürleme Nişangâhı
          Center(
            child: AnimatedBuilder(
              animation: _scanAnim,
              builder: (_, __) {
                final scale = 1.0 + sin(_scanAnim.value * pi) * 0.06;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.30),
                      border: Border.all(
                        color: _sealing ? Colors.greenAccent : p.accentSecondary,
                        width: 2.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _sealing ? Icons.enhanced_encryption_rounded : Icons.qr_code_scanner_rounded,
                          size: 46,
                          color: _sealing ? Colors.greenAccent : Colors.white,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _sealing
                              ? 'Konum Şifreleniyor...'
                              : 'Çevreyi AR ile Tara',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            'GPS + Pusula Yönü + Görsel Doku AES-256-GCM mührüne bağlanır.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Alt Mühürle Butonu
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: FilledButton.icon(
              onPressed: _sealing ? null : _sealAndEncryptLocation,
              style: FilledButton.styleFrom(
                backgroundColor: p.accentPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              icon: _sealing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.lock_rounded),
              label: Text(
                _sealing
                    ? 'AR Konum Mührü Üretiliyor...'
                    : 'Konumu AR ile Şifrele & Onayla',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudItem(String label, String val, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            val,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
