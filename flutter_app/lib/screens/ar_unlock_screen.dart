import 'dart:math';

import 'package:flutter/material.dart';

import '../models/capsule_models.dart';
import '../services/api_client.dart';
import '../services/ar_camera_view.dart';
import '../services/location_sensor_service.dart';
import '../widgets/audio_note_widget.dart';
import '../widgets/pixel_art_editor.dart';

class ArUnlockScreen extends StatefulWidget {
  final TimeCapsule capsule;
  final ApiClient api;
  final LocationSensorService locationService;

  const ArUnlockScreen({
    super.key,
    required this.capsule,
    required this.api,
    required this.locationService,
  });

  @override
  State<ArUnlockScreen> createState() => _ArUnlockScreenState();
}

class _ArUnlockScreenState extends State<ArUnlockScreen>
    with SingleTickerProviderStateMixin {
  final ArCameraController _cameraController = ArCameraController();
  late AnimationController _pulseController;
  bool _verifying = false;
  UnlockAttemptResult? _result;
  TimeCapsule? _unlockedCapsule;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    widget.locationService.addListener(_onMoved);
  }

  void _onMoved() {
    if (mounted) setState(() {});
  }

  double get _currentDistance => LocationSensorService.distanceMeters(
        widget.locationService.latitude,
        widget.locationService.longitude,
        widget.capsule.latitude,
        widget.capsule.longitude,
      );

  Future<void> _verifyAndUnlock({bool spoofTest = false}) async {
    setState(() => _verifying = true);

    if (spoofTest) {
      // Inject impossible GPS jump to test Anti-Spoofing rejection
      widget.locationService.injectSpoofJump(
        widget.capsule.latitude + 0.0045,
        widget.capsule.longitude + 0.0045,
      );
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final observedVisual = _cameraController.captureVisualSignature(
      lat: widget.locationService.latitude,
      lon: widget.locationService.longitude,
      headingDeg: widget.locationService.headingDeg,
    );

    final res = await widget.api.attemptUnlock(
      capsuleId: widget.capsule.id,
      telemetryWindow: widget.locationService.telemetryWindow,
      visualSignature: observedVisual.isNotEmpty
          ? observedVisual
          : widget.capsule.visualSignature,
      observedHeadingDeg: widget.locationService.headingDeg,
      bypassVisualInDemo: true,
    );

    if (!mounted) return;
    setState(() {
      _verifying = false;
      _result = res;
      if (res.unlocked && res.capsule != null) {
        _unlockedCapsule = res.capsule;
        widget.locationService.markCapsuleUnlocked(widget.capsule.id);
        widget.api.logActivity(stepsAdded: 65, distanceAdded: 48);
      }
    });
  }

  @override
  void dispose() {
    widget.locationService.removeListener(_onMoved);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dist = _currentDistance;
    final inUnlockRange = dist <= widget.capsule.unlockRadiusMeters;
    final unlocked = _unlockedCapsule != null ||
        widget.locationService.unlockedIds.contains(widget.capsule.id);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          widget.capsule.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (!inUnlockRange && !unlocked)
            TextButton.icon(
              onPressed: () {
                widget.locationService.startDemoWalkToward(
                  widget.capsule.latitude,
                  widget.capsule.longitude,
                );
              },
              icon: const Icon(Icons.directions_walk, color: Colors.tealAccent, size: 18),
              label: const Text(
                '5m İçine Yürü',
                style: TextStyle(color: Colors.tealAccent, fontSize: 12),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Canlı WebRTC Kamera veya AR Referans Görünümü
          ArCameraBackground(
            controller: _cameraController,
            fallbackImageUrl: widget.capsule.imageUrl,
          ),

          // Üst Telemetri & Hibrit Doğrulama Şeridi
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: inUnlockRange ? Colors.greenAccent : Colors.white24,
                ),
              ),
              child: Row(
                children: [
                  _hudPill(
                    'Mesafe',
                    '${dist.toStringAsFixed(1)} m',
                    inUnlockRange ? Colors.greenAccent : Colors.amberAccent,
                  ),
                  const SizedBox(width: 10),
                  _hudPill(
                    'Sensör Penceresi',
                    '${widget.locationService.telemetryWindow.length} örnek',
                    Colors.lightBlueAccent,
                  ),
                  const SizedBox(width: 10),
                  _hudPill(
                    'İvme',
                    '${widget.locationService.currentAccelMagnitude.toStringAsFixed(1)} m/s²',
                    Colors.white,
                  ),
                ],
              ),
            ),
          ),

          // Orta AR Nişangâh veya Açılmış Kapsül İçeriği
          Center(
            child: unlocked
                ? _buildUnlockedCapsuleOverlay()
                : AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) {
                      final scale = 1.0 + sin(_pulseController.value * pi) * 0.08;
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 210,
                          height: 210,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: inUnlockRange
                                  ? Colors.greenAccent
                                  : Colors.tealAccent.withValues(alpha: 0.7),
                              width: 2.5,
                            ),
                            color: Colors.black.withValues(alpha: 0.25),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.view_in_ar_rounded,
                                size: 48,
                                color: inUnlockRange ? Colors.greenAccent : Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                inUnlockRange
                                    ? 'Görsel İşaretçi Hazır'
                                    : '${dist.toStringAsFixed(1)} m kaldı',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.capsule.locationName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Alt Aksiyon Paneli
          Positioned(
            bottom: 18,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_result != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _result!.unlocked
                          ? const Color(0xFF065F46).withValues(alpha: 0.92)
                          : const Color(0xFF7F1D1D).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _result!.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Güven: %${_result!.antiSpoofing.trustScore.toStringAsFixed(0)} • '
                          'Kalman: ${_result!.antiSpoofing.kalmanInnovationMeters.toStringAsFixed(1)} m • '
                          'Yön Uyumu: %${_result!.headingAlignmentScore.toStringAsFixed(0)} • '
                          'Mühür: ${_result!.spatialSealVerified ? "AES-256 Çözüldü" : "Bekliyor"}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        if (_result!.antiSpoofing.layers.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: _result!.antiSpoofing.layers.map((l) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${l.passed ? "✓" : "✕"} ${l.name}: %${l.score.toStringAsFixed(0)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 10),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (!unlocked)
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          onPressed: _verifying ? null : () => _verifyAndUnlock(),
                          style: FilledButton.styleFrom(
                            backgroundColor: inUnlockRange
                                ? const Color(0xFF10B981)
                                : const Color(0xFF1E3A8A),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: _verifying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.qr_code_scanner_rounded),
                          label: Text(
                            _verifying
                                ? 'Doğrulanıyor...'
                                : 'Hibrit Doğrulama ile Aç',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: _verifying
                              ? null
                              : () => _verifyAndUnlock(spoofTest: true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.amberAccent,
                            side: const BorderSide(color: Colors.amberAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Spoof Test', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudPill(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockedCapsuleOverlay() {
    final cap = _unlockedCapsule ?? widget.capsule;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cap.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${cap.locationName} • ${cap.createdBy}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            if (cap.imageUrl != null && cap.imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  cap.imageUrl!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (cap.contentType == 'pixelArt' && cap.pixelArtGrid != null) ...[
              const SizedBox(height: 12),
              Center(child: PixelArtViewer(grid: cap.pixelArtGrid!, size: 176)),
            ],
            if (cap.contentType == 'audio') ...[
              const SizedBox(height: 12),
              AudioNotePlayer(
                durationSec: cap.audioDurationSec ?? 15,
                waveform: cap.audioWaveform ?? const [],
              ),
            ],
            if (cap.noteText != null && cap.noteText!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  cap.noteText!,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
