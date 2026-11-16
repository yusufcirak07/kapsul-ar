import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/capsule_models.dart';

class CapsuleCard extends StatelessWidget {
  final TimeCapsule capsule;
  final bool isUnlocked;
  final VoidCallback onOpenAr;
  final VoidCallback onWalkHere;

  const CapsuleCard({
    super.key,
    required this.capsule,
    required this.isUnlocked,
    required this.onOpenAr,
    required this.onWalkHere,
  });

  Color _categoryColor(AppPalette p) {
    switch (capsule.category) {
      case 'Kültürel Miras':
        return p.accentPrimary;
      case 'Fiziksel Aktivite':
        return p.accentSecondary;
      case 'Yerel İşletme':
        return p.accentAmber;
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  IconData get _typeIcon {
    switch (capsule.contentType) {
      case 'audio':
        return Icons.graphic_eq_rounded;
      case 'pixelArt':
        return Icons.grid_view_rounded;
      case 'photo':
        return Icons.photo_camera_back_rounded;
      default:
        return capsule.isEncrypted ? Icons.lock_rounded : Icons.auto_stories_rounded;
    }
  }

  String _formatDistance(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final catColor = _categoryColor(p);
    final inAr = capsule.inArRange;
    final inUnlock = capsule.inUnlockRange;

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: inUnlock
              ? const Color(0xFF10B981)
              : (inAr ? p.accentSecondary : p.border),
          width: inAr ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.25 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 78,
              height: 78,
              child: capsule.imageUrl != null && capsule.imageUrl!.isNotEmpty
                  ? Image.network(
                      capsule.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholderBox(catColor),
                    )
                  : _placeholderBox(catColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        capsule.category,
                        style: TextStyle(
                          color: catColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(_typeIcon, size: 14, color: p.textSecondary),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        capsule.contentTypeLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: p.textSecondary),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: inUnlock
                            ? const Color(0xFF10B981).withValues(alpha: 0.16)
                            : (inAr
                                ? p.accentSecondary.withValues(alpha: 0.16)
                                : p.surfaceMuted),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _formatDistance(capsule.distanceMeters),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: inUnlock
                              ? const Color(0xFF10B981)
                              : (inAr ? p.accentSecondary : p.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  capsule.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  capsule.locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (isUnlocked)
                      const Row(
                        children: [
                          Icon(Icons.verified_rounded, size: 16, color: Color(0xFF10B981)),
                          SizedBox(width: 4),
                          Text(
                            'Açıldı',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        inUnlock
                            ? '5m kilit alanında'
                            : (inAr ? '15m WebAR menzilinde' : 'Hedefe yürüyün'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: inAr ? p.accentSecondary : p.textSecondary,
                        ),
                      ),
                    const Spacer(),
                    // %10 Accent Renk Kuralı: belirgin CTA butonları
                    if (!inAr)
                      FilledButton.tonalIcon(
                        onPressed: onWalkHere,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accentPrimary.withValues(alpha: 0.14),
                          foregroundColor: p.accentPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(Icons.directions_walk_rounded, size: 15),
                        label: const Text(
                          'Yaklaş',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      FilledButton.icon(
                        onPressed: onOpenAr,
                        style: FilledButton.styleFrom(
                          backgroundColor: inUnlock ? const Color(0xFF10B981) : p.accentPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(Icons.view_in_ar_rounded, size: 15),
                        label: Text(
                          isUnlocked ? 'Görüntüle' : 'AR ile Aç',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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

  Widget _placeholderBox(Color catColor) {
    return Container(
      color: catColor.withValues(alpha: 0.15),
      child: Center(
        child: Icon(_typeIcon, color: catColor, size: 28),
      ),
    );
  }
}
