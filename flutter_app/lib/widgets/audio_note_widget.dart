import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class AudioNotePlayer extends StatefulWidget {
  final int durationSec;
  final List<double> waveform;

  const AudioNotePlayer({
    super.key,
    required this.durationSec,
    required this.waveform,
  });

  @override
  State<AudioNotePlayer> createState() => _AudioNotePlayerState();
}

class _AudioNotePlayerState extends State<AudioNotePlayer> {
  bool _playing = false;
  double _progress = 0;
  Timer? _timer;

  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }

    setState(() {
      _playing = true;
      if (_progress >= 1.0) _progress = 0;
    });

    final totalMs = max(widget.durationSec, 3) * 1000;
    const stepMs = 100;
    _timer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      if (!mounted) return;
      setState(() {
        _progress += stepMs / totalMs;
        if (_progress >= 1.0) {
          _progress = 1.0;
          _playing = false;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.waveform.isNotEmpty
        ? widget.waveform
        : const [0.3, 0.6, 0.85, 0.5, 0.75, 0.9, 0.4, 0.65, 0.55, 0.35];
    final currentSec = (_progress * widget.durationSec).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          IconButton.filled(
            onPressed: _togglePlay,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 36,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(bars.length, (i) {
                  final active = (i / bars.length) <= _progress;
                  final h = (bars[i].clamp(0.15, 1.0)) * 32;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      height: h,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF0D9488)
                            : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${currentSec.toString().padLeft(2, '0')}:${widget.durationSec.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

class AudioNoteRecorder extends StatefulWidget {
  final ValueChanged<(int durationSec, List<double> waveform)> onRecorded;

  const AudioNoteRecorder({super.key, required this.onRecorded});

  @override
  State<AudioNoteRecorder> createState() => _AudioNoteRecorderState();
}

class _AudioNoteRecorderState extends State<AudioNoteRecorder> {
  bool _recording = false;
  int _seconds = 0;
  final List<double> _bars = [];
  Timer? _timer;
  final Random _rng = Random();

  void _toggleRecord() {
    if (_recording) {
      _timer?.cancel();
      setState(() => _recording = false);
      widget.onRecorded((max(_seconds, 1), List<double>.from(_bars)));
      return;
    }

    setState(() {
      _recording = true;
      _seconds = 0;
      _bars.clear();
    });

    _timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      setState(() {
        if (t.tick.isEven) _seconds++;
        _bars.add(0.25 + _rng.nextDouble() * 0.72);
        if (_bars.length > 20) _bars.removeAt(0);
      });
      if (_seconds >= 30) {
        _toggleRecord();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _recording ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _toggleRecord,
                style: FilledButton.styleFrom(
                  backgroundColor: _recording
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF1E3A8A),
                ),
                icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(_recording ? 'Kaydı Durdur' : 'Sesli Anı Kaydet'),
              ),
              const SizedBox(width: 12),
              Text(
                '00:${_seconds.toString().padLeft(2, '0')} / 00:30',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (_bars.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 32,
              child: Row(
                children: _bars
                    .map((v) => Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            height: v * 30,
                            decoration: BoxDecoration(
                              color: _recording
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF0D9488),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
