import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

int _cameraViewCounter = 0;

Widget buildPlatformCameraPreview({
  required VoidCallback onReady,
  required ValueChanged<String> onError,
  void Function(String Function() captureFn)? onRegisterCapture,
}) {
  return _WebArVideoWidget(
    onReady: onReady,
    onError: onError,
    onRegisterCapture: onRegisterCapture,
  );
}

class _WebArVideoWidget extends StatefulWidget {
  final VoidCallback onReady;
  final ValueChanged<String> onError;
  final void Function(String Function() captureFn)? onRegisterCapture;

  const _WebArVideoWidget({
    required this.onReady,
    required this.onError,
    this.onRegisterCapture,
  });

  @override
  State<_WebArVideoWidget> createState() => _WebArVideoWidgetState();
}

class _WebArVideoWidgetState extends State<_WebArVideoWidget> {
  late final String _viewType;
  late final web.HTMLVideoElement _video;
  web.MediaStream? _stream;

  @override
  void initState() {
    super.initState();
    _viewType = 'kapsul-ar-video-${_cameraViewCounter++}';

    _video = (web.document.createElement('video') as web.HTMLVideoElement)
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _video);
    widget.onRegisterCapture?.call(_captureFrameSignature);
    _startCamera(_video);
  }

  String _captureFrameSignature() {
    try {
      if (_video.videoWidth <= 0 || _video.videoHeight <= 0) return '';
      final canvas = (web.document.createElement('canvas') as web.HTMLCanvasElement)
        ..width = 4
        ..height = 4;
      final ctx = canvas.context2D;
      ctx.drawImage(_video, 0, 0, 4, 4);
      final data = ctx.getImageData(0, 0, 4, 4).data.toDart;
      final buf = StringBuffer();
      for (int i = 0; i < 16 && (i * 4 + 2) < data.length; i++) {
        final r = data[i * 4];
        final g = data[i * 4 + 1];
        final b = data[i * 4 + 2];
        final lum = ((0.299 * r + 0.587 * g + 0.114 * b) / 16).round().clamp(0, 15);
        buf.write(lum.toRadixString(16));
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  Future<void> _startCamera(web.HTMLVideoElement video) async {
    try {
      final constraints = web.MediaStreamConstraints(
        video: {'facingMode': 'environment'}.jsify()!,
        audio: false.toJS,
      );
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      _stream = stream;
      video.srcObject = stream;
      await video.play().toDart;
      if (mounted) widget.onReady();
    } catch (_) {
      if (mounted) {
        widget.onError('Kamera erişimi yok veya reddedildi; AR uzamsal görünüm aktif.');
      }
    }
  }

  @override
  void dispose() {
    if (_stream != null) {
      final tracks = _stream!.getTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
