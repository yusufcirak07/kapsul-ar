import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/capsule_models.dart';

class StoryStrip extends StatelessWidget {
  final List<TimeCapsule> capsules;
  final List<NearbyMediaItem> popularPlaces;
  final Set<String> unlockedIds;
  final VoidCallback onAddTap;
  final ValueChanged<TimeCapsule> onCapsuleTap;
  final ValueChanged<NearbyMediaItem> onPlaceTap;

  const StoryStrip({
    super.key,
    required this.capsules,
    required this.popularPlaces,
    required this.unlockedIds,
    required this.onAddTap,
    required this.onCapsuleTap,
    required this.onPlaceTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final totalCount = 1 + capsules.length + popularPlaces.length;

    return SizedBox(
      height: 92,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: totalCount,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, idx) {
          if (idx == 0) {
            return _StoryItem(
              label: 'Paylaş',
              isAdd: true,
              ringColors: [p.accentPrimary, p.accentSecondary],
              imageUrl: null,
              onTap: onAddTap,
            );
          }

          final capIdx = idx - 1;
          if (capIdx < capsules.length) {
            final cap = capsules[capIdx];
            final opened = unlockedIds.contains(cap.id);
            return _StoryItem(
              label: cap.locationName.split(' ').first,
              imageUrl: cap.imageUrl,
              ringColors: opened
                  ? [p.border, p.border]
                  : [p.accentPrimary, p.accentSecondary, p.accentAmber],
              badgeIcon: cap.inArRange ? Icons.view_in_ar_rounded : null,
              onTap: () => onCapsuleTap(cap),
            );
          }

          final poi = popularPlaces[capIdx - capsules.length];
          return _StoryItem(
            label: poi.title.split(' ').first,
            imageUrl: poi.imageUrl,
            ringColors: [p.accentAmber, const Color(0xFFFB7185)],
            badgeIcon: Icons.star_rounded,
            onTap: () => onPlaceTap(poi),
          );
        },
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final List<Color> ringColors;
  final bool isAdd;
  final IconData? badgeIcon;
  final VoidCallback onTap;

  const _StoryItem({
    required this.label,
    required this.imageUrl,
    required this.ringColors,
    this.isAdd = false,
    this.badgeIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: ringColors,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: p.surface,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: isAdd
                          ? Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    p.accentPrimary.withValues(alpha: 0.15),
                                    p.accentSecondary.withValues(alpha: 0.15),
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                color: p.accentPrimary,
                                size: 28,
                              ),
                            )
                          : (imageUrl != null && imageUrl!.isNotEmpty
                              ? Image.network(
                                  imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.place_rounded,
                                    color: p.accentPrimary,
                                  ),
                                )
                              : Icon(Icons.hourglass_bottom_rounded, color: p.accentPrimary)),
                    ),
                  ),
                ),
                if (badgeIcon != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: p.accentAmber,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.surface, width: 2),
                      ),
                      child: Icon(badgeIcon, size: 11, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
