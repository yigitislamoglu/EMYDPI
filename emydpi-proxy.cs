// EMYDPI yerel SNI proxy
// hosts dosyasi secilen servislerin alan adlarini 127.0.0.1'e yonlendirir. Bu proxy 127.0.0.1:443'te
// dinler, gelen TLS ClientHello'dan SNI'yi okur, gercek IP'yi sifreli DNS (DoH) ile bulur ve
// ClientHello'yu DPI'nin alan adini okuyamayacagi sekilde bolerek iletir.
// TLS cozulmez; sifreli trafik oldugu gibi aktarilir.
//
// auto modu: her internet saglayicisinin DPI'si farkli davranabilir. Proxy sirayla birkac bolme
// yontemi dener; sunucu cevap verdigi ilk yontemi ogrenir, kaydeder ve sonraki baglantilarda
// dogrudan onu kullanir. Istemciye henuz hicbir sey gonderilmedigi icin yeniden deneme guvenlidir.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public static class EmyProxy
{
    static readonly object LogLock = new object();
    static string LogPath;
    static string StatePath;
    static string Mode = "auto";

    // ---------------- bolme yontemleri ----------------
    // tlsrec : ClientHello'yu SNI'nin 1. baytindan iki TLS kaydina boler (hizli, cogu DPI icin yeterli)
    // multi  : SNI'yi birkac baytlik cok sayida TLS kaydina boler
    // recfrag: tlsrec + SNI bitene kadar kucuk TCP parcalari
    // frag   : SNI bitene kadar 2 baytlik TCP parcalari (eski yedek mod)
    static readonly string[] Strategies = { "tlsrec", "multi", "recfrag", "frag" };
    static int Learned = 0;                                   // auto modda ogrenilen genel yontem
    static readonly Dictionary<string, int> HostLearned = new Dictionary<string, int>();
    const int TryTimeoutMs = 4000;

    // ---------------- DoH ----------------
    // Hepsi IP ile cagrilir (DNS gerekmez, SNI gonderilmez). RFC 8484 wire format, tum saglayicilar destekler.
    static readonly string[] Resolvers = {
        "https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query", "https://94.140.14.140/dns-query",
        "https://1.0.0.1/dns-query", "https://8.8.4.4/dns-query", "https://94.140.14.141/dns-query"
    };
    static int GoodResolver = 0;
    class CacheEntry { public string[] Ips; public DateTime Expires; }
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
        StatePath = Path.Combine(Path.GetDirectoryName(logPath), "emydpi-strategy.txt");
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        ServicePointManager.DefaultConnectionLimit = 32;
        LoadLearned();
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
            TcpClient c = listener.AcceptTcpClient();
            Thread t = new Thread(Handle);
            t.IsBackground = true;
            t.Start(c);
        }
    }

    static void LoadLearned()
    {
        try
        {
            if (!File.Exists(StatePath)) return;
            int i = Array.IndexOf(Strategies, File.ReadAllText(StatePath).Trim());
            if (i >= 0) Learned = i;
        }
        catch { }
    }

    static void SaveLearned(int i)
    {
        if (Learned == i) return;
        Learned = i;
        try { File.WriteAllText(StatePath, Strategies[i]); } catch { }
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
            int extEnd = p + 2 + ((body[p] << 8) | body[p + 1]);
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
                        if (nameLen <= 0 || nameOffset + nameLen > body.Length) return null;
                        return Encoding.ASCII.GetString(body, nameOffset, nameLen).ToLowerInvariant();
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
            int type = (m[p] << 8) | m[p + 1];
            int t = (m[p + 4] << 24) | (m[p + 5] << 16) | (m[p + 6] << 8) | m[p + 7];
            int rdlen = (m[p + 8] << 8) | m[p + 9];
            p += 10;
            if (type == 1 && rdlen == 4 && p + 4 <= m.Length)
            {
                string ip = m[p] + "." + m[p + 1] + "." + m[p + 2] + "." + m[p + 3];
                // 0.0.0.0 / 127.x / 10.x gibi sahte cevaplari kabul etme
                if (m[p] != 0 && m[p] != 127 && m[p] != 10) ips.Add(ip);
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
        req.Timeout = 3000;
        req.ReadWriteTimeout = 3000;
        req.Proxy = null;
        using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
        using (Stream s = resp.GetResponseStream())
        using (MemoryStream ms = new MemoryStream())
        {
            s.CopyTo(ms);
            return ParseAnswer(ms.ToArray(), out ttl);
        }
    }

    static string[] Resolve(string host)
    {
        CacheEntry stale = null;
        lock (Cache)
        {
            CacheEntry e;
            if (Cache.TryGetValue(host, out e))
            {
                if (e.Expires > DateTime.Now) return e.Ips;
                stale = e;
            }
        }
        int start = GoodResolver;
        for (int k = 0; k < Resolvers.Length; k++)
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
                return ips;
            }
            catch { }
        }
        if (stale != null) { Log(host + ": DoH cevap vermedi, eski kayit kullaniliyor"); return stale.Ips; }
        return null;
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

    static void Send(Stream s, byte[] b, int off, int len) { s.Write(b, off, len); s.Flush(); }

    // b dizisini "until" konumuna kadar chunk baytlik TCP parcalari, gerisini tek seferde gonder
    static void SendChunked(Stream s, byte[] b, int until, int chunk)
    {
        until = Math.Min(until, b.Length);
        int i = 0;
        for (; i < until; i += chunk) { Send(s, b, i, Math.Min(chunk, until - i)); Thread.Sleep(1); }
        if (i < b.Length) Send(s, b, i, b.Length - i);
    }

    static void SendHello(Stream ss, string strategy, byte[] hdr, byte[] body, int nameOff, int nameLen)
    {
        int recLen = body.Length;
        int a = nameOff + 1;
        if (strategy == "tlsrec")
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
            byte[] all = new byte[r1.Length + r2.Length];
            Array.Copy(r1, all, r1.Length); Array.Copy(r2, 0, all, r1.Length, r2.Length);
            // ilk kaydin son kismi + SNI'nin tamami 1 baytlik TCP parcalarinda
            int from = Math.Max(0, 5 + a - 8);
            Send(ss, all, 0, from);
            Thread.Sleep(2);
            byte[] rest = new byte[all.Length - from];
            Array.Copy(all, from, rest, 0, rest.Length);
            SendChunked(ss, rest, (5 + nameOff + nameLen + 5) - from + 4, 1);
        }
        else // frag
        {
            byte[] all = new byte[5 + recLen];
            Array.Copy(hdr, all, 5); Array.Copy(body, 0, all, 5, recLen);
            SendChunked(ss, all, 5 + nameOff + nameLen + 4, 2);
        }
    }

    static TcpClient ConnectWithTimeout(string ip, int ms)
    {
        TcpClient c = new TcpClient();
        c.NoDelay = true;
        IAsyncResult ar = c.BeginConnect(ip, 443, null, null);
        if (!ar.AsyncWaitHandle.WaitOne(ms) || !c.Connected)
        {
            try { c.Close(); } catch { }
            throw new IOException(ip + ":443 baglanti zaman asimi");
        }
        c.EndConnect(ar);
        return c;
    }

    // Bir yontemle dener; sunucudan ilk cevap gelirse baglantiyi ve ilk veriyi dondurur
    static TcpClient TryStrategy(string ip, string strategy, byte[] hdr, byte[] body, int nameOff, int nameLen,
                                 out byte[] first, out int firstLen)
    {
        first = null; firstLen = 0;
        TcpClient server = null;
        try
        {
            server = ConnectWithTimeout(ip, TryTimeoutMs);
            NetworkStream ss = server.GetStream();
            SendHello(ss, strategy, hdr, body, nameOff, nameLen);
            ss.ReadTimeout = TryTimeoutMs;
            byte[] buf = new byte[32 * 1024];
            int n = ss.Read(buf, 0, buf.Length);
            if (n <= 0) throw new IOException("sunucu baglantiyi kapatti");
            ss.ReadTimeout = Timeout.Infinite;
            first = buf; firstLen = n;
            return server;
        }
        catch
        {
            try { if (server != null) server.Close(); } catch { }
            return null;
        }
    }

    static void Handle(object o)
    {
        TcpClient client = (TcpClient)o;
        TcpClient server = null;
        string host = "?";
        try
        {
            client.NoDelay = true;
            NetworkStream cs = client.GetStream();
            byte[] hdr = new byte[5];
            if (!ReadExact(cs, hdr, 0, 5) || hdr[0] != 0x16) { client.Close(); return; }
            int recLen = (hdr[3] << 8) | hdr[4];
            byte[] body = new byte[recLen];
            if (!ReadExact(cs, body, 0, recLen)) { client.Close(); return; }

            int nameOff, nameLen;
            host = ParseSni(body, out nameOff, out nameLen);
            if (host == null) { Log("SNI bulunamadi, baglanti kapatildi"); client.Close(); return; }

            string[] ips = Resolve(host);
            if (ips == null || ips.Length == 0) { Log(host + " cozulemedi (DoH)"); client.Close(); return; }

            // denenecek yontem sirasi
            List<int> order = new List<int>();
            if (Mode == "auto")
            {
                int h;
                lock (HostLearned) { if (HostLearned.TryGetValue(host, out h)) order.Add(h); }
                if (!order.Contains(Learned)) order.Add(Learned);
                for (int i = 0; i < Strategies.Length; i++) if (!order.Contains(i)) order.Add(i);
            }
            else
            {
                int i = Array.IndexOf(Strategies, Mode);
                order.Add(i < 0 ? 0 : i);
            }

            byte[] first = null; int firstLen = 0;
            string usedIp = null; int used = -1;
            for (int k = 0; k < order.Count && server == null; k++)
            {
                // her denemede farkli IP (varsa) - tek bir sunucu sorunlu olabilir
                string ip = ips[k % ips.Length];
                server = TryStrategy(ip, Strategies[order[k]], hdr, body, nameOff, nameLen, out first, out firstLen);
                if (server != null) { usedIp = ip; used = order[k]; }
                else if (Mode == "auto") Log(host + ": " + Strategies[order[k]] + " yontemi cevap almadi, sonraki deneniyor");
            }
            if (server == null)
            {
                Log(host + " baglanamadi (" + (Mode == "auto" ? "tum yontemler denendi" : "mod=" + Mode) + ")");
                client.Close();
                return;
            }
            if (Mode == "auto")
            {
                lock (HostLearned) { HostLearned[host] = used; }
                // genel yontem denenip basarisiz olduysa yenisini genel yontem yap
                int li = order.IndexOf(Learned), ui = order.IndexOf(used);
                if (li >= 0 && li < ui) SaveLearned(used);
            }

            Log(host + " -> " + usedIp + (Mode == "auto" ? " [" + Strategies[used] + "]" : ""));
            NetworkStream ss = server.GetStream();
            cs.Write(first, 0, firstLen);
            TcpClient srv = server;
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

    static void Pump(Stream from, Stream to, TcpClient a, TcpClient b)
    {
        byte[] buf = new byte[32 * 1024];
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
