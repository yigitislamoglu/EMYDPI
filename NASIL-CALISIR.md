# EMYDPI nasıl çalışır?

Bu doküman EMYDPI'nin arka planda tam olarak ne yaptığını adım adım anlatır. Kısa özet için
[README](README.md)'ye bakabilirsin.

- [1. Engel nasıl uygulanıyor?](#1-engel-nasıl-uygulanıyor)
- [2. EMYDPI engeli nasıl aşıyor?](#2-emydpi-engeli-nasıl-aşıyor)
- [3. Bir bağlantının yolculuğu](#3-bir-bağlantının-yolculuğu)
- [4. Kurulumda ne oluyor?](#4-kurulumda-ne-oluyor)
- [5. Bilgisayar açıldığında ne oluyor?](#5-bilgisayar-açıldığında-ne-oluyor)
- [6. Performans: bilgisayarı yorar mı?](#6-performans-bilgisayarı-yorar-mı)
- [7. Güvenlik: ne yapar, ne yapmaz?](#7-güvenlik-ne-yapar-ne-yapmaz)

---

## 1. Engel nasıl uygulanıyor?

Bir uygulama HTTPS ile bir sunucuya bağlanırken önce bir **TLS el sıkışması** yapılır. Bu el sıkışmanın ilk
paketi olan **ClientHello**, bağlanılmak istenen sitenin adını **SNI** (Server Name Indication) alanında
**şifrelenmemiş** olarak taşır:

```
TLS ClientHello
 ├─ Sürüm, rastgele sayı, şifreleme listesi ...
 └─ Uzantılar
     └─ server_name (SNI): "discord.com"   ← açık metin
```

Operatörün **DPI** (Derin Paket İnceleme) cihazı bu paketi okur. SNI alanında yasaklı bir ad görürse
(`discord.com`, `roblox.com` ...) bağlantıyı düşürür. Uygulama sonsuza kadar yanıt bekler.

Bunu EMYDPI geliştirilirken yaptığımız testlerle doğruladık:

| Test | Sonuç |
|---|---|
| Discord IP'sine `discord.com` adıyla bağlan | ❌ zaman aşımı |
| **Aynı IP'ye** başka bir adla bağlan | ✅ bağlanıyor |
| Başka bir IP'ye `discord.com` adıyla bağlan | ❌ zaman aşımı |

Yani engel **IP'ye göre değil, paketteki ada göre** uygulanıyor. Discord'da buna ek olarak operatör DNS'i yanlış
adres döndürüyor; Roblox'ta DNS doğru, sadece SNI engeli var.

## 2. EMYDPI engeli nasıl aşıyor?

DPI cihazları saniyede milyonlarca paketi incelemek zorunda oldukları için her bağlantının tamamını yeniden
birleştirip çözümleyemezler; genelde ilk paketi hızlıca tarayıp karar verirler. EMYDPI bundan faydalanır.

ClientHello'yu **SNI adının tam ortasından ikiye böler** ve iki ayrı **TLS kaydı** olarak, iki ayrı TCP paketiyle
gönderir:

```
Normal:     [ TLS kaydı: ...server_name="discord.com"... ]          → DPI "discord.com" görür → keser

EMYDPI:     [ TLS kaydı 1: ...server_name="d ]                      → DPI: tam ad yok
            [ TLS kaydı 2: iscord.com"...    ]                      → DPI: tam ad yok → geçirir
```

TLS standardı (RFC 8446) bir el sıkışma mesajının birden fazla kayda bölünmesine izin verir. Bu yüzden Discord ve
Roblox sunucuları iki parçayı sorunsuz birleştirir ve bağlantı normal şekilde kurulur. DPI cihazı ise iki parçanın
hiçbirinde tam adı göremez.

Bu yöntem testlerde **~250 ms**'de bağlantı kurdu. Bu, normal bir bağlantıyla aynı süre. Daha yavaş ama daha
saldırgan bir alternatif olan **yedek mod** (`[6]`), paketi 2 baytlık parçalara böler. Operatör bir gün
yöntemini değiştirirse bu mod kullanılabilir.

### Neden hosts + yerel proxy?

Paketi bölebilmek için bağlantının bir şekilde bizim elimizden geçmesi gerekiyor. Bunun iki yolu var:

| Yöntem | Kullanan | Dezavantajı |
|---|---|---|
| Ağ sürücüsü (WinDivert) ile tüm trafiği yakalamak | GoodbyeDPI, zapret | Sürücü kurulur, sistemin **tüm** trafiği incelenir |
| Uygulamaya DLL enjekte edip proxy'ye zorlamak | DPIscord | Uygulama dosyalarına müdahale edilir, sadece tek uygulama |
| **hosts ile sadece hedef adları yerel proxy'ye yönlendirmek** | **EMYDPI** | 443 portu boş olmalı |

EMYDPI üçüncü yolu seçer: Windows'un kendi `hosts` dosyası, **sadece** listedeki alan adlarını `127.0.0.1`'e
(bilgisayarın kendisine) yönlendirir. Böylece Discord, Roblox, tarayıcı ve güncelleyiciler gibi o adlara giden
**her program** otomatik olarak proxy'den geçer, başka hiçbir trafik geçmez.

## 3. Bir bağlantının yolculuğu

Discord açılıp `gateway.discord.gg` adresine bağlanmak istediğinde:

```
1. Discord       "gateway.discord.gg nerede?"
2. Windows       hosts dosyasına bakar → 127.0.0.1
3. Discord       127.0.0.1:443'e bağlanır, ClientHello gönderir
4. EMYDPI proxy  ClientHello'yu okur, SNI = "gateway.discord.gg"
5. EMYDPI proxy  Gerçek IP'yi sorar → https://1.1.1.1/dns-query (şifreli DNS)
                 → 162.159.130.234  (10 dakika önbellekte tutulur)
6. EMYDPI proxy  162.159.130.234:443'e bağlanır
7. EMYDPI proxy  ClientHello'yu ikiye bölüp gönderir  ← DPI'nin atlatıldığı an
8. Sonrası       Proxy iki taraf arasında baytları olduğu gibi aktarır.
                 Şifreli trafiği çözemez, okumaz, değiştirmez.
```

Proxy logunda (`[5] Log göster`) bu şöyle görünür:

```
14:32:31 EMYDPI proxy calisiyor: 127.0.0.1:443 mod=tlsrec
14:32:34 updates.discord.com -> 162.159.136.232
14:32:35 gateway.discord.gg -> 162.159.130.234
14:32:37 cdn.discordapp.com -> 162.159.135.233
```

> **Neden sertifika hatası olmuyor?** Proxy TLS'i sonlandırmaz, yani araya girip kendi sertifikasını sunmaz.
> Şifreleme doğrudan Discord/Roblox sunucusu ile senin uygulaman arasında kurulur, proxy sadece "kablo" görevi
> görür. Bu yüzden sertifika kurmaya gerek yoktur ve proxy trafiğin içeriğini göremez.

## 4. Kurulumda ne oluyor?

`[1] Kur / Onar` sırasıyla şunları yapar:

1. **hosts dosyası:** İlk değişiklikten önce yedek alınır (`hosts.emydpi.bak`). Ardından şu blok eklenir:
   ```
   # >>> EMYDPI BASLANGIC (otomatik - elle duzenlemeyin)
   # Servisler: Discord,Roblox
   127.0.0.1	discord.com
   127.0.0.1	gateway.discord.gg
   ...
   # <<< EMYDPI BITIS
   ```
   Dosyanın geri kalanına dokunulmaz. Blok zaten doğruysa dosya hiç yazılmaz.
2. **Zamanlanmış görev:** Görev Zamanlayıcı'ya `EMYDPI` adlı bir görev eklenir. Bu görev oturum açılışında
   çalışır, **yönetici yetkisi olmadan** normal kullanıcı olarak ve **pencere açmadan** (`conhost --headless`)
   başlar. Çökerse 1 dakika sonra kendini yeniden başlatır (en fazla 3 kez).
3. **Proxy başlatılır,** DNS önbelleği temizlenir, Discord yeniden açılır.

Yönetici izni sadece 1. ve 2. adımlar için (sistem dosyası ve görev kaydı) istenir. Proxy'nin kendisi yönetici
olarak **çalışmaz**.

`[2] Tamamen kaldır` bunların hepsini geri alır: görev silinir, proxy durdurulur, hosts bloğu kaldırılır.

## 5. Bilgisayar açıldığında ne oluyor?

1. Oturum açarsın.
2. Görev Zamanlayıcı `EMYDPI` görevini başlatır.
3. `emydpi-proxy.ps1`, `emydpi-proxy.cs` dosyasını .NET derleyicisiyle belleğe derler (~1-2 saniye, diske exe
   yazılmaz) ve proxy'yi başlatır.
4. Proxy 127.0.0.1:443'te bekler. Bağlantı gelmedikçe **hiç CPU kullanmaz**.

Ekranda hiçbir pencere veya simge görünmez. Çalıştığını görmek istersen `EMYDPI.bat` durum ekranına ya da
Görev Yöneticisi → Ayrıntılar'daki `powershell.exe`'ye bakabilirsin.

## 6. Performans: bilgisayarı yorar mı?

**Hayır.** Aşağıdaki değerler 28 çekirdekli bir Windows 11 bilgisayarda gerçek ölçümlerdir:

| Durum | CPU | RAM |
|---|---|---|
| Boşta (bağlantı beklerken) | **%0** | ~7 MB fiziksel RAM |
| 1 saat normal Discord kullanımı | toplam **2,7 saniye** CPU (ortalama %0,0025) | ~7 MB fiziksel RAM |
| 100 eşzamanlı bağlantı | 0,5 saniye CPU, hepsi 2,8 saniyede başarılı | ~85 MB |
| 102 MB dosya indirme, tam hız | tüm işlemcinin **%0,28**'i | ~85 MB |

| Hız testi (102 MB Discord kurulum dosyası) | Hız |
|---|---|
| Doğrudan | 8,0 MB/sn |
| EMYDPI proxy üzerinden | 9,7 MB/sn |

Yani proxy hızı düşürmüyor; sınır internet hattının kendisi.

**Neden bu kadar hafif?**

- Proxy sadece bağlantının **ilk paketini** işler (birkaç yüz bayt). Sonrasında baytları hiçbir işlem yapmadan bir
  taraftan diğerine kopyalar.
- Şifreleme/şifre çözme **yapmaz**. CPU'yu en çok yoran şey budur ve EMYDPI'de yoktur.
- Bağlantı yokken iş parçacıkları uyur, sürekli çalışan bir döngü yoktur.
- Görüntülü sohbet, oyun içi ses ve Roblox oyun trafiği (UDP) proxy'den hiç geçmez.
- Windows boşta duran programın belleğini zamanla serbest bırakır. Görev Yöneticisi'nde "ayrılmış" bellek ~70 MB
  görünse de bunun büyük kısmı PowerShell/.NET çalışma ortamıdır ve fiziksel RAM'de yer kaplamaz.

**Ping'i etkiler mi?** Hayır. Proxy aynı bilgisayarda çalışır (127.0.0.1); araya eklenen gecikme mikrosaniye
düzeyindedir. VPN'den farklı olarak trafik başka bir ülkedeki sunucuya gitmez.

## 7. Güvenlik: ne yapar, ne yapmaz?

**Yapar:**

- `hosts` dosyasına sadece listedeki alan adları için `127.0.0.1` satırları ekler.
- Gerçek IP adreslerini öğrenmek için Cloudflare (`1.1.1.1`, `1.0.0.1`) ve Google (`8.8.8.8`) şifreli DNS
  sunucularına sorgu gönderir. Sorguda sadece alan adı bulunur (ör. `discord.com`).
- Kendi klasörüne `emydpi.log` yazar (en fazla 512 KB, sadece alan adı ve IP; içerik yok).

**Yapmaz:**

- ❌ İnternetten dosya indirmez, güncelleme çekmez, başka program çalıştırmaz.
- ❌ Şifreli trafiği çözmez, okumaz, kaydetmez, değiştirmez.
- ❌ Sürücü kurmaz, Discord/Roblox dosyalarına dokunmaz, DLL enjekte etmez.
- ❌ Sistem DNS ayarlarını, ağ bağdaştırıcısını veya güvenlik duvarını değiştirmez.
- ❌ Hiçbir sunucuya veri, istatistik veya telemetri göndermez.
- ❌ Yönetici yetkisiyle sürekli çalışmaz (sadece kurulum/kaldırma anında).

Tüm kaynak kodu dört dosyadır ve birkaç yüz satırdır. İstersen her satırını okuyabilirsin:
[`EMYDPI.bat`](EMYDPI.bat) · [`emydpi.ps1`](emydpi.ps1) · [`emydpi-proxy.ps1`](emydpi-proxy.ps1) ·
[`emydpi-proxy.cs`](emydpi-proxy.cs)

VirusTotal sonuçları ve dosya özetleri (SHA256) için [README → Güvenlik](README.md#guvenlik)'e bak.
