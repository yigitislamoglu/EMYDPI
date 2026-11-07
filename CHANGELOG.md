# Değişiklik Günlüğü

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

[1.0.0]: https://github.com/yigitislamoglu/EMYDPI/releases/tag/v1.0.0
