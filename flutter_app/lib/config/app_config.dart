import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const String _envApiUrl = String.fromEnvironment('API_URL', defaultValue: '');

  static String get defaultApiBaseUrl {
    if (_envApiUrl.isNotEmpty) return _envApiUrl;
    if (kIsWeb) return 'http://localhost:5088';
    // Android emulators route host loopback via 10.0.2.2
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5088';
    }
    return 'http://localhost:5088';
  }

  // Varsayılan pilot kampüs merkezi: İstanbul Üniversitesi Beyazıt Kampüsü
  static const double defaultLat = 41.0121;
  static const double defaultLon = 28.9637;

  static const List<String> categories = [
    'Tümü',
    'Kültürel Miras',
    'Kampüs Yaşamı',
    'Fiziksel Aktivite',
    'Yerel İşletme',
  ];
}
