# verimlilik-motoru

Verimlilik ailesinin motoru: 32 uygulamanın gerçek uygulamaları, 33 dilde metinleri ve
merkez görünümü (onaylı oyun merkezi tasarımının lacivert-kehribar tonu).

- Çatı: `studio_core/apps` (AppTool, merkez kabuğu, reklam/satın alma, gizlilik, favoriler).
- Her uygulama kendi ince deposunda (`uyg-*`) yayımlanır; merkez uygulama `merkez-verimlilik`.
- Hepsi çevrimdışı çalışır; veriler yalnızca cihazda (`AppStore`) tutulur. Hesap yok.
- Tek istisna: Çevrimdışı Çeviri, dil paketini (~30 MB, ML Kit) ilk kullanımda kullanıcı
  onayıyla bir kez indirir; sonra internetsiz çevirir. Sesten Yazıya, telefonun konuşma
  hizmetini kullanır ("yalnızca cihazda" ayarı varsayılan açık).
- Kamera/mikrofon/ML olmayan cihazlarda ve web'de uygulama "bu cihazda yok" der, çökmez.
  Web'de: Görselden Metin ve Çeviri bilgi gösterir; Kartvizit elle girişe düşer; Ses
  Kaydedici bilgi gösterir; Hatırlatıcı sistem bildirimi yerine listede kalır.
- Hatırlatıcı `SCHEDULE_EXACT_ALARM` kullanır, izin yoksa kesin olmayan alarma düşer;
  `USE_EXACT_ALARM` istenmez. Pano Geçmişi yalnızca kullanıcının yapıştırdığını saklar.
- Fatura/fiş ve fatura-teklif uygulamaları finans uyarısı taşır; belge resmî e-Fatura
  yerine geçmez. PDF'ler gömülü DejaVu Sans (özgür lisans, `assets/fonts`) ile çizilir.
- Reklam yalnızca uygulamadan çıkarken (en az 3 dk arayla, merkez kabuğu); CSV dışa aktarma
  gibi küçük ekstralar reklamsız/premium kullanıcıya açık, diğerlerine ödüllü reklamla
  bugünlük açılır (`ToolContext.unlockForToday`). Asıl iş hiçbir zaman kilitlenmez.

Metinler `proto/apps/verimlilik/ver_titles*.py` ve `ver_labels*.py` dosyalarından
`proto/apps/verimlilik/mkengine.py` ile üretilir (`lib/src/tx.dart`, `lib/src/registry.dart`).
Saf mantık (`lib/src/logic/`) `test/engine_test.dart` ile sınanır.

## 2. tur ekleri
- **Şifre Kasası** (`uyg-sifre-kasasi`): çevrimdışı; kayıtlar AES-256-GCM ile şifreli, anahtar ana
  şifreden Argon2id (19 MiB, 2 tur) ile türetilir; tuz ve ayarlar zarfta saklanır. İsteğe bağlı
  biyometrik açma: anahtar Keystore/Keychain'de (`flutter_secure_storage`), `local_auth` ile açılır
  (merkezde Android `FlutterFragmentActivity`, iOS `NSFaceIDUsageDescription` gerekir). 5 dk
  hareketsizlikte ve uygulamadan çıkınca kilitlenir; kopyalanan şifre 30 sn sonra panodan silinir.
  Bulut yok; dışa aktarma ayrı şifreyle şifreli `.kasa` dosyasıdır. Ana şifre kurtarılamaz.
- **Hedef ve OKR Takibi** (`uyg-hedef-takibi`): hedefler, ağırlıklı anahtar sonuçlar (sayı/yüzde/
  yapıldı), ilerleme girişleri ve geçmişi, zamana göre durum, çeyrek süzgeci.
- **Proje Zaman Çizelgesi** (`uyg-proje-zaman-cizelgesi`): Gantt, bitiş-başlangıç bağımlılıkları
  (otomatik kaydırma, döngü engeli), kilometre taşları, kritik yol, bugün çizgisi, CSV paylaşımı.
