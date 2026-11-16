# KapsülAR — Konum Kilitli Dijital Zaman Kapsülü Sistemi

Web Tabanlı Artırılmış Gerçeklik (WebAR / PWA) ve Hibrit Konum Doğrulama mimarisi kullanılarak mekansal etkileşim ve fiziksel aktivite motivasyonunu artırmak amacıyla geliştirilen **Flutter (PWA + Mobil)** ve **ASP.NET Core (.NET 10) Uzamsal REST API** projesi.

---

## 1. Mimari Bileşenler

| Katman | Teknoloji | Konum |
|---|---|---|
| **İstemci (PWA & Mobil)** | Flutter (Material 3, `flutter_map`, `geolocator`, `sensors_plus`, WebRTC `getUserMedia`) | `flutter_app/` |
| **Sunucu & Uzamsal API** | ASP.NET Core (.NET 10) Minimal API | `backend/` |
| **Veritabanı Şeması & Yük Testi** | PostgreSQL + PostGIS (`GiST`, `SP-GiST`, `Geohash`) & `k6` | `backend/database/` |
| **Görsel Veri Kaynağı** | Wikimedia Commons & Wikipedia Geosearch API (Açık Lisanslı) | `WikimediaMediaService.cs` |

---

## 2. Öne Çıkan Özellikler

1. **Sade ve Anlaşılır 4 Sekmeli Arayüz**
   - **Keşfet:** OpenStreetMap haritası, 15m WebAR tetikleme / 5m kilit halkaları, Wikimedia görselli kapsül kartları ve masaüstü/iç mekan testleri için **Yürüyüş Simülatörü (1.5 m/s)**.
   - **Bırak:** Metin/Şifreli Not, Fotoğraf, **16×16 Piksel Sanat Tuvali**, Sesli Anı oluşturma ve **Wikimedia Commons'tan mekana uygun görsel çekme**.
   - **Aktivite:** Günlük adım, yürünen mesafe (km) ve açılan zaman kapsülleri arşivi.
   - **Lab:**
     - **10.000 Noktalı Canlı Uzamsal İndeks Kıyaslaması:** İndekssiz tarama vs `Geohash` vs `SP-GiST (QuadTree)` vs `GiST (R-Tree/MBR)`.
     - **30 Saniyelik Hibrit Anti-Spoofing Testi:** Normal yürüyüş vs imkansız GPS sıçraması + sensör füzyonu tutarlılığı.
     - **SUS & TAM Değerlendirme Formu:** Anlık SUS puanı hesaplama (hedef > 75).

2. **WebAR Kilit Açma Akışı**
   - Kapsüle 15m yaklaşıldığında kamera (`navigator.mediaDevices.getUserMedia`) ve görsel yer işareti doğrulaması açılır.
   - Sunucu tarafı son 30 saniyelik hız/ivme penceresini doğrular; 5m içine girildiğinde zaman kapsülünü açar.

---

## 3. Çalıştırma Talimatları

### A. Backend API (.NET 10)
```powershell
cd backend
dotnet run
```
Sunucu varsayılan olarak `http://localhost:5088` adresinde çalışır.

### B. Flutter Uygulaması (PWA / Web veya Mobil)
```powershell
cd flutter_app
flutter pub get
flutter run -d chrome
```
> **Not:** Android emülatöründe `ApiClient` otomatik olarak `http://10.0.2.2:5088` adresini kullanır; gerekirse **Lab** sekmesinden API adresi değiştirilebilir.

### C. PostgreSQL + PostGIS ve k6 Yük Testi (Opsiyonel Üretim Ortamı)
- Şema ve indeksler: `backend/database/schema_postgis.sql`
- Yük testi: `k6 run backend/database/benchmark_k6.js`
