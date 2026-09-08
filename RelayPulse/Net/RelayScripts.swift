import Foundation

/// Shell / Python snippets executed on the relay over SSH.
/// Swift raw strings (`#"""`) so backslashes and quotes pass through untouched.
enum RelayScripts {

    /// Nyx equivalent. Like nyx, it talks to anon's **control socket** (cookie
    /// auth) for the real relay data: version, uptime, total traffic, consensus
    /// flags, weight, OR connection count.
    ///
    /// Why this is needed: `systemctl status anon` shows the
    /// "multi-instance-master" unit on multi-instance boxes (`active (exited)`),
    /// hiding the real `anon@…` instance, and `grep /etc/anon/anonrc*` also
    /// matches backup files, printing the same line several times.
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
        return ("%dd " % d if d else "") + "%dh %dm" % (h, m)

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
    print("=== RUNNING RELAY SERVICES ===")
    for u in units or ["(no anon service running)"]:
        if not u.startswith("anon"): print(u); continue
        pid = sh("systemctl show %s -p MainPID --value" % u)
        rss = sh("ps -o rss= -p %s" % pid) if pid and pid != "0" else ""
        cpu = sh("ps -o %%cpu= -p %s" % pid) if pid and pid != "0" else ""
        extra = (" · RAM " + human(int(rss) * 1024)) if rss.isdigit() else ""
        extra += (" · CPU " + cpu.strip() + "%") if cpu.strip() else ""
        print(u + "  active" + extra)
        since = sh("systemctl show %s -p ActiveEnterTimestamp --value" % u)
        if since: print("  started: " + since)

    sock = next((p for p in ["/run/anon/control", "/var/run/anon/control", "/run/tor/control"] if os.path.exists(p)), None)
    cookie_path = next(iter(glob.glob("/run/anon/*.authcookie") + glob.glob("/var/lib/anon/control_auth_cookie") + glob.glob("/run/tor/*.authcookie")), None)

    if not sock or not cookie_path:
        print("\n(no control socket / cookie found — service info only)")
    else:
        try:
            c = Ctl(sock, open(cookie_path, "rb").read().hex())
            fpraw = c.info("fingerprint")
            fp = fpraw.split()[-1] if fpraw else None
            nick = c.info("conf/Nickname") or sh("grep -m1 '^Nickname' /etc/anon/anonrc | awk '{print $2}'")
            print("\n=== RELAY ===")
            print("Nickname   : " + (nick or "?"))
            print("Fingerprint: " + (fp or "?"))
            print("Version    : " + (c.info("version") or "?"))
            up = c.info("uptime")
            if up: print("Uptime     : " + dur(up))
            di = c.info("status/enough-dir-info")
            print("Directory  : " + ("complete" if di == "1" else "incomplete / downloading"))

            print("\n=== TRAFFIC (since service start) ===")
            print("Read: " + human(c.info("traffic/read")) + "   Written: " + human(c.info("traffic/written")))

            if fp:
                ns = c.info("ns/id/$" + fp)
                if ns:
                    for line in ns.splitlines():
                        if line.startswith("s "):
                            print("\n=== CONSENSUS FLAGS ===")
                            print("  " + ", ".join(line[2:].split()))
                        if line.startswith("w "):
                            print("Weight: " + line[2:])
                else:
                    print("\n(not in the consensus yet — may still be propagating)")

            oc = c.info("orconn-status")
            if oc:
                lines = [l for l in oc.splitlines() if l.strip()]
                states = {}
                for l in lines:
                    st = l.split()[-1] if l.split() else "?"
                    states[st] = states.get(st, 0) + 1
                print("\n=== OR CONNECTIONS ===")
                print("Total %d · " % len(lines) + ", ".join("%s: %d" % (k, v) for k, v in states.items()))
            c.close()
        except Exception as e:
            print("\n(control port error: %s)" % e)

    print("\n=== PORTS ===")
    print(sh("ss -tnlp 2>/dev/null | grep -E ':(9001|9030|9050|9051|443)\\b'") or "(no relay port listening)")
    print("Established connections: " + (sh("ss -tn state established 2>/dev/null | tail -n +2 | wc -l") or "?"))

