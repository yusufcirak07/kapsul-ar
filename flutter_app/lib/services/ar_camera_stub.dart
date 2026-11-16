import 'package:flutter/material.dart';

Widget buildPlatformCameraPreview({
  required VoidCallback onReady,
  required ValueChanged<String> onError,
  void Function(String Function() captureFn)? onRegisterCapture,
}) {
  return const SizedBox.shrink();
}
