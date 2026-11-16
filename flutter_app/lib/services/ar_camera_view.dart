import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'ar_camera_stub.dart'
    if (dart.library.js_interop) 'ar_camera_web.dart';

class ArCameraController {
  String Function()? _captureFrameFn;

  void _attach(String Function() fn) {
    _captureFrameFn = fn;
  }

  /// Captures a 16-hex visual landmark signature from live camera frame if available,
  /// or derives a deterministic spatial environment signature from GPS + heading.
  String captureVisualSignature({
    required double lat,
    required double lon,
    required double headingDeg,
  }) {
    final live = _captureFrameFn?.call() ?? '';
    if (live.length == 16) return live;

    // Spatial fallback when camera hardware is unavailable (e.g., Android Emulator / Desktop)
    final sector = ((headingDeg % 360 + 360) % 360 / 30).floor();
    final seed = '${lat.toStringAsFixed(4)}|${lon.toStringAsFixed(4)}|$sector';
    final digest = sha256.convert(utf8.encode(seed)).toString();
    return digest.substring(0, 16);
  }
}

class ArCameraBackground extends StatefulWidget {
  final String? fallbackImageUrl;
  final ArCameraController? controller;

  const ArCameraBackground({
    super.key,
    this.fallbackImageUrl,
    this.controller,
  });

  @override
  State<ArCameraBackground> createState() => _ArCameraBackgroundState();
}

class _ArCameraBackgroundState extends State<ArCameraBackground> {
  bool _cameraReady = false;
  String? _fallbackReason;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
          child: widget.fallbackImageUrl != null
              ? Opacity(
                  opacity: _cameraReady ? 0.0 : 0.32,
                  child: Image.network(
                    widget.fallbackImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (_fallbackReason == null)
          buildPlatformCameraPreview(
            onReady: () {
              if (mounted) setState(() => _cameraReady = true);
            },
            onError: (msg) {
              if (mounted) setState(() => _fallbackReason = msg);
            },
            onRegisterCapture: (fn) => widget.controller?._attach(fn),
          ),
        IgnorePointer(
          child: CustomPaint(painter: _ArGridPainter()),
        ),
        if (_fallbackReason != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _fallbackReason!,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ArGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
