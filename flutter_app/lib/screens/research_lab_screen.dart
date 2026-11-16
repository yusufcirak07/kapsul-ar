import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/capsule_models.dart';
import '../services/api_client.dart';
import '../services/location_sensor_service.dart';

class ResearchLabScreen extends StatefulWidget {
  final ApiClient api;
  final LocationSensorService locationService;

  const ResearchLabScreen({
    super.key,
    required this.api,
    required this.locationService,
  });

  @override
  State<ResearchLabScreen> createState() => _ResearchLabScreenState();
}

class _ResearchLabScreenState extends State<ResearchLabScreen> {
  ExperimentSummary? _summary;
  SpatialBenchmarkData? _benchmark;
  AntiSpoofingReport? _antiSpoofResult;
  bool _runningBench = false;
  bool _runningAntiSpoof = false;

  late final TextEditingController _apiController;

  // 10-item SUS answers (1..5), default positive baseline
  final List<int> _susAnswers = [5, 2, 5, 1, 4, 2, 5, 1, 5, 2];
  double _tamUsefulness = 4.5;
  double _tamEaseOfUse = 4.5;
  double? _lastSusScore;

  static const List<String> _susItems = [
    '1. Bu sistemi sık sık kullanmak isterim.',
    '2. Sistemi gereksiz yere karmaşık buldum.',
    '3. Sistemin kullanımının kolay olduğunu düşündüm.',
    '4. Teknik destek olmadan kullanamayacağımı hissettim.',
    '5. Sistemdeki işlevlerin iyi entegre edildiğini gördüm.',
    '6. Sistemde çok fazla tutarsızlık olduğunu düşündüm.',
    '7. Çoğu insanın bu sistemi çok çabuk öğreneceğini tahmin ediyorum.',
    '8. Sistemin kullanımını oldukça hantal buldum.',
    '9. Sistemi kullanırken kendimi çok güvende hissettim.',
    '10. Sistemi kullanmadan önce çok şey öğrenmem gerekti.',
  ];

  @override
  void initState() {
    super.initState();
    _apiController = TextEditingController(text: widget.api.baseUrl);
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final s = await widget.api.fetchExperimentSummary();
    if (mounted && s != null) setState(() => _summary = s);
  }

  Future<void> _runSpatialBenchmark() async {
    setState(() => _runningBench = true);
    final res = await widget.api.runSpatialBenchmark(count: 10000, radius: 5.0, iterations: 80);
    if (!mounted) return;
    setState(() {
      _benchmark = res;
      _runningBench = false;
    });
  }

  Future<void> _testAntiSpoof({required bool simulateAttack}) async {
    setState(() => _runningAntiSpoof = true);
    final now = DateTime.now().millisecondsSinceEpoch;

    final window = simulateAttack
        ? [
            TelemetrySample(
              latitude: 41.0121,
              longitude: 28.9637,
              accuracyMeters: 0,
              isMocked: true,
              timestampMs: now - 4000,
              accelX: 0,
              accelY: 0,
              accelZ: 9.81,
            ),
            TelemetrySample(
              latitude: 41.0170, // ~545 m jump in 2 seconds!
              longitude: 28.9690,
              accuracyMeters: 0,
              isMocked: true,
              timestampMs: now - 2000,
              accelX: 0,
              accelY: 0,
              accelZ: 9.81,
            ),
          ]
        : [
            TelemetrySample(
              latitude: 41.01210,
              longitude: 28.96370,
              accuracyMeters: 4.1,
              timestampMs: now - 6000,
              accelX: 0.4,
              accelY: -0.2,
              accelZ: 9.9,
              gyroBeta: 0.12,
            ),
            TelemetrySample(
              latitude: 41.01212,
              longitude: 28.96372,
              accuracyMeters: 3.9,
              timestampMs: now - 3000,
              accelX: -0.5,
              accelY: 0.3,
              accelZ: 10.3,
              gyroBeta: 0.18,
            ),
            TelemetrySample(
              latitude: 41.01215,
              longitude: 28.96374,
              accuracyMeters: 3.6,
              timestampMs: now,
              accelX: 0.6,
              accelY: -0.3,
              accelZ: 9.4,
              gyroBeta: 0.15,
            ),
          ];

    final report = await widget.api.evaluateAntiSpoof(window);
    if (!mounted) return;
    setState(() {
      _antiSpoofResult = report;
      _runningAntiSpoof = false;
    });
    _loadSummary();
  }

