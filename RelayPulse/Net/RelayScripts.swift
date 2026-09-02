import Foundation

/// Relay üzerinde çalıştırılan kabuk/python betikleri.
/// Swift ham dize (`#"""`) kullanılır — ters bölü ve tırnaklar aynen gider.
enum RelayScripts {

    /// nyx eşdeğeri. nyx'in yaptığı gibi anon **kontrol soketine** bağlanıp
    /// (cookie auth) gerçek relay verisini çeker: sürüm, uptime, toplam trafik,
    /// consensus bayrakları, ağırlık, OR bağlantı sayısı.
    ///
    /// Neden gerekliydi: `systemctl status anon` çok-örnekli kutularda
    /// "multi-instance-master" unit'ini gösteriyordu (`active (exited)`),
    /// `grep ... /etc/anon/anonrc*` ise yedek dosyaları da tarayıp aynı satırı
    /// defalarca yazdırıyordu.
    static let nyx = #"""
    python3 - <<'PYEOF'
    import socket, os, glob, subprocess

    def sh(c):
        try: return subprocess.check_output(c, shell=True, stderr=subprocess.DEVNULL, timeout=8).decode().strip()
        except Exception: return ""

    def human(n):
        try: n = float(n)
        except Exception: return "?"
        for u in ["B","KB","MB","GB","TB"]:
            if n < 1024: return "%.1f %s" % (n, u)
            n /= 1024
        return "%.1f PB" % n

    def dur(s):
        try: s = int(s)
        except Exception: return "?"
        d, s = divmod(s, 86400); h, s = divmod(s, 3600); m, _ = divmod(s, 60)
        return ("%dg " % d if d else "") + "%dsa %ddk" % (h, m)

