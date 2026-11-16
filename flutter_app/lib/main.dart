import 'package:flutter/material.dart';

import 'config/app_theme.dart';
import 'models/capsule_models.dart';
import 'screens/create_capsule_screen.dart';
import 'screens/discoveries_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/profile_screen.dart';
import 'services/api_client.dart';
import 'services/location_sensor_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KapsulArApp());
}

class KapsulArApp extends StatefulWidget {
  const KapsulArApp({super.key});

  @override
  State<KapsulArApp> createState() => _KapsulArAppState();
}

class _KapsulArAppState extends State<KapsulArApp> {
  final ThemeController _themeController = ThemeController();

  @override
  void initState() {
    super.initState();
    _themeController.initialize();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (_, __) {
        return MaterialApp(
          title: 'KapsülAR',
          debugShowCheckedModeBanner: false,
          themeMode: _themeController.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4F46E5),
              primary: const Color(0xFF4F46E5),
              secondary: const Color(0xFF0D9488),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: Colors.transparent,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFF0F172A),
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              primary: const Color(0xFF6366F1),
              secondary: const Color(0xFF14B8A6),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: Colors.transparent,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFFF1F5F9),
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
          ),
          home: HomeShell(themeController: _themeController),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  final ThemeController themeController;

  const HomeShell({super.key, required this.themeController});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ApiClient _api = ApiClient();
  final LocationSensorService _locationService = LocationSensorService();
  int _tabIndex = 0;
  NearbyMediaItem? _prefilledPlace;

  @override
  void initState() {
    super.initState();
    _locationService.initialize();
  }

  @override
  void dispose() {
    _locationService.dispose();
    super.dispose();
  }

  void _openCreateWithPlace(NearbyMediaItem place) {
    setState(() {
      _prefilledPlace = place;
      _tabIndex = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return AppGradientBackground(
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [p.accentPrimary, p.accentSecondary],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.hourglass_bottom_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'KapsülAR',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
          actions: [
            AnimatedBuilder(
              animation: _locationService,
              builder: (_, __) => Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: p.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_run_rounded, size: 15, color: p.accentSecondary),
                    const SizedBox(width: 5),
                    Text(
                      '${_locationService.stepsToday} adım',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: widget.themeController.isDark ? 'Aydınlık Tema' : 'Karanlık Tema',
              onPressed: () =>
                  widget.themeController.toggleDarkMode(!widget.themeController.isDark),
              icon: Icon(
                widget.themeController.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: p.accentPrimary,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: IndexedStack(
          index: _tabIndex,
          children: [
            ExploreScreen(
              api: _api,
              locationService: _locationService,
              onGoToCreate: () => setState(() => _tabIndex = 1),
              onCreateAtPlace: _openCreateWithPlace,
            ),
            CreateCapsuleScreen(
              api: _api,
              locationService: _locationService,
              themeController: widget.themeController,
              prefilledPlace: _prefilledPlace,
              onCreated: () => setState(() {
                _prefilledPlace = null;
                _tabIndex = 0;
              }),
            ),
            DiscoveriesScreen(api: _api, locationService: _locationService),
            ProfileScreen(
              api: _api,
              locationService: _locationService,
              themeController: widget.themeController,
            ),
          ],
        ),
        // Ekran çerçevesinden ayrılmış, elips formunda modern alt gezinme çubuğu
        bottomNavigationBar: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: p.navBackground,
              borderRadius: BorderRadius.circular(38),
              border: Border.all(color: p.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _EllipticalNavButton(
                  icon: Icons.explore_rounded,
                  label: 'Keşfet',
                  selected: _tabIndex == 0,
                  palette: p,
                  onTap: () => setState(() => _tabIndex = 0),
                ),
                _EllipticalNavButton(
                  icon: Icons.add_box_rounded,
                  label: 'Bırak',
                  selected: _tabIndex == 1,
                  palette: p,
                  onTap: () => setState(() => _tabIndex = 1),
                ),
                _EllipticalNavButton(
                  icon: Icons.bolt_rounded,
                  label: 'Aktivite',
                  selected: _tabIndex == 2,
                  palette: p,
                  onTap: () => setState(() => _tabIndex = 2),
                ),
                _EllipticalNavButton(
                  icon: Icons.person_rounded,
                  label: 'Profil',
                  selected: _tabIndex == 3,
                  palette: p,
                  onTap: () => setState(() => _tabIndex = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EllipticalNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  const _EllipticalNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 16 : 12,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [palette.accentPrimary, palette.accentSecondary],
                )
              : null,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 21,
              color: selected ? Colors.white : palette.textSecondary,
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
