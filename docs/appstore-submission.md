# RelayPulse iOS — App Store gönderim paketi

App Store Connect app id **6808128260** · bundle `com.baris.relaypulse` · v1.0.5 (6)

---

## ⛔ Önce bu: hesap engeli

**Paid Apps Agreement durumu "New"** (imzalanmamış). Bu imzalanmadan App Store'da
ücretli hiçbir uygulama satılamaz. Sıra: legal entity bilgileri → banka (IBAN) →
vergi formları (Norveç + ABD W-8BEN) → Apple doğrulaması. **Günler sürer, sadece
hesap sahibi yapabilir.** Bugün başlat, gerisi paralel ilerlesin.

Ayrıca **DSA trader beyanı** gerekiyor (AB dağıtımı için). ⚠️ Trader olarak beyan
edersen iletişim bilgilerin AB App Store sayfasında herkese görünür — şahıs
hesabında bu ev adresi demek.

---

## App Review Information (gönderirken doldurulacak)

### Notes — bunu birebir kopyala

```
RelayPulse is an administration tool for operators of Anyone Protocol relay
servers. It connects over SSH and HTTPS to servers that the user owns and
configures; there is no RelayPulse backend and no account system.

HOW TO REVIEW WITHOUT SERVERS
The app cannot show anything useful until the reviewer adds a server, and we
cannot supply real production servers. For this reason the app includes a demo
mode with a fictional fleet:

  Settings tab  ->  "Try it out"  ->  turn on "Demo data"

This fills every screen (fleet dashboard, per-relay detail, fleet health,
metrics) with sample data and makes no network connections. A banner at the top
of the dashboard makes clear the data is not real. All UI can be reviewed this
way. The switch can be turned off again at any time.

ABOUT THE ATS EXCEPTION (NSAllowsArbitraryLoads)
The app connects to servers whose addresses are typed in by the user, so the
domains cannot be declared in advance. Two cases require the exception:
  1. Each relay runs a small monitoring agent over HTTPS with a self-signed
     certificate. Identity is proven by a shared token (X-Agent-Token) that the
     user configures, not by a public CA.
  2. Optionally, the app reads fleet status from RelayPulse running on the
     user's own Mac over the local network, which is plain HTTP on the LAN.
No third-party or advertising traffic is involved.

LOCAL NETWORK PERMISSION
Used solely to reach the user's own Mac at an address they enter. The app does
not scan or enumerate the network.

AI FEATURE
Optional and off by default. If the user enters their own OpenAI or Anthropic
API key, error text and recent log lines from their own server are sent to that
provider under the user's own account.
```

### Contact
İletişim bilgileri App Store Connect'te zaten kayıtlı (Baris Adiyaman,
+47 40615187, baris.a@hotmail.no).

### Demo account
Gerekmiyor — hesap sistemi yok. Notlarda demo modu anlatıldı.

---

## Store listing

| Alan | Değer |
|---|---|
| **Kategori (birincil)** | Developer Tools |
| **Kategori (ikincil)** | Utilities |
| **Yaş sınırı** | 4+ |
| **Gizlilik Politikası URL** | `docs/privacy-policy.html` yayınlandıktan sonraki adres |
| **Destek URL** | https://barisadiy1974-hub.github.io/relaypulse/ |

### Name (30)
```
RelayPulse
```

### Subtitle (30)
```
Anyone relay fleet monitor
```

### Keywords (100)
```
relay,anyone,protocol,node,monitor,ssh,uptime,fleet,server,exit,onion,devops,sysadmin
```

### Promotional text (170)
```
Watch your Anyone Protocol relays from your pocket. Live health for every node, alerts when one stops earning, and one-tap diagnostics over SSH.
```

### Description
```
RelayPulse puts your Anyone Protocol relay fleet in your pocket.

SEE EVERY RELAY AT A GLANCE
One screen shows the whole fleet: online, warning, stale and offline counts, plus total bandwidth. Each card carries what actually matters — anon service state, connection count, download and upload, CPU, RAM and disk.

KNOW BEFORE YOUR NODES STOP EARNING
A relay can look "up" while the anon service is dead or the dashboard has stopped seeing it. RelayPulse separates those cases instead of showing one green light, so you find out while it is still fixable.

FLEET HEALTH
A dedicated view ranks what needs attention right now and lists the busiest relays, so a hundred nodes stay readable.

REAL TOOLS, NOT JUST CHARTS
Open Nyx, read logs, check the agent endpoint or edit anonrc — over SSH, straight from the phone.

OPTIONAL AI DIAGNOSIS
Bring your own OpenAI or Anthropic key and let the app summarise what went wrong and suggest the fix. Off by default; your key stays in the Keychain.

WORKS WITH THE MAC APP
If you run RelayPulse on a Mac, the iPhone can read the fleet status it has already collected over your local network — no extra load on your relays.

PRIVATE BY DESIGN
No accounts, no backend, no analytics, no ads. The app talks only to the servers you configure. SSH keys and tokens live in the iOS Keychain and never leave your device.

TRY IT FIRST
Turn on Demo data in Settings to explore the whole app with a sample fleet before adding your own servers.

Requires servers you administer yourself. Optional monitoring agent (open source, included with the desktop app) gives richer metrics than SSH alone.
```

---

## App Privacy anketi — cevaplar

| Veri türü | Toplanıyor? |
|---|---|
| Contact Info, Health, Financial, Location, Contacts, User Content, Browsing History, Search History, Identifiers, Usage Data, Diagnostics | **Hayır (hepsi)** |

**"Data Not Collected"** seçilecek. Gerekçe: uygulama hiçbir veriyi geliştiriciye
göndermiyor; girilen sunucu bilgileri yalnızca cihazda kalıyor ve doğrudan
kullanıcının kendi sunucularına bağlanılıyor.

---

## Ekran görüntüleri

`store-screenshots/` altında, 1320×2868 (6.9"):
1. `1-relays.png` — filo paneli, dört durum ve demo şeridi
2. `2-relay-detail.png` — tek relay metrikleri ve araç butonları
3. `3-fleet-health.png` — dikkat gerektirenler + en yoğun relay'ler

Hepsi **demo veriden** çekildi; gerçek relay adı, IP veya cüzdan içermiyor.

---

## Gönderim öncesi kontrol listesi

- [ ] Paid Apps Agreement imzalandı (**engelleyici**)
- [ ] DSA trader beyanı yapıldı
- [ ] Gizlilik politikası yayınlandı, URL girildi
- [ ] Ekran görüntüleri yüklendi
- [ ] App Privacy anketi "Data Not Collected" olarak dolduruldu
- [ ] Yaş sınırı anketi
- [ ] Fiyat belirlendi
- [ ] App Review Notes yukarıdaki metinle dolduruldu
- [ ] Yeni build yüklendi (v1.0.6, demo modu içeren)
