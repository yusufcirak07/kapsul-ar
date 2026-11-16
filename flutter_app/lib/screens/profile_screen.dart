import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/api_client.dart';
import '../services/location_sensor_service.dart';
import 'research_lab_screen.dart';

class ProfileScreen extends StatelessWidget {
  final ApiClient api;
  final LocationSensorService locationService;
  final ThemeController themeController;

  const ProfileScreen({
    super.key,
    required this.api,
    required this.locationService,
    required this.themeController,
  });

  void _openEditProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: themeController.displayName);
    final bioCtrl = TextEditingController(text: themeController.bio);
    final p = AppPalette.of(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: p.surface,
        title: Text('Profili Düzenle', style: TextStyle(color: p.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Görünen Ad'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bioCtrl,
              decoration: const InputDecoration(labelText: 'Hakkında / Rota Notu'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              themeController.updateProfile(
                name: nameCtrl.text,
                bio: bioCtrl.text,
              );
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: p.accentPrimary),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final loc = locationService;
    final initial = themeController.displayName.isNotEmpty
        ? themeController.displayName[0].toUpperCase()
        : 'K';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
      children: [
        // Profil Kartı
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Container(
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [p.accentPrimary, p.accentSecondary, p.accentAmber],
                  ),
                ),
                child: CircleAvatar(
                  backgroundColor: p.surfaceMuted,
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: p.accentPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      themeController.displayName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      themeController.bio,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _miniStat(p, '${loc.stepsToday} adım'),
                        const SizedBox(width: 8),
                        _miniStat(p, '${loc.unlockedIds.length} kapsül'),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _openEditProfileDialog(context),
                style: IconButton.styleFrom(
                  backgroundColor: p.accentPrimary.withValues(alpha: 0.14),
                  foregroundColor: p.accentPrimary,
                ),
                icon: const Icon(Icons.edit_rounded, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Tema & Görünüm Ayarları
        _settingsGroup(
          p: p,
          title: 'Görünüm ve Tema',
          children: [
            SwitchListTile(
              secondary: Icon(
                themeController.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: p.accentPrimary,
              ),
              title: Text(
                'Karanlık Tema (Dark Mode)',
                style: TextStyle(fontWeight: FontWeight.w600, color: p.textPrimary),
              ),
              subtitle: Text(
                'Arka plan gradiyenini ve haritayı gece moduna uyarlar.',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
              value: themeController.isDark,
              activeThumbColor: p.accentPrimary,
              onChanged: themeController.toggleDarkMode,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Konum & Kapsül Tercihleri
        _settingsGroup(
          p: p,
          title: 'Konum ve Kapsül Tercihleri',
          children: [
            SwitchListTile(
              secondary: Icon(Icons.gps_fixed_rounded, color: p.accentSecondary),
              title: Text(
                'Gerçek GPS Modu',
                style: TextStyle(fontWeight: FontWeight.w600, color: p.textPrimary),
              ),
              subtitle: Text(
                loc.isSimulated
                    ? 'Şu an Kampüs Demo Simülasyonu aktif'
                    : 'Cihaz GPS sensörleri aktif',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
              value: !loc.isSimulated,
              activeThumbColor: p.accentSecondary,
              onChanged: (useGps) async {
                if (useGps) {
                  await loc.enableRealGps();
                } else {
                  loc.switchToCampusSimulation();
                }
              },
            ),
            Divider(height: 1, color: p.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Varsayılan Kilit Yarıçapı',
                    style: TextStyle(fontWeight: FontWeight.w600, color: p.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [5.0, 10.0, 15.0].map((r) {
                      final selected = themeController.defaultRadius == r;
                      return ChoiceChip(
                        label: Text(
                          '${r.toInt()} m',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : p.textPrimary,
                          ),
                        ),
                        selected: selected,
                        showCheckmark: false,
                        selectedColor: p.accentPrimary,
                        backgroundColor: p.surfaceMuted,
                        onSelected: (_) => themeController.updateDefaultRadius(r),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Akademik & Teknik Araçlar (Lab)
        _settingsGroup(
          p: p,
          title: 'Araştırma & Sistem Araçları',
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: p.accentPrimary.withValues(alpha: 0.14),
                child: Icon(Icons.science_rounded, color: p.accentPrimary),
              ),
              title: Text(
                'Araştırma Laboratuvarı',
                style: TextStyle(fontWeight: FontWeight.w700, color: p.textPrimary),
              ),
              subtitle: Text(
                'GiST/SP-GiST hız testi, Anti-Spoofing ve SUS/TAM anketi',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: p.textSecondary),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Araştırma Laboratuvarı')),
                      body: AppGradientBackground(
                        child: ResearchLabScreen(
                          api: api,
                          locationService: locationService,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniStat(AppPalette p, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: p.accentPrimary,
        ),
      ),
    );
  }

  Widget _settingsGroup({
    required AppPalette p,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: p.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
