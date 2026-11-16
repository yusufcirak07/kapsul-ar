import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  String _displayName = 'Yusuf';
  String _bio = 'Mekansal Keşifçi • Kampüs Rotası';
  double _defaultRadius = 5.0;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  String get displayName => _displayName;
  String get bio => _bio;
  double get defaultRadius => _defaultRadius;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool('dark_mode') ?? false;
    _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    _displayName = prefs.getString('profile_name') ?? 'Yusuf';
    _bio = prefs.getString('profile_bio') ?? 'Mekansal Keşifçi • Kampüs Rotası';
    _defaultRadius = prefs.getDouble('default_radius') ?? 5.0;
    notifyListeners();
  }

  Future<void> toggleDarkMode(bool value) async {
    _themeMode = value ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
  }

  Future<void> updateProfile({required String name, required String bio}) async {
    _displayName = name.trim().isEmpty ? 'Gezgin' : name.trim();
    _bio = bio.trim().isEmpty ? 'Mekansal Keşifçi' : bio.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', _displayName);
    await prefs.setString('profile_bio', _bio);
  }

  Future<void> updateDefaultRadius(double radius) async {
    _defaultRadius = radius;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('default_radius', radius);
  }
}

/// 60-30-10 Renk Kuralı Paleti
/// - %60 Dominant: Arka plan gradiyeni
/// - %30 Secondary: Kartlar, elips alt bar, çipler
/// - %10 Accent: Belirgin aksiyon butonları ve aktif vurgular
class AppPalette {
  final bool isDark;
  final List<Color> bgGradient;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accentPrimary;
  final Color accentSecondary;
  final Color accentAmber;
  final Color navBackground;

  const AppPalette({
    required this.isDark,
    required this.bgGradient,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.accentAmber,
    required this.navBackground,
  });

  static AppPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const AppPalette(
        isDark: true,
        bgGradient: [Color(0xFF070B14), Color(0xFF0F172A), Color(0xFF172554)],
        surface: Color(0xFF162033),
        surfaceMuted: Color(0xFF1E293B),
        border: Color(0xFF2B3A52),
        textPrimary: Color(0xFFF1F5F9),
        textSecondary: Color(0xFF94A3B8),
        accentPrimary: Color(0xFF6366F1),
        accentSecondary: Color(0xFF14B8A6),
        accentAmber: Color(0xFFFBBF24),
        navBackground: Color(0xEB151F32),
      );
    }
    return const AppPalette(
      isDark: false,
      bgGradient: [Color(0xFFF8FAFC), Color(0xFFEEF2FF), Color(0xFFE0F2FE)],
      surface: Color(0xF5FFFFFF),
      surfaceMuted: Color(0xFFF1F5F9),
      border: Color(0xFFE2E8F0),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF64748B),
      accentPrimary: Color(0xFF4F46E5),
      accentSecondary: Color(0xFF0D9488),
      accentAmber: Color(0xFFF59E0B),
      navBackground: Color(0xF2FFFFFF),
    );
  }
}

class AppGradientBackground extends StatelessWidget {
  final Widget child;

  const AppGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.bgGradient,
        ),
      ),
      child: child,
    );
  }
}
