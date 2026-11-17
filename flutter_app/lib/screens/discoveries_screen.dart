import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/capsule_models.dart';
import '../services/api_client.dart';
import '../services/location_sensor_service.dart';
import '../widgets/audio_note_widget.dart';
import '../widgets/pixel_art_editor.dart';

class DiscoveriesScreen extends StatefulWidget {
  final ApiClient api;
  final LocationSensorService locationService;

  const DiscoveriesScreen({
    super.key,
    required this.api,
    required this.locationService,
  });

  @override
  State<DiscoveriesScreen> createState() => _DiscoveriesScreenState();
}

class _DiscoveriesScreenState extends State<DiscoveriesScreen> {
  List<TimeCapsule> _capsules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await widget.api.fetchNearbyCapsules(
      lat: widget.locationService.latitude,
      lon: widget.locationService.longitude,
    );
    if (!mounted) return;
    setState(() {
      _capsules = all;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final loc = widget.locationService;
    final unlocked = _capsules.where((c) => loc.unlockedIds.contains(c.id)).toList();
    const dailyGoalSteps = 6000;
    final progress = (loc.stepsToday / dailyGoalSteps).clamp(0.0, 1.0);
    final kmToday = (loc.distanceMetersToday / 1000).toStringAsFixed(2);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.accentPrimary, p.accentSecondary],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: p.accentPrimary.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Günlük Mekansal Keşif Özeti',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${loc.stepsToday} adım',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$kmToday km yürüyüş',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFFBBF24)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hedef: $dailyGoalSteps adım • Açılan kapsül: ${loc.unlockedIds.length} • Rota: ${loc.completedRouteIds.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite_rounded, color: p.accentSecondary, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Yürüyüş Sonrası Moral & Sosyalleşme İsteği',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    if (loc.wellBeingScores.isNotEmpty)
                      Text(
                        'Ort: ${loc.averageWellBeing.toStringAsFixed(1)}/5',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: p.accentSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Hareketsizlik ve umutsuzluk hissini azaltmak için yürüyüş sonrası kendinizi nasıl hissettiğinizi puanlayın:',
                  style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (idx) {
                    final score = idx + 1;
                    final labels = ['Yorgun', 'Durgun', 'Normal', 'Enerjik', 'Sosyal'];
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: idx < 4 ? 6 : 0),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            side: BorderSide(color: p.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            await loc.recordWellBeing(score);
                            await widget.api.submitWellBeing(
                              moodScore: score,
                              socialConnectedness: score,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('İyi oluş kaydınız ($score/5 - ${labels[idx]}) eklendi.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Column(
                            children: [
                              Text(
                                '$score',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: p.accentPrimary,
                                ),
                              ),
                              Text(
                                labels[idx],
                                style: TextStyle(fontSize: 9.5, color: p.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Açtığım Zaman Kapsülleri',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            )
          else if (unlocked.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.border),
              ),
              child: Column(
                children: [
                  Icon(Icons.explore_outlined, size: 40, color: p.textSecondary),
                  const SizedBox(height: 10),
                  Text(
                    'Henüz kapsül açmadınız.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Keşfet sekmesinden bir kapsüle yürüyerek WebAR ile ilk keşfinizi yapın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ],
              ),
            )
          else
            ...unlocked.map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: p.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              c.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            c.contentTypeLabel,
                            style: TextStyle(fontSize: 11, color: p.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.locationName,
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                      if (c.contentType == 'pixelArt' && c.pixelArtGrid != null) ...[
                        const SizedBox(height: 10),
                        Center(child: PixelArtViewer(grid: c.pixelArtGrid!, size: 140)),
                      ],
                      if (c.contentType == 'audio') ...[
                        const SizedBox(height: 10),
                        AudioNotePlayer(
                          durationSec: c.audioDurationSec ?? 15,
                          waveform: c.audioWaveform ?? const [],
                        ),
                      ],
                      if (c.noteText != null && c.noteText!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          c.noteText!,
                          style: TextStyle(fontSize: 13, color: p.textPrimary),
                        ),
                      ],
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