    class Ctl:
        def __init__(self, path, cookie):
            self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); self.s.settimeout(6)
            self.s.connect(path)
            self.f = self.s.makefile("rwb")
            self._cmd("AUTHENTICATE " + cookie)
        def _cmd(self, c):
            self.f.write((c + "\r\n").encode()); self.f.flush()
            out = []
            while True:
                line = self.f.readline().decode(errors="replace").rstrip("\r\n")
                if not line: break
                out.append(line)
                if line[3:4] == " ": break
            return out
        def info(self, key):
            r = self._cmd("GETINFO " + key)
            if not r or not r[0].startswith("250"): return None
            vals = []
            for line in r:
                if line[:4] in ("250+", "250-", "250 "):
                    body = line[4:]
                    if body.startswith(key + "="): body = body[len(key) + 1:]
                    elif body == "OK": continue
                    if body: vals.append(body)
                elif line != ".":
                    vals.append(line)
            return "\n".join(vals).strip() or None
        def close(self):
            try: self._cmd("QUIT"); self.s.close()
            except Exception: pass

    units = [u.split()[0] for u in sh("systemctl list-units --type=service --state=running --no-pager --plain 'anon*'").splitlines() if u.startswith("anon")]
    print("=== ÇALIŞAN RELAY SERVİSLERİ ===")
    for u in units or ["(çalışan anon servisi yok)"]:
        if not u.startswith("anon"): print(u); continue
        pid = sh("systemctl show %s -p MainPID --value" % u)
        rss = sh("ps -o rss= -p %s" % pid) if pid and pid != "0" else ""
        cpu = sh("ps -o %%cpu= -p %s" % pid) if pid and pid != "0" else ""
        extra = (" · RAM " + human(int(rss) * 1024)) if rss.isdigit() else ""
        extra += (" · CPU " + cpu.strip() + "%") if cpu.strip() else ""
        print(u + "  aktif" + extra)
        since = sh("systemctl show %s -p ActiveEnterTimestamp --value" % u)
        if since: print("  başlangıç: " + since)

    sock = next((p for p in ["/run/anon/control", "/var/run/anon/control", "/run/tor/control"] if os.path.exists(p)), None)
    cookie_path = next(iter(glob.glob("/run/anon/*.authcookie") + glob.glob("/var/lib/anon/control_auth_cookie") + glob.glob("/run/tor/*.authcookie")), None)

    if not sock or not cookie_path:
        print("\n(kontrol soketi/cookie bulunamadı — sadece servis bilgisi)")
    else:
        try:
            c = Ctl(sock, open(cookie_path, "rb").read().hex())
            fpraw = c.info("fingerprint")
            fp = fpraw.split()[-1] if fpraw else None
            nick = c.info("conf/Nickname") or sh("grep -m1 '^Nickname' /etc/anon/anonrc | awk '{print $2}'")
            print("\n=== RELAY ===")
            print("Nickname     : " + (nick or "?"))
            print("Fingerprint  : " + (fp or "?"))
            print("Sürüm        : " + (c.info("version") or "?"))
            up = c.info("uptime")
            if up: print("Uptime       : " + dur(up))
            di = c.info("status/enough-dir-info")
            print("Dizin bilgisi: " + ("tam" if di == "1" else "eksik / indiriliyor"))

            print("\n=== TRAFİK (servis başından beri) ===")
            print("İndirilen: " + human(c.info("traffic/read")) + "   Yüklenen: " + human(c.info("traffic/written")))

            if fp:
                ns = c.info("ns/id/$" + fp)
                if ns:
                    for line in ns.splitlines():
                        if line.startswith("s "):
                            print("\n=== CONSENSUS BAYRAKLARI ===")
                            print("  " + ", ".join(line[2:].split()))
                        if line.startswith("w "):
                            print("Ağırlık: " + line[2:])
                else:
                    print("\n(consensus'ta bulunamadı — henüz yayılmamış olabilir)")

            oc = c.info("orconn-status")
            if oc:
                lines = [l for l in oc.splitlines() if l.strip()]
                states = {}
                for l in lines:
                    st = l.split()[-1] if l.split() else "?"
                    states[st] = states.get(st, 0) + 1
                print("\n=== OR BAĞLANTILARI ===")
                print("Toplam %d · " % len(lines) + ", ".join("%s: %d" % (k, v) for k, v in states.items()))
            c.close()
        except Exception as e:
            print("\n(kontrol portu hatası: %s)" % e)

    print("\n=== PORTLAR ===")
    print(sh("ss -tnlp 2>/dev/null | grep -E ':(9001|9030|9050|9051|443)\\b'") or "(dinleyen relay portu yok)")
    print("Kurulu bağlantı: " + (sh("ss -tn state established 2>/dev/null | tail -n +2 | wc -l") or "?"))

    print("\n=== YAPILANDIRMA (/etc/anon/anonrc) ===")
    print(sh("grep -E '^(Nickname|Address|ContactInfo|ORPort|DirPort|BandwidthRate|BandwidthBurst|RelayBandwidthRate|AccountingMax|ExitRelay)' /etc/anon/anonrc") or "(okunamadı)")
    ex = sh("grep -c '^ExitPolicy' /etc/anon/anonrc")
    if ex.isdigit() and int(ex) > 0: print("ExitPolicy   : %s satır" % ex)
    if sh("grep -c '^MyFamily' /etc/anon/anonrc") == "1":
        print("MyFamily     : %s üye" % sh("grep '^MyFamily' /etc/anon/anonrc | tr ',' '\\n' | wc -l"))
    PYEOF
    """#

    /// htop eşdeğeri — tek seferlik süreç/bellek/disk özeti.
    static let htop = #"""
    echo "=== YÜK ==="; uptime
    echo; echo "=== EN ÇOK CPU ==="; ps -eo pid,pcpu,pmem,rss,comm --sort=-pcpu 2>/dev/null | head -8
    echo; echo "=== EN ÇOK BELLEK ==="; ps -eo pid,pcpu,pmem,rss,comm --sort=-rss 2>/dev/null | head -6
    echo; echo "=== BELLEK ==="; free -m 2>/dev/null
    echo; echo "=== DİSK ==="; df -h / /var 2>/dev/null
    """#

    static let log = "journalctl -u anon -n 60 --no-pager 2>/dev/null || journalctl -u 'anon@*' -n 60 --no-pager 2>/dev/null || journalctl -u anyone-relay -n 60 --no-pager 2>/dev/null || echo '(log bulunamadı)'"

    static let https = #"""
    echo "=== AGENT (:19191) ==="
    curl -sk -m 8 -o /dev/null -w 'HTTP %{http_code} · %{time_total}s\n' https://127.0.0.1:19191/metrics 2>&1 || echo "curl basarisiz"
    echo "=== AGENT SERVİSİ ==="
    systemctl is-active anyone-agent 2>/dev/null || systemctl is-active relaypulse-agent 2>/dev/null || systemctl list-units --type=service --plain --no-pager '*agent*' 2>/dev/null | head -4 || echo "(agent servisi bulunamadı)"
    echo "=== DİNLEYEN ==="
    ss -tnlp 2>/dev/null | grep 19191 || echo "(19191 dinlenmiyor)"
    """#
}
