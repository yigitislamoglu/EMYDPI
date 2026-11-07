// EMYDPI yerel SNI proxy
// hosts dosyasi Discord alan adlarini 127.0.0.1'e yonlendirir. Bu proxy 127.0.0.1:443'te
// dinler, gelen TLS ClientHello'dan SNI'yi okur, gercek IP'yi DoH ile bulur ve
// ClientHello'yu SNI'nin ortasindan iki TLS kaydina bolerek (ayri TCP paketleri) iletir.
// TLS cozulmez; sifreli trafik oldugu gibi aktarilir.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

public static class EmyProxy
{
    static readonly object LogLock = new object();
    static string LogPath;
    static string Mode = "tlsrec";
    static readonly Dictionary<string, KeyValuePair<string, DateTime>> Cache = new Dictionary<string, KeyValuePair<string, DateTime>>();

    static readonly string[] Resolvers = {
        "https://1.1.1.1/dns-query?name={0}&type=A",
        "https://8.8.8.8/resolve?name={0}&type=A",
        "https://1.0.0.1/dns-query?name={0}&type=A"
    };
    static readonly Regex ARecord = new Regex("\"type\"\\s*:\\s*1\\s*,[^}]*?\"data\"\\s*:\\s*\"([0-9.]+)\"");

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
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        try { listener.Start(); }
        catch (Exception e)
        {
            Log("HATA: 127.0.0.1:" + port + " dinlenemiyor (baska bir program kullaniyor olabilir): " + e.Message);
            throw;
        }
        Log("EMYDPI proxy calisiyor: 127.0.0.1:" + port + " mod=" + mode);
        while (true)
        {
            TcpClient c = listener.AcceptTcpClient();
            Thread t = new Thread(Handle);
            t.IsBackground = true;
            t.Start(c);
        }
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

    // ClientHello icinde SNI adinin baslangic konumunu (record govdesine gore) ve adi dondurur
    static string ParseSni(byte[] body, out int nameOffset)
    {
        nameOffset = -1;
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
                        int nlen = (body[q + 1] << 8) | body[q + 2];
                        nameOffset = q + 3;
                        return Encoding.ASCII.GetString(body, nameOffset, nlen);
                    }
                }
                p += len;
            }
        }
        catch { }
        return null;
    }

    static string Resolve(string host)
    {
        lock (Cache)
        {
            KeyValuePair<string, DateTime> e;
            if (Cache.TryGetValue(host, out e) && e.Value > DateTime.Now) return e.Key;
        }
        foreach (string r in Resolvers)
        {
            try
            {
                using (WebClient wc = new WebClient())
                {
                    wc.Headers.Add("accept", "application/dns-json");
                    string json = wc.DownloadString(string.Format(r, host));
                    Match m = ARecord.Match(json);
                    if (m.Success)
                    {
                        string ip = m.Groups[1].Value;
                        lock (Cache) { Cache[host] = new KeyValuePair<string, DateTime>(ip, DateTime.Now.AddMinutes(10)); }
                        return ip;
                    }
                }
            }
            catch { }
        }
        return null;
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

            int nameOff;
            host = ParseSni(body, out nameOff);
            if (host == null) { Log("SNI bulunamadi, baglanti kapatildi"); client.Close(); return; }

            string ip = Resolve(host);
            if (ip == null) { Log(host + " cozulemedi (DoH)"); client.Close(); return; }

            server = new TcpClient();
            server.NoDelay = true;
            server.Connect(ip, 443);
            NetworkStream ss = server.GetStream();

            if (Mode == "frag")
            {
                // yedek mod: ClientHello'yu 2 baytlik TCP parcalari halinde gonder (yavas ama saglam)
                byte[] all = new byte[5 + recLen];
                Array.Copy(hdr, all, 5); Array.Copy(body, 0, all, 5, recLen);
                for (int i = 0; i < all.Length; i += 2)
                {
                    ss.Write(all, i, Math.Min(2, all.Length - i));
                    ss.Flush();
                    Thread.Sleep(1);
                }
            }
            else
            {
                // tlsrec: SNI'nin 1. baytindan iki TLS kaydina bol, ayri TCP paketleriyle gonder
                int a = nameOff + 1;
                byte[] r1 = new byte[5 + a];
                byte[] r2 = new byte[5 + recLen - a];
                Array.Copy(hdr, r1, 3); r1[3] = (byte)(a >> 8); r1[4] = (byte)a;
                Array.Copy(body, 0, r1, 5, a);
                Array.Copy(hdr, r2, 3); r2[3] = (byte)((recLen - a) >> 8); r2[4] = (byte)(recLen - a);
                Array.Copy(body, a, r2, 5, recLen - a);
                ss.Write(r1, 0, r1.Length); ss.Flush();
                Thread.Sleep(5);
                ss.Write(r2, 0, r2.Length); ss.Flush();
            }

            Log(host + " -> " + ip);
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
