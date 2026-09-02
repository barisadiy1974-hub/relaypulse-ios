# RelayPulse iOS

Anyone Protocol relay filosunu iPhone'dan izlemek için native SwiftUI uygulaması.
**Yalnızca izleme** — auto-fix, SSH, yapılandırma değişikliği yok (bunlar Mac/Pi RelayPulse'ta).

## Mimari

Standalone: uygulama **her relay'in HTTPS agent'ına doğrudan** bağlanır. Pi/Mac backend yok.

- `GET https://<host>:19191/metrics`  ·  header `X-Agent-Token: <token>`  ·  6s timeout
- Self-signed sertifika kabul (`AgentClient` URLSession delegate)
- Sağlıklı = anon servisi `active`/`activating` VEYA relay portu dinliyor
- Flap dampening: 1 başarısız poll → `stale` (sarı), `offlineAfter`+ → `offline` (kırmızı)
- rx/tx Mbps ve CPU% ardışık iki poll'un deltasından hesaplanır (Mac `monitor.js` ile aynı)

## Filo tanımını alma

Mac RelayPulse → **Ayarlar → İzleme → iPhone → "iPhone'a Aktar…"** bir JSON üretir
(host + agent portu + çözülmüş token). AirDrop ile telefona at, uygulamada **İçe Aktar**.
`Documents/fleet.json` olarak saklanır (cihaz kilitliyken şifreli).

## Derleme

```bash
brew install xcodegen
xcodegen generate
open RelayPulse.xcodeproj
```

Bundle ID: `com.baris.relaypulse` · Deployment target: iOS 17.0

## Dosya yapısı

```
RelayPulse/
  RelayPulseApp.swift      @main + scenePhase poll aç/kapa
  Models/                  Server, AgentMetrics, RelayStatus
  Net/AgentClient.swift    URLSession + self-signed + X-Agent-Token
  Store/
    FleetStore.swift       poll döngüsü, delta hesabı, flap dampening
    ServerStorage.swift     Documents/fleet.json persist
  Views/                   Dashboard, RelayCard, RelayDetail, Import, Settings
```
