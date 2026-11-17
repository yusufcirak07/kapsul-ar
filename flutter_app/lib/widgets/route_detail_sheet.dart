import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/capsule_models.dart';
import '../services/api_client.dart';
import '../services/location_sensor_service.dart';

class RouteDetailSheet extends StatefulWidget {
  final WalkingRoute route;
  final ApiClient api;
  final LocationSensorService locationService;
  final String userName;
  final VoidCallback onWalkToStart;
  final ValueChanged<WalkingRoute> onRouteUpdated;

  const RouteDetailSheet({
    super.key,
    required this.route,
    required this.api,
    required this.locationService,
    required this.userName,
    required this.onWalkToStart,
    required this.onRouteUpdated,
  });

  @override
  State<RouteDetailSheet> createState() => _RouteDetailSheetState();
}

class _RouteDetailSheetState extends State<RouteDetailSheet> {
  late WalkingRoute _route;
  final _commentController = TextEditingController();
  int _selectedStars = 5;
  int _selectedMoodBoost = 5;
  bool _submittingRating = false;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _route = widget.route;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    setState(() => _submittingRating = true);
    final updated = await widget.api.rateRoute(
      routeId: _route.id,
      userName: widget.userName,
      stars: _selectedStars,
      comment: _commentController.text.trim(),
      moodBoostScore: _selectedMoodBoost,
    );
    if (!mounted) return;
    setState(() => _submittingRating = false);
    if (updated != null) {
      _commentController.clear();
      setState(() => _route = updated);
      widget.onRouteUpdated(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rota puanınız ve değerlendirmeniz kaydedildi!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _completeRoute() async {
    setState(() => _completing = true);
    final updated = await widget.api.completeRoute(
      routeId: _route.id,
      moodBoostScore: _selectedMoodBoost,
    );
    await widget.locationService.markRouteCompleted(
      routeId: _route.id,
      stepsEarned: _route.estimatedSteps,
      distanceMetersEarned: _route.distanceKm * 1000.0,
      moodBoostScore: _selectedMoodBoost,
    );
    await widget.api.submitWellBeing(
      moodScore: _selectedMoodBoost,
      socialConnectedness: _selectedMoodBoost,
      routeId: _route.id,
    );
    if (!mounted) return;
    setState(() {
      _completing = false;
      if (updated != null) _route = updated;
    });
    if (updated != null) widget.onRouteUpdated(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"${_route.title}" tamamlandı! +${_route.estimatedSteps} adım ve moral kaydınız işlendi.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final completed = widget.locationService.completedRouteIds.contains(_route.id);

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _tagChip(
                  _route.routeCategory,
                  _route.isRawPreset ? p.accentAmber : p.accentSecondary,
                ),
                _tagChip(_route.cityDistrict, p.accentPrimary),
                _tagChip(_route.socialTag, const Color(0xFF0EA5E9)),
                _tagChip(_route.difficulty, p.textSecondary),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _route.title,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              _route.description,
              style: TextStyle(fontSize: 13, color: p.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),

            // İstatistik Barı
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metricCol('${_route.distanceKm.toStringAsFixed(1)} km', 'Mesafe', p),
                  _metricCol('${_route.estimatedMinutes} dk', 'Süre', p),
                  _metricCol('~${_route.estimatedSteps}', 'Adım', p),
                  _metricCol(
                    _route.ratingCount > 0 ? '★ ${_route.averageRating}' : 'Yeni',
                    '${_route.ratingCount} oy',
                    p,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Aksiyon Butonları
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onWalkToStart();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.accentPrimary,
                      side: BorderSide(color: p.accentPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.directions_walk_rounded, size: 18),
                    label: const Text('Başlangıca Yürü'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _completing ? null : _completeRoute,
                    style: FilledButton.styleFrom(
                      backgroundColor: completed ? const Color(0xFF10B981) : p.accentSecondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Icon(completed ? Icons.verified_rounded : Icons.flag_rounded, size: 18),
                    label: Text(completed ? 'Tamamlandı' : 'Rotayı Tamamla'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Duraklar
            Text(
              'Rota Durakları (${_route.waypoints.length})',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: p.textPrimary),
            ),
            const SizedBox(height: 8),
            ..._route.waypoints.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.accentPrimary,
                          shape: BoxShape.circle,
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              w.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: p.textPrimary,
                              ),
                            ),
                            if (w.hint.isNotEmpty)
                              Text(
                                w.hint,
                                style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const Divider(height: 24),

            // Puanlama & Sosyalleşme / İyi Oluş Geri Bildirimi
            Text(
              'Rotayı Puanla & Sosyal Etkiyi Paylaş',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: p.textPrimary),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Rota Puanı:', style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
                const SizedBox(width: 8),
                ...List.generate(5, (idx) {
                  final star = idx + 1;
                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => setState(() => _selectedStars = star),
                    icon: Icon(
                      star <= _selectedStars ? Icons.star_rounded : Icons.star_border_rounded,
                      color: p.accentAmber,
                      size: 26,
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Yürüyüş sonrası moral & sosyalleşme isteği:',
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ),
                Text(
                  '$_selectedMoodBoost / 5',
                  style: TextStyle(fontWeight: FontWeight.w800, color: p.accentSecondary),
                ),
              ],
            ),
            Slider(
              value: _selectedMoodBoost.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_selectedMoodBoost / 5',
              onChanged: (v) => setState(() => _selectedMoodBoost = v.round()),
            ),
            TextField(
              controller: _commentController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Kısa yorum (Örn: Küçük ilçede yalnızlığı kıran harika akşam yürüyüşü...)',
                filled: true,
                fillColor: p.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: p.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submittingRating ? null : _submitRating,
                style: FilledButton.styleFrom(
                  backgroundColor: p.accentPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.rate_review_rounded, size: 18),
                label: Text(_submittingRating ? 'Gönderiliyor...' : 'Puanı ve Yorumu Gönder'),
              ),
            ),

            if (_route.ratings.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Topluluk Değerlendirmeleri (${_route.ratings.length})',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.textPrimary),
              ),
              const SizedBox(height: 8),
              ..._route.ratings.map((r) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              r.userName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: p.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '★ ${r.stars} • Moral ${r.moodBoostScore}/5',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: p.accentAmber,
                              ),
                            ),
                          ],
                        ),
                        if (r.comment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            r.comment,
                            style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _metricCol(String val, String label, AppPalette p) {
    return Column(
      children: [
        Text(val, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: p.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: p.textSecondary)),
      ],
    );
  }
}