    print("\n=== CONFIG (/etc/anon/anonrc) ===")
    print(sh("grep -E '^(Nickname|Address|ContactInfo|ORPort|DirPort|BandwidthRate|BandwidthBurst|RelayBandwidthRate|AccountingMax|ExitRelay)' /etc/anon/anonrc") or "(unreadable)")
    ex = sh("grep -c '^ExitPolicy' /etc/anon/anonrc")
    if ex.isdigit() and int(ex) > 0: print("ExitPolicy : %s lines" % ex)
    if sh("grep -c '^MyFamily' /etc/anon/anonrc") == "1":
        print("MyFamily   : %s members" % sh("grep '^MyFamily' /etc/anon/anonrc | tr ',' '\\n' | wc -l"))
    PYEOF
    """#

    /// htop equivalent — one-shot process / memory / disk summary.
    static let htop = #"""
    echo "=== LOAD ==="; uptime
    echo; echo "=== TOP CPU ==="; ps -eo pid,pcpu,pmem,rss,comm --sort=-pcpu 2>/dev/null | head -8
    echo; echo "=== TOP MEMORY ==="; ps -eo pid,pcpu,pmem,rss,comm --sort=-rss 2>/dev/null | head -6
    echo; echo "=== MEMORY ==="; free -m 2>/dev/null
    echo; echo "=== DISK ==="; df -h / /var 2>/dev/null
    """#

    static let log = "journalctl -u anon -n 60 --no-pager 2>/dev/null || journalctl -u 'anon@*' -n 60 --no-pager 2>/dev/null || journalctl -u anyone-relay -n 60 --no-pager 2>/dev/null || echo '(no log found)'"

    static let https = #"""
    echo "=== AGENT (:19191) ==="
    curl -sk -m 8 -o /dev/null -w 'HTTP %{http_code} · %{time_total}s\n' https://127.0.0.1:19191/metrics 2>&1 || echo "curl failed"
    echo "=== AGENT SERVICE ==="
    systemctl is-active anyone-agent 2>/dev/null || systemctl is-active relaypulse-agent 2>/dev/null || systemctl list-units --type=service --plain --no-pager '*agent*' 2>/dev/null | head -4 || echo "(no agent service found)"
    echo "=== LISTENING ==="
    ss -tnlp 2>/dev/null | grep 19191 || echo "(nothing listening on 19191)"
    """#

    /// SSH fallback for the poll loop, used when the HTTPS agent on :19191 does
    /// not answer. Rather than re-collecting the metrics with a separate shell
    /// script (which would drift from the agent), it imports the agent module
    /// already installed on the relay and calls its own `collect()`. The output
    /// is therefore byte-for-byte the JSON the HTTP endpoint would have returned,
    /// so `AgentMetrics` decodes it unchanged.
    ///
    /// This is what lets the phone match the desktop app: the desktop falls back
    /// to SSH when the agent is unreachable (monitor.js), so a relay whose agent
    /// hiccups but whose SSH is fine stays green there. Without this the phone
    /// had only one measurement path and showed yellow for the same relay.
    static let metrics = #"""
    python3 - <<'PYEOF'
    import sys, json
    sys.path.insert(0, "/opt/anyone-agent")
    import agent
    print(json.dumps(agent.collect()))
    PYEOF
    """#

    /// Reads the agent's real token out of its systemd unit.
    ///
    /// The token lives in two places — the relay's unit file and this app's copy —
    /// so they can drift apart: rebuilding a relay regenerates it, and a fleet
    /// exported to the phone is a snapshot that ages. When they drift the agent
    /// answers 403 and a healthy relay looks broken. Desktop RelayPulse has
    /// repaired itself from this since the beginning (`monitor.js`
    /// `_fetchRemoteAgentToken`); this is the same command, so the two apps
    /// recover the same way.
    static let readAgentToken =
        "grep -oP '(?<=AGENT_TOKEN=)\\S+' /etc/systemd/system/anyone-agent.service 2>/dev/null || true"

    /// Locates the live anonrc and prints `PATH=<path>` then `---` then the contents.
    static let readAnonrc = #"""
    for p in /etc/anon/anonrc /etc/anon/anonrc-* /etc/anon/instances/*/anonrc /usr/local/etc/anon/anonrc /etc/tor/torrc; do
      [ -f "$p" ] && { echo "PATH=$p"; echo '---'; cat "$p"; exit 0; }
    done
    echo "PATH="; echo '---'; echo "(anonrc not found)"
    """#
}