  Future<void> _submitSus() async {
    final score = await widget.api.submitSusTam(
      group: 'Deney',
      susAnswers: _susAnswers,
      tamUsefulness: _tamUsefulness,
      tamEaseOfUse: _tamEaseOfUse,
      tamIntention: (_tamUsefulness + _tamEaseOfUse) / 2,
    );
    if (!mounted) return;
    if (score != null) {
      setState(() => _lastSusScore = score);
      _loadSummary();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SUS puanınız kaydedildi: $score / 100')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya ulaşılamadı; puan kaydedilemedi.')),
      );
    }
  }

  @override
  void dispose() {
    _apiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      children: [
        const Text(
          'Araştırma & Performans Laboratuvarı',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Uzamsal sorgu indeksleme, anti-spoofing doğrulama ve SUS/TAM deney metrikleri.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),

        // Deney Özeti Kartları
        if (s != null)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statBox('Kapsül', '${s.totalCapsules}'),
              _statBox('Açılma', '${s.totalUnlocks}'),
              _statBox('Spoof Engel', '%${s.spoofBlockRatePercent}'),
              _statBox('Ort. SUS', '${s.averageSusScore}'),
            ],
          ),

        const SizedBox(height: 16),

        // 1. Uzamsal İndeks Kıyaslaması (GiST vs SP-GiST vs Geohash)
        _sectionCard(
          title: '1. Uzamsal Sorgu Optimizasyonu (5m Yakınlık)',
          subtitle: '10.000 sentetik koordinat üzerinde GiST, SP-GiST ve Geohash kıyaslaması.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: _runningBench ? null : _runSpatialBenchmark,
                icon: _runningBench
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.speed_rounded),
                label: Text(_runningBench ? 'Test Çalışıyor...' : '10.000 Nokta Testini Başlat'),
              ),
              if (_benchmark != null) ...[
                const SizedBox(height: 14),
                ..._benchmark!.results.map((r) {
                  final maxMs = _benchmark!.results
                      .map((x) => x.avgQueryMs)
                      .reduce((a, b) => a > b ? a : b);
                  final ratio = maxMs > 0 ? (r.avgQueryMs / maxMs).clamp(0.05, 1.0) : 0.1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.strategy,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            Text(
                              '${r.avgQueryMs.toStringAsFixed(3)} ms • ${r.avgCandidatesScanned} aday',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation(
                              r.strategy.contains('İndekssiz')
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF0D9488),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Anti-Spoofing Güvenlik Katmanı
        _sectionCard(
          title: '2. Hibrit Anti-Spoofing Doğrulama (30 sn Pencere)',
          subtitle: 'Yaya kinematiği + ivmeölçer/jiroskop füzyonu testi.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _runningAntiSpoof ? null : () => _testAntiSpoof(simulateAttack: false),
                      icon: const Icon(Icons.directions_walk_rounded, size: 18),
                      label: const Text('Normal Yürüyüş'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _runningAntiSpoof ? null : () => _testAntiSpoof(simulateAttack: true),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                      icon: const Icon(Icons.shield_outlined, size: 18),
                      label: const Text('Sahte GPS Atla'),
                    ),
                  ),
                ],
              ),
              if (_antiSpoofResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _antiSpoofResult!.passed
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _antiSpoofResult!.passed
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _antiSpoofResult!.passed
                            ? 'DOĞRULANDI (Güven: %${_antiSpoofResult!.trustScore})'
                            : 'ENGELLENDİ (Güven: %${_antiSpoofResult!.trustScore})',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _antiSpoofResult!.passed
                              ? const Color(0xFF047857)
                              : const Color(0xFFB91C1C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_antiSpoofResult!.reason, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        'Maks Hız: ${_antiSpoofResult!.maxObservedSpeedMps} m/s • '
                        'Kalman Sapması: ${_antiSpoofResult!.kalmanInnovationMeters} m • '
                        'Sensör Füzyonu: ${_antiSpoofResult!.sensorFusionConsistent ? "Evet" : "Hayır"}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                      ),
                      if (_antiSpoofResult!.layers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ..._antiSpoofResult!.layers.map((l) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '${l.passed ? "✓" : "✕"} ${l.name} (%${l.score.toStringAsFixed(0)}): ${l.detail}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. SUS & TAM Değerlendirme Formu
        _sectionCard(
          title: '3. SUS Kullanılabilirlik & TAM Anketi',
          subtitle: 'Hedef: SUS > 75 puan. Yanıtlar API üzerinden kaydedilir.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...List.generate(_susItems.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_susItems[i], style: const TextStyle(fontSize: 12)),
                      Slider(
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: '${_susAnswers[i]}',
                        value: _susAnswers[i].toDouble(),
                        onChanged: (v) => setState(() => _susAnswers[i] = v.round()),
                      ),
                    ],
                  ),
                );
              }),
              Text(
                'TAM Algılanan Fayda: ${_tamUsefulness.toStringAsFixed(1)} / 5',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Slider(
                min: 1,
                max: 5,
                divisions: 8,
                value: _tamUsefulness,
                onChanged: (v) => setState(() => _tamUsefulness = v),
              ),
              Text(
                'TAM Kullanım Kolaylığı: ${_tamEaseOfUse.toStringAsFixed(1)} / 5',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Slider(
                min: 1,
                max: 5,
                divisions: 8,
                value: _tamEaseOfUse,
                onChanged: (v) => setState(() => _tamEaseOfUse = v),
              ),
              Row(
                children: [
                  FilledButton(
                    onPressed: _submitSus,
                    child: const Text('Anketi Gönder'),
                  ),
                  const SizedBox(width: 12),
                  if (_lastSusScore != null)
                    Text(
                      'Son SUS: $_lastSusScore / 100',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF047857)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. API Bağlantı Ayarı
        _sectionCard(
          title: 'Backend API Bağlantısı',
          subtitle: 'ASP.NET Core Uzamsal API adresi',
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _apiController,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  widget.api.baseUrl = _apiController.text.trim();
                  _loadSummary();
                },
                child: const Text('Güncelle'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value) {
    final p = AppPalette.of(context);
    return Container(
      width: 155,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: p.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: p.accentPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: p.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: p.textSecondary)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
