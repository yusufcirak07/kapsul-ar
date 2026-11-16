import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

int _cameraViewCounter = 0;

Widget buildPlatformCameraPreview({
  required VoidCallback onReady,
  required ValueChanged<String> onError,
}) {
  return _WebArVideoWidget(onReady: onReady, onError: onError);
}

class _WebArVideoWidget extends StatefulWidget {
  final VoidCallback onReady;
  final ValueChanged<String> onError;

  const _WebArVideoWidget({required this.onReady, required this.onError});

  @override
  State<_WebArVideoWidget> createState() => _WebArVideoWidgetState();
}

class _WebArVideoWidgetState extends State<_WebArVideoWidget> {
  late final String _viewType;
  web.MediaStream? _stream;

  @override
  void initState() {
    super.initState();
    _viewType = 'kapsul-ar-video-${_cameraViewCounter++}';

    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => video);
    _startCamera(video);
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
