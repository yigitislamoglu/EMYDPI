# Değişiklik Günlüğü

## [1.4.0] - 2026-11-20

### Yeni
- ⚡ **`oob` yöntemi (yeni varsayılan):** Alan adının ortasına TCP acil verisi (OOB) ile 1 bayt eklenir; sunucu
  baytı atar, DPI alan adını yanlış okur. Test edilen operatörde `tlsrec`, `multi` ve `recfrag` engellenince
  96/96 denemede ~0,25 saniyede bağlandı. Yedek olarak `oob2` da eklendi.
- 🔌 **İnternet gidip gelince otomatik toparlanma:** Sunucuya hiç ulaşılamıyorsa bu internet kesintisi sayılır,
  yöntem değiştirilmez. Kayıtlı IP'ler çalışmazsa taze DNS sorgusuyla hemen tekrar denenir. Wi-Fi/modem
  değişikliği algılanır ve en hızlı yöntem tekrar denenir.
- DNS kayıtları diske yazılır. Süresi dolan kayıt beklemeden kullanılır ve arka planda yenilenir.
- 🔒 Proxy sadece Discord ve Roblox adreslerine aracılık eder. Yerel/özel ağ adresi dönen DNS cevapları reddedilir.

### Düzeltilenler
- **Yavaşlama:** İnternet kesintisi sırasında tüm yöntemler başarısız sayılıyor ve proxy en yavaş yöntem `frag`'a
  geçip öyle kalıyordu. Artık bir yöntem en az iki kez gerçekten engellenmeden değiştirilmez. Daha yavaş bir
  yöntem öğrenildiyse 10 dakikada bir en hızlısı tekrar denenir.
- **Resim / dosya gönderememe:** Discord'un yükleme sunucusu (`storage.googleapis.com`) engelli olmadığı halde
  proxy'den geçiyordu ve kesintilerde yüklemeler düşüyordu. Artık doğrudan gider.
- Bağlantı başına bekleme 16 saniyeden en fazla ~6 saniyeye indi (cevap bekleme 4 → 3 sn, DNS 3 → 2,5 sn).
- Proxy çökerse veya 443 portu geçici olarak meşgulse kendini yeniden başlatır.

## [1.3.0] - 2026-11-07

### Yeni
- 🖱️ **Arayüz:** `EMYDPI.bat`'a çift tıklayınca numaralı menü yerine butonlu, koyu temalı bir pencere açılır.
  Canlı durum kartı (çalışıyor / eksik / kurulu değil), servis seçimi, Kur / Başlat / Durdur / Kaldır butonları,
  gelişmiş ayarlarda yöntem seçimi ve log, işlem çıktısı paneli. Çakışan program ve antivirüs engeli için
  açıklamalı uyarı pencereleri.
- Arayüz Windows'un kendi WPF bileşeniyle yazıldı; yine `.exe`/`.dll` yok.
- Eski yazı menüsü `EMYDPI.bat konsol` ile kullanılmaya devam edebilir.

## [1.2.0] - 2026-11-07

### Yeni
- 🌐 **Otomatik mod (varsayılan):** 4 atlatma yöntemi (`tlsrec`, `multi`, `recfrag`, `frag`). Bir yöntem cevap
  almazsa bağlantı sıradaki yöntemle tekrar denenir; işe yarayan kaydedilir ve sonraki açılışlarda doğrudan
  kullanılır. Farklı operatörlerin farklı DPI cihazlarına uyum için.
- 🧹 **Çakışan program kontrolü:** Kurulum GoodbyeDPI, zapret, DPIscord, SpoofDPI, ByeDPI, GreenTunnel, PowerTunnel
  ve WinDivert sürücülerini tespit eder, uyarır ve onay verilirse durdurur. Durum ekranında da uyarı gösterilir.
- `hosts` içinde başka araçlardan kalmış Discord/Roblox satırları temizlenir.
- Ön kontroller: Windows sürümü, PowerShell kısıtlaması, 443 portu.
- `[6] Yöntem seç`: gelişmiş kullanıcılar için yöntemi elle sabitleme.

### Değişenler
- Şifreli DNS 6 sunucuya çıkarıldı (Cloudflare, Google, AdGuard) ve RFC 8484 standart formatına geçildi.
  3 saniye zaman aşımı; hepsi erişilemezse son bilinen IP kullanılır.
- Sunucunun birden fazla IP'si varsa yeniden denemede farklı IP kullanılır.
- `frag` yöntemi artık sadece alan adı bitene kadar parçalar (eskisinden çok daha hızlı).

## [1.1.0] - 2026-11-07

### Yeni
- 🎮 **Roblox desteği.** Roblox'un site, giriş, API ve oyuna katılma bağlantıları (62 alan adı) artık açılıyor.
  Roblox da Discord gibi SNI tabanlı engellendiği için aynı yöntem kullanılır.
- **`[7] Servis seç`:** Discord + Roblox, sadece Discord veya sadece Roblox.
- Durum ekranında kurulu servisler gösteriliyor.

### Değişenler
- İlk kurulum varsayılan olarak Discord + Roblox kurar. `[1] Kur / Onar` mevcut servis seçimini korur.
- v1.0.0 kurulumları otomatik olarak "Discord" olarak tanınır.
- Servis seçimi değişmedikçe `hosts` dosyasına dokunulmaz (antivirüs duraklatmaya gerek kalmaz).

## [1.0.0] - 2026-11-07

İlk sürüm.

### Özellikler
- Yerel SNI proxy: TLS ClientHello'yu SNI'nin ortasından iki TLS kaydına bölerek DPI'yi atlatır (`tlsrec` modu).
- Yedek mod: ClientHello'yu küçük TCP parçalarına bölerek gönderir (`frag` modu).
- Gerçek IP adresleri için şifreli DNS (DoH): Cloudflare 1.1.1.1 / 1.0.0.1, Google 8.8.8.8.
- Sadece Discord alan adlarını `hosts` ile yönlendirir; diğer trafiğe dokunmaz.
- Oturum açılışında pencere açmadan otomatik başlatma (Görev Zamanlayıcı + `conhost --headless`).
- Tek menülü `.bat`: kur, kaldır, başlat, durdur, log.
- Antivirüs `hosts` dosyasını koruyorsa anlaşılır hata mesajı verir; `hosts` zaten doğruysa dosyaya dokunmaz.

[1.4.0]: https://github.com/yigitislamoglu/EMYDPI/releases/tag/v1.4.0
[1.3.0]: https://github.com/yigitislamoglu/EMYDPI/releases/tag/v1.3.0
[1.2.0]: https://github.com/yigitislamoglu/EMYDPI/releases/tag/v1.2.0
[1.1.0]: https://github.com/yigitislamoglu/EMYDPI/releases/tag/v1.1.0
[1.0.0]: https://github.com/yigitislamoglu/EMYDPI/releases/tag/v1.0.0
