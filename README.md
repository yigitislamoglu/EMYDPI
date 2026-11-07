# EMYDPI

**Türkiye'de Discord'a tek tıkla erişim.** Sadece Discord trafiğini etkiler; diğer sitelere, DNS ayarlarına veya internet hızına dokunmaz.

- Harici `.exe`, `.dll` veya sürücü **yok**. Yalnızca Windows'ta zaten bulunan PowerShell kullanılır, tüm kod açık ve okunabilir.
- VPN değildir; trafiğin başka bir sunucuya gitmez, doğrudan Discord'a bağlanırsın.
- Discord'a DLL enjekte etmez, Discord dosyalarına dokunmaz.
- Kurulduktan sonra bilgisayar her açıldığında arka planda görünmez şekilde kendiliğinden çalışır.

> Windows 10 / 11 için. Discord masaüstü uygulaması ve tarayıcıdan Discord ile çalışır.

---

## Kurulum

1. Sağ üstteki **Code → Download ZIP** ile indir ve ZIP'i bir klasöre çıkar
   (örneğin `Belgeler\EMYDPI`). Klasörü sonradan taşıma; taşırsan kurulumu tekrar yap.
2. `EMYDPI.bat` dosyasına çift tıkla, yönetici iznine **Evet** de.
3. Menüden **`[1] Kur / Onar`** seç.

Hepsi bu. Discord kendiliğinden yeniden açılır ve bağlanır.

### Antivirüs uyarısı (Kaspersky vb.)

Kurulum, Windows'un `hosts` dosyasına birkaç satır ekler. Kaspersky gibi bazı antivirüsler bu dosyayı korur ve
şu hatayı görürsün: **"hosts dosyasına yazma ENGELLENDİ"**. Çözümü:

1. Antivirüsü birkaç dakikalığına **duraklat**.
2. `[1] Kur / Onar`'ı tekrar çalıştır.
3. Antivirüsü **geri aç**.

Bu sadece kurulum ve kaldırma sırasında gerekir; günlük kullanımda gerekmez.

---

## Menü

| Seçenek | Ne yapar |
|---|---|
| `[1] Kur / Onar` | hosts kayıtlarını ekler, proxy'yi başlatır, açılışta otomatik çalışmayı ayarlar |
| `[2] Tamamen kaldır` | Her şeyi geri alır: proxy, otomatik başlatma, hosts kayıtları |
| `[3] Proxy'yi başlat` | Proxy'yi (yeniden) başlatır, Discord'u yeniden açar |
| `[4] Proxy'yi durdur` | Proxy'yi durdurur (kurulum kalır) |
| `[5] Log göster` | Son bağlantı kayıtlarını gösterir |
| `[6] Yedek mod ile kur` | `[1]` işe yaramazsa farklı bir atlatma yöntemiyle kurar |

---

## Nasıl çalışıyor?

Türkiye'deki Discord engeli iki katmanlı:

1. **DNS engeli:** Operatörün DNS sunucusu Discord için yanlış adres döndürür.
2. **DPI / SNI engeli:** HTTPS bağlantısı başlarken tarayıcı, gitmek istediği sitenin adını (SNI) şifrelenmemiş olarak
   gönderir. Operatör bu paketi okur, içinde `discord.com` görürse bağlantıyı keser. Bu yüzden sadece DNS'i
   değiştirmek **yetmez**.

EMYDPI ikisini de şöyle aşar:

```
Discord ──► hosts (discord.com = 127.0.0.1) ──► EMYDPI proxy (127.0.0.1:443)
                                                    │
                     ┌──────────────────────────────┤
                     │ 1. SNI'yi okur (discord.com)  │
                     │ 2. Gerçek IP'yi şifreli DNS   │
                     │    (DoH: 1.1.1.1 / 8.8.8.8)   │
                     │    ile bulur                  │
                     │ 3. TLS ClientHello'yu SNI'nin │
                     │    ortasından iki TLS kaydına │
                     │    böler, ayrı paketlerle     │
                     │    gönderir                   │
                     └──────────────┬───────────────┘
                                    ▼
                               Discord sunucusu
```

DPI sistemi parçalanmış paketlerde alan adının tamamını göremediği için bağlantıyı kesmez. Şifreli trafik
**çözülmez veya değiştirilmez**; proxy sadece ilk paketi böler, gerisini olduğu gibi aktarır. Bu yüzden sertifika
kurulumu da gerekmez.

Sadece [`emydpi.ps1`](emydpi.ps1) içindeki listede bulunan Discord alan adları yönlendirilir; diğer tüm trafik
normal yolundan gider.

### Dosyalar

| Dosya | Görev |
|---|---|
| [`EMYDPI.bat`](EMYDPI.bat) | Menü, yönetici izni ister |
| [`emydpi.ps1`](emydpi.ps1) | Kurulum/kaldırma, hosts ve zamanlanmış görev yönetimi |
| [`emydpi-proxy.cs`](emydpi-proxy.cs) | Proxy'nin kendisi (C#, çalışırken PowerShell tarafından derlenir) |
| [`emydpi-proxy.ps1`](emydpi-proxy.ps1) | Proxy'yi derleyip başlatır |

### Sisteme yapılan değişiklikler

- `C:\Windows\System32\drivers\etc\hosts` dosyasına `# >>> EMYDPI` ile başlayan bir blok eklenir.
  İlk değişiklikten önce yedeği `hosts.emydpi.bak` olarak alınır.
- Görev Zamanlayıcı'ya **EMYDPI** adlı, oturum açılışında çalışan bir görev eklenir (yönetici yetkisiyle değil,
  normal kullanıcı olarak çalışır).

`[2] Tamamen kaldır` bunların hepsini geri alır.

---

## Sorun giderme

**Discord "Checking for updates…" ekranında kalıyor**
→ `[5] Log göster`'e bak. Satırlar görünüyorsa proxy çalışıyordur; `[6] Yedek mod ile kur`'u dene.
Hiç satır yoksa `[3] Proxy'yi başlat`'ı dene.

**"443 portunu başka bir program kullanıyor"**
→ Bilgisayarında 443 portunu dinleyen bir program var (yerel web sunucusu, IIS, XAMPP, Skype'ın eski sürümleri vb.).
O programı kapatıp `[3]`'ü çalıştır.

**Discord'a erişim tamamen gitti**
→ Proxy kapalıyken hosts kayıtları duruyorsa Discord bağlanamaz. `[3]` ile başlat ya da `[2]` ile tamamen kaldır.

**Sesli sohbet çalışmıyor**
→ Ses sunucuları sürekli değişen adlar kullandığı için proxy'den geçmez. Bu yazıldığı tarihte sesli sohbet engelli
değildi; ileride engellenirse lütfen bir *Issue* aç.

**PowerShell betikleri çalışmıyor / şirket bilgisayarı**
→ Grup ilkesiyle PowerShell kısıtlanmış bilgisayarlarda çalışmayabilir.

---

## Sorumluluk reddi

Bu proje eğitim amaçlıdır ve kişisel kullanım içindir. Kullanımından doğabilecek her türlü sorumluluk kullanıcıya
aittir. Proje Discord Inc. ile hiçbir şekilde bağlantılı değildir.

## Lisans

[MIT](LICENSE): Dilediğin gibi kullanabilir, değiştirebilir, dağıtabilirsin.

Katkılar memnuniyetle karşılanır. Hata bildirmek veya öneride bulunmak için *Issue* aç.
