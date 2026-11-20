// EMYDPI yerel SNI proxy
// hosts dosyasi secilen servislerin alan adlarini 127.0.0.1'e yonlendirir. Bu proxy 127.0.0.1:443'te
// dinler, gelen TLS ClientHello'dan SNI'yi okur, gercek IP'yi sifreli DNS (DoH) ile bulur ve
// ClientHello'yu DPI'nin alan adini okuyamayacagi sekilde bolerek iletir.
// TLS cozulmez; sifreli trafik oldugu gibi aktarilir.
//
// auto modu: her internet saglayicisinin DPI'si farkli davranabilir. Proxy sirayla birkac bolme
// yontemi dener; sunucu cevap verdigi ilk yontemi ogrenir, kaydeder ve sonraki baglantilarda
// dogrudan onu kullanir. Istemciye henuz hicbir sey gonderilmedigi icin yeniden deneme guvenlidir.
//
// Internet kesintisi DPI engeliyle karistirilmaz: sunucuya TCP baglantisi hic kurulamiyorsa sorun
// yontemde degil agdadir; bu durumda yontem degistirilmez. Ag degistiginde (Wi-Fi, modem yeniden
// baslama) ogrenilenler sifirlanir ve en hizli yontem tekrar denenir.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public static class EmyProxy
{
    static readonly object LogLock = new object();
    static string LogPath;
    static string StatePath;
    static string DnsPath;
    static string Mode = "auto";

    // ---------------- bolme yontemleri (hizlidan yavasa) ----------------
    // oob    : SNI'nin 1. baytindan sonra TCP "acil veri" (URG) olarak 1 bayt gonderir. Sunucu bu bayti
    //          akistan atar, DPI ise akisi yanlis birlestirir. En hizli ve en guclu yontem.
    // oob2   : ayni, acil bayt kaydin en basinda
    // tlsrec : ClientHello'yu SNI'nin 1. baytindan iki TLS kaydina boler
    // recfrag: tlsrec + SNI bitene kadar 1 baytlik TCP parcalari
    // multi  : SNI'yi 3 baytlik cok sayida TLS kaydina boler
    // frag   : SNI bitene kadar 1 baytlik TCP parcalari (en yavas, son care)
    static readonly string[] Strategies = { "oob", "oob2", "tlsrec", "recfrag", "multi", "frag" };
    const string StateVersion = "v2:";
    static int Learned = 0;                                   // auto modda ogrenilen genel yontem
    static readonly Dictionary<string, int> HostLearned = new Dictionary<string, int>();
    static readonly int[] FailStreak = new int[Strategies.Length];
    static DateTime ReprobeAt = DateTime.MaxValue;            // en hizli yontemi tekrar deneme zamani
    const int ConnectTimeoutMs = 3000;
    const int ReplyTimeoutMs = 3000;

    // Sadece bu servislerin alan adlarina aracilik edilir (proxy baska bir amaca kullanilamaz)
    static readonly string[] AllowedSuffixes = {
        "discord.com", "discord.gg", "discord.media", "discord.co", "discord.new", "discord.gift",
        "discord.dev", "discordapp.com", "discordapp.net", "discordcdn.com", "roblox.com", "blox.com",
        "discord-attachments-uploads-prd.storage.googleapis.com"   // eski surum kurulumlarinin hosts kaydi
    };

    // ---------------- DoH ----------------
    // Hepsi IP ile cagrilir (DNS gerekmez, SNI gonderilmez). RFC 8484 wire format, tum saglayicilar destekler.
    static readonly string[] Resolvers = {
        "https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query", "https://94.140.14.140/dns-query",
        "https://1.0.0.1/dns-query", "https://8.8.4.4/dns-query", "https://94.140.14.141/dns-query"
    };
    static int GoodResolver = 0;
    class CacheEntry { public string[] Ips; public DateTime Expires; public bool Refreshing; }
    static readonly Dictionary<string, CacheEntry> Cache = new Dictionary<string, CacheEntry>();

    public static void Log(string msg)
    {
        string line = DateTime.Now.ToString("HH:mm:ss") + " " + msg;
        Console.WriteLine(line);
        if (LogPath == null) return;
        lock (LogLock)
        {
            try
            {
                FileInfo fi = new FileInfo(LogPath);
                if (fi.Exists && fi.Length > 512 * 1024) File.WriteAllText(LogPath, "");
                File.AppendAllText(LogPath, line + Environment.NewLine);
            }
            catch { }
        }
    }

    public static void Run(int port, string mode, string logPath)
    {
        Mode = mode;
        LogPath = logPath;
        string dir = Path.GetDirectoryName(logPath);
        StatePath = Path.Combine(dir, "emydpi-strategy.txt");
        DnsPath = Path.Combine(dir, "emydpi-dns.txt");
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        ServicePointManager.DefaultConnectionLimit = 32;
        LoadLearned();
        LoadDns();
        NetworkChange.NetworkAddressChanged += delegate { OnNetworkChanged(); };
        NetworkChange.NetworkAvailabilityChanged += delegate { OnNetworkChanged(); };

        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        try { listener.Start(); }
        catch (Exception e)
        {
            Log("HATA: 127.0.0.1:" + port + " dinlenemiyor (baska bir program kullaniyor olabilir): " + e.Message);
            throw;
        }
        Log("EMYDPI proxy calisiyor: 127.0.0.1:" + port + " mod=" + mode +
            (mode == "auto" ? " (ogrenilen yontem: " + Strategies[Learned] + ")" : ""));
        while (true)
        {
            TcpClient c;
            try { c = listener.AcceptTcpClient(); }
            catch (Exception e) { Log("kabul hatasi: " + e.Message); Thread.Sleep(200); continue; }
            Thread t = new Thread(Handle);
            t.IsBackground = true;
            t.Start(c);
        }
    }

    static DateTime lastNetChange = DateTime.MinValue;
    static void OnNetworkChanged()
    {
        lock (HostLearned)
        {
            if ((DateTime.Now - lastNetChange).TotalSeconds < 5) return;   // ayni degisiklik icin birden fazla olay gelir
            lastNetChange = DateTime.Now;
            HostLearned.Clear();
            for (int i = 0; i < FailStreak.Length; i++) FailStreak[i] = 0;
            if (Learned != 0) ReprobeAt = DateTime.Now;
        }
        Log("Ag degisikligi algilandi, baglantilar yeniden kurulacak");
    }

    static void LoadLearned()
    {
        try
        {
            if (!File.Exists(StatePath)) return;
            string s = File.ReadAllText(StatePath).Trim();
            if (!s.StartsWith(StateVersion)) return;           // eski surumun kaydi: en hizli yontemden basla
            int i = Array.IndexOf(Strategies, s.Substring(StateVersion.Length));
            if (i >= 0) Learned = i;
            if (Learned != 0) ReprobeAt = DateTime.Now.AddMinutes(10);
        }
        catch { }
    }

    static void SaveLearned(int i)
    {
        if (Learned == i) return;
        Learned = i;
        ReprobeAt = i == 0 ? DateTime.MaxValue : DateTime.Now.AddMinutes(10);
        try { File.WriteAllText(StatePath, StateVersion + Strategies[i]); } catch { }
        Log("Yeni yontem ogrenildi ve kaydedildi: " + Strategies[i]);
    }

    static bool ReadExact(Stream s, byte[] buf, int off, int len)
    {
        while (len > 0)
        {
            int n = s.Read(buf, off, len);
            if (n <= 0) return false;
            off += n; len -= n;
        }
        return true;
    }

    static bool IsAllowed(string host)
    {
        foreach (string s in AllowedSuffixes)
            if (host == s || host.EndsWith("." + s)) return true;
        return false;
    }

    // ClientHello icinde SNI adinin baslangic konumunu (record govdesine gore), uzunlugunu ve adi dondurur
    static string ParseSni(byte[] body, out int nameOffset, out int nameLen)
    {
        nameOffset = -1; nameLen = 0;
        try
        {
            int p = 0;
            if (body[p] != 0x01) return null;      // ClientHello
            p += 4;                                 // handshake header
            p += 2 + 32;                            // version + random
            p += 1 + body[p];                       // session id
            p += 2 + ((body[p] << 8) | body[p + 1]); // cipher suites
            p += 1 + body[p];                       // compression
            int extEnd = Math.Min(body.Length, p + 2 + ((body[p] << 8) | body[p + 1]));
            p += 2;
            while (p + 4 <= extEnd)
            {
                int type = (body[p] << 8) | body[p + 1];
                int len = (body[p + 2] << 8) | body[p + 3];
                p += 4;
                if (type == 0)
                {
                    int q = p + 2;                  // server_name_list length
                    if (body[q] == 0)               // host_name
                    {
                        nameLen = (body[q + 1] << 8) | body[q + 2];
                        nameOffset = q + 3;
                        if (nameLen <= 0 || nameLen > 253 || nameOffset + nameLen > body.Length) return null;
                        string name = Encoding.ASCII.GetString(body, nameOffset, nameLen).ToLowerInvariant();
                        foreach (char ch in name)
                            if (!((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '.')) return null;
                        return name;
                    }
                }
                p += len;
            }
        }
        catch { }
        return null;
    }

    // ---------------- DoH (RFC 8484) ----------------
    static byte[] BuildQuery(string host)
    {
        List<byte> q = new List<byte>(new byte[] { 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0 });
        foreach (string label in host.TrimEnd('.').Split('.'))
        {
            byte[] b = Encoding.ASCII.GetBytes(label);
            q.Add((byte)b.Length); q.AddRange(b);
        }
        q.AddRange(new byte[] { 0, 0, 1, 0, 1 });   // root, type A, class IN
        return q.ToArray();
    }

    static int SkipName(byte[] m, int p)
    {
        while (p < m.Length)
        {
            int l = m[p];
            if (l == 0) return p + 1;
            if ((l & 0xC0) == 0xC0) return p + 2;
            p += 1 + l;
        }
        return p;
    }

    // Yerel / ozel ag adresleri gercek sunucu olamaz (sahte DNS cevabi)
    static bool IsPublic(byte a, byte b)
    {
        if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
        if (a == 169 && b == 254) return false;
        if (a == 172 && b >= 16 && b <= 31) return false;
        if (a == 192 && b == 168) return false;
        if (a == 100 && b >= 64 && b <= 127) return false;
        return true;
    }

    static string[] ParseAnswer(byte[] m, out int ttl)
    {
        ttl = 300;
        List<string> ips = new List<string>();
        if (m.Length < 12 || (m[3] & 0x0F) != 0) return ips.ToArray();
        int qd = (m[4] << 8) | m[5], an = (m[6] << 8) | m[7];
        int p = 12;
        for (int i = 0; i < qd; i++) p = SkipName(m, p) + 4;
        bool first = true;
        for (int i = 0; i < an && p + 10 <= m.Length; i++)
        {
            p = SkipName(m, p);
            if (p + 10 > m.Length) break;
            int type = (m[p] << 8) | m[p + 1];
            int t = (m[p + 4] << 24) | (m[p + 5] << 16) | (m[p + 6] << 8) | m[p + 7];
            int rdlen = (m[p + 8] << 8) | m[p + 9];
            p += 10;
            if (type == 1 && rdlen == 4 && p + 4 <= m.Length)
            {
                if (IsPublic(m[p], m[p + 1])) ips.Add(m[p] + "." + m[p + 1] + "." + m[p + 2] + "." + m[p + 3]);
                if (first) { ttl = t; first = false; }
            }
            p += rdlen;
        }
        return ips.ToArray();
    }

    static string[] DohQuery(string url, string host, out int ttl)
    {
        string dns = Convert.ToBase64String(BuildQuery(host)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url + "?dns=" + dns);
        req.Accept = "application/dns-message";
        req.Timeout = 2500;
        req.ReadWriteTimeout = 2500;
        req.Proxy = null;
        using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
        using (Stream s = resp.GetResponseStream())
        using (MemoryStream ms = new MemoryStream())
        {
            s.CopyTo(ms);
            return ParseAnswer(ms.ToArray(), out ttl);
        }
    }

    // Tum DoH saglayicilarini sirayla dener; maxTries kadar
    static string[] Lookup(string host, int maxTries)
    {
        int start = GoodResolver;
        for (int k = 0; k < Math.Min(maxTries, Resolvers.Length); k++)
        {
            int i = (start + k) % Resolvers.Length;
            try
            {
                int ttl;
                string[] ips = DohQuery(Resolvers[i], host, out ttl);
                if (ips.Length == 0) continue;
                ttl = Math.Max(60, Math.Min(ttl, 1800));
                lock (Cache) { Cache[host] = new CacheEntry { Ips = ips, Expires = DateTime.Now.AddSeconds(ttl) }; }
                if (GoodResolver != i) { GoodResolver = i; Log("DNS saglayici: " + Resolvers[i]); }
                SaveDns();
                return ips;
            }
            catch { }
        }
        return null;
    }

    static string[] Resolve(string host)
    {
        CacheEntry e;
        lock (Cache)
        {
            if (Cache.TryGetValue(host, out e))
            {
                if (e.Expires > DateTime.Now) return e.Ips;
                // suresi dolmus kayit: hemen eski IP ile devam et, arka planda yenile (beklemeden)
                if (!e.Refreshing)
                {
                    e.Refreshing = true;
                    CacheEntry ce = e;
                    ThreadPool.QueueUserWorkItem(delegate { if (Lookup(host, Resolvers.Length) == null) ce.Refreshing = false; });
                }
                return e.Ips;
            }
        }
        return Lookup(host, 4);
    }

    // DNS kayitlari diske yazilir: internet yeni geldiginde DoH henuz cevap vermese bile baglanilabilir
    static DateTime lastDnsSave = DateTime.MinValue;
    static void SaveDns()
    {
        try
        {
            StringBuilder sb = new StringBuilder();
            lock (Cache)
            {
                if ((DateTime.Now - lastDnsSave).TotalSeconds < 20) return;
                lastDnsSave = DateTime.Now;
                foreach (KeyValuePair<string, CacheEntry> kv in Cache)
                    sb.Append(kv.Key).Append(' ').Append(string.Join(",", kv.Value.Ips)).Append("\r\n");
            }
            File.WriteAllText(DnsPath, sb.ToString());
        }
        catch { }
    }

    static void LoadDns()
    {
        try
        {
            if (!File.Exists(DnsPath)) return;
            foreach (string line in File.ReadAllLines(DnsPath))
            {
                string[] p = line.Split(' ');
                if (p.Length != 2 || !IsAllowed(p[0])) continue;
                List<string> ips = new List<string>();
                foreach (string ip in p[1].Split(','))
                {
                    IPAddress a;
                    if (IPAddress.TryParse(ip, out a) && a.AddressFamily == AddressFamily.InterNetwork &&
                        IsPublic(a.GetAddressBytes()[0], a.GetAddressBytes()[1])) ips.Add(ip);
                }
                // suresi dolmus kabul edilir: ilk kullanimda arka planda yenilenir
                if (ips.Count > 0) Cache[p[0]] = new CacheEntry { Ips = ips.ToArray(), Expires = DateTime.MinValue };
            }
        }
        catch { }
    }

    // ---------------- gonderim ----------------
    static byte[] Record(byte[] hdr, byte[] body, int off, int len)
    {
        byte[] r = new byte[5 + len];
        r[0] = hdr[0]; r[1] = hdr[1]; r[2] = hdr[2];
        r[3] = (byte)(len >> 8); r[4] = (byte)len;
        Array.Copy(body, off, r, 5, len);
        return r;
    }

    static void Send(Socket s, byte[] b, int off, int len)
    {
        while (len > 0) { int n = s.Send(b, off, len, SocketFlags.None); off += n; len -= n; }
    }

    // b dizisini "until" konumuna kadar chunk baytlik TCP parcalari, gerisini tek seferde gonder
    static void SendChunked(Socket s, byte[] b, int until, int chunk, int delayMs)
    {
        until = Math.Min(until, b.Length);
        int i = 0;
        for (; i < until; i += chunk) { Send(s, b, i, Math.Min(chunk, until - i)); Thread.Sleep(delayMs); }
        if (i < b.Length) Send(s, b, i, b.Length - i);
    }

    static void SendHello(Socket ss, string strategy, byte[] hdr, byte[] body, int nameOff, int nameLen)
    {
        int recLen = body.Length;
        int a = nameOff + 1;
        byte[] all = new byte[5 + recLen];
        Array.Copy(hdr, all, 5); Array.Copy(body, 0, all, 5, recLen);

        if (strategy == "oob" || strategy == "oob2")
        {
            int cut = strategy == "oob" ? 5 + a : 1;
            Send(ss, all, 0, cut);
            ss.Send(new byte[] { 0 }, 0, 1, SocketFlags.OutOfBand);   // sunucu tarafinda akistan atilir
            Send(ss, all, cut, all.Length - cut);
        }
        else if (strategy == "tlsrec")
        {
            Send(ss, Record(hdr, body, 0, a), 0, 5 + a);
            Thread.Sleep(5);
            byte[] r2 = Record(hdr, body, a, recLen - a);
            Send(ss, r2, 0, r2.Length);
        }
        else if (strategy == "multi")
        {
            // ilk kayit SNI'nin 1. baytina kadar, sonra SNI 3'er baytlik kayitlar, sonra geri kalan
            List<int> cuts = new List<int>();
            cuts.Add(a);
            for (int c = a + 3; c < nameOff + nameLen; c += 3) cuts.Add(c);
            cuts.Add(nameOff + nameLen);
            int prev = 0;
            foreach (int c in cuts)
            {
                if (c <= prev) continue;
                byte[] r = Record(hdr, body, prev, c - prev);
                Send(ss, r, 0, r.Length);
                Thread.Sleep(2);
                prev = c;
            }
            if (prev < recLen) { byte[] r = Record(hdr, body, prev, recLen - prev); Send(ss, r, 0, r.Length); }
        }
        else if (strategy == "recfrag")
        {
            byte[] r1 = Record(hdr, body, 0, a);
            byte[] r2 = Record(hdr, body, a, recLen - a);
            byte[] two = new byte[r1.Length + r2.Length];
            Array.Copy(r1, two, r1.Length); Array.Copy(r2, 0, two, r1.Length, r2.Length);
            // ilk kaydin son kismi + SNI'nin tamami 1 baytlik TCP parcalarinda
            int from = Math.Max(0, 5 + a - 8);
            Send(ss, two, 0, from);
            Thread.Sleep(2);
            byte[] rest = new byte[two.Length - from];
            Array.Copy(two, from, rest, 0, rest.Length);
            SendChunked(ss, rest, (5 + nameOff + nameLen + 5) - from + 4, 1, 1);
        }
        else // frag
        {
            SendChunked(ss, all, 5 + nameOff + nameLen + 4, 1, 2);
        }
    }

    static Socket ConnectWithTimeout(string ip, int ms)
    {
        Socket s = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        s.NoDelay = true;
        try
        {
            IAsyncResult ar = s.BeginConnect(IPAddress.Parse(ip), 443, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(ms)) throw new IOException("zaman asimi");
            s.EndConnect(ar);
            return s;
        }
        catch { try { s.Close(); } catch { } return null; }
    }

    enum TryResult { Ok, NoConnect, Blocked }

    // Bir yontemle dener; sunucudan ilk cevap gelirse baglantiyi ve ilk veriyi dondurur.
    // NoConnect: sunucuya hic ulasilamadi (internet / IP sorunu). Blocked: baglanti kuruldu ama cevap yok (DPI).
    static TryResult TryStrategy(string ip, string strategy, byte[] hdr, byte[] body, int nameOff, int nameLen,
                                 out Socket server, out byte[] first, out int firstLen)
    {
        first = null; firstLen = 0;
        server = ConnectWithTimeout(ip, ConnectTimeoutMs);
        if (server == null) return TryResult.NoConnect;
        try
        {
            SendHello(server, strategy, hdr, body, nameOff, nameLen);
            server.ReceiveTimeout = ReplyTimeoutMs;
            byte[] buf = new byte[64 * 1024];
            int n = server.Receive(buf);
            if (n <= 0) throw new IOException("sunucu baglantiyi kapatti");
            server.ReceiveTimeout = 0;
            first = buf; firstLen = n;
            return TryResult.Ok;
        }
        catch
        {
            try { server.Close(); } catch { }
            server = null;
            return TryResult.Blocked;
        }
    }

    static List<int> BuildOrder(string host)
    {
        List<int> order = new List<int>();
        if (Mode != "auto")
        {
            int i = Array.IndexOf(Strategies, Mode);
            order.Add(i < 0 ? 0 : i);
            return order;
        }
        lock (HostLearned)
        {
            // ogrenilen yontem en hizlisi degilse ara sira en hizlisini tekrar dene (DPI degismis olabilir)
            if (DateTime.Now >= ReprobeAt) { order.Add(0); ReprobeAt = DateTime.Now.AddMinutes(10); }
            int h;
            if (HostLearned.TryGetValue(host, out h) && !order.Contains(h)) order.Add(h);
        }
        if (!order.Contains(Learned)) order.Add(Learned);
        for (int i = 0; i < Strategies.Length; i++) if (!order.Contains(i)) order.Add(i);
        return order;
    }

    static void Handle(object o)
    {
        TcpClient client = (TcpClient)o;
        Socket server = null;
        string host = "?";
        try
        {
            client.NoDelay = true;
            client.ReceiveTimeout = 10000;
            NetworkStream cs = client.GetStream();
            byte[] hdr = new byte[5];
            if (!ReadExact(cs, hdr, 0, 5) || hdr[0] != 0x16) { client.Close(); return; }
            int recLen = (hdr[3] << 8) | hdr[4];
            if (recLen < 40 || recLen > 16384 + 2048) { client.Close(); return; }
            byte[] body = new byte[recLen];
            if (!ReadExact(cs, body, 0, recLen)) { client.Close(); return; }
            client.ReceiveTimeout = 0;

            int nameOff, nameLen;
            host = ParseSni(body, out nameOff, out nameLen);
            if (host == null) { Log("SNI bulunamadi, baglanti kapatildi"); client.Close(); return; }
            if (!IsAllowed(host)) { Log(host + ": Discord/Roblox adresi degil, reddedildi"); client.Close(); return; }

            string[] ips = Resolve(host);
            if (ips == null || ips.Length == 0) { Log(host + " cozulemedi (DoH) - internet baglantisi var mi?"); client.Close(); return; }

            List<int> order = BuildOrder(host);
            byte[] first = null; int firstLen = 0;
            string usedIp = null; int used = -1;
            int ipIdx = 0, noConnect = 0;
            bool relooked = false;
            List<int> blocked = new List<int>();
            for (int k = 0; k < order.Count && server == null; )
            {
                if (noConnect >= Math.Min(ips.Length, 3))
                {
                    // kayitli IP'lere ulasilamadi: IP degismis olabilir, bir kez taze DNS sorgusuyla tekrar dene
                    if (relooked) break;
                    relooked = true;
                    string[] fresh = Lookup(host, 3);
                    if (fresh == null || string.Join(",", fresh) == string.Join(",", ips)) break;
                    ips = fresh; ipIdx = 0; noConnect = 0;
                }
                string ip = ips[ipIdx % ips.Length];
                TryResult r = TryStrategy(ip, Strategies[order[k]], hdr, body, nameOff, nameLen, out server, out first, out firstLen);
                if (r == TryResult.Ok) { usedIp = ip; used = order[k]; break; }
                if (r == TryResult.NoConnect)
                {
                    // yontem sorunu degil: ayni yontemle baska IP dene, hicbirine ulasilamiyorsa vazgec
                    ipIdx++; noConnect++;
                    continue;
                }
                blocked.Add(order[k]);
                if (Mode == "auto") Log(host + ": " + Strategies[order[k]] + " cevap almadi, sonraki deneniyor");
                k++;
            }
            if (server == null)
            {
                if (blocked.Count == 0) Log(host + ": sunucuya ulasilamadi (internet baglantisi kesik olabilir)");
                else Log(host + " baglanamadi (" + (Mode == "auto" ? "denenen yontemler cevap almadi" : "mod=" + Mode) + ")");
                client.Close();
                return;
            }
            if (Mode == "auto")
            {
                lock (HostLearned)
                {
                    HostLearned[host] = used;
                    FailStreak[used] = 0;
                    foreach (int b in blocked) FailStreak[b]++;
                }
                // genel yontem birden fazla kez DPI tarafindan engellendiyse ya da daha hizli bir yontem
                // tekrar calismaya basladiysa genel yontemi degistir
                if (used < Learned || (blocked.Contains(Learned) && FailStreak[Learned] >= 2)) SaveLearned(used);
            }

            Log(host + " -> " + usedIp + (Mode == "auto" ? " [" + Strategies[used] + "]" : ""));
            server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
            client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
            NetworkStream ss = new NetworkStream(server, true);
            cs.Write(first, 0, firstLen);
            Socket srv = server;
            Thread up = new Thread(delegate () { Pump(cs, ss, client, srv); });
            up.IsBackground = true;
            up.Start();
            Pump(ss, cs, client, server);
        }
        catch (Exception e)
        {
            Log(host + " hata: " + e.Message);
            try { client.Close(); } catch { }
            try { if (server != null) server.Close(); } catch { }
        }
    }

    static void Pump(Stream from, Stream to, TcpClient a, Socket b)
    {
        byte[] buf = new byte[64 * 1024];
        try
        {
            int n;
            while ((n = from.Read(buf, 0, buf.Length)) > 0) to.Write(buf, 0, n);
        }
        catch { }
        try { a.Close(); } catch { }
        try { b.Close(); } catch { }
    }
}
