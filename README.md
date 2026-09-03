# RelayPulse for iPhone

Monitor your [Anyone Protocol](https://anyone.io) relay fleet from your iPhone. Real-time status, SSH tools, AI diagnostics — in your pocket.

## Features

- **Real-time monitoring** — polls each relay's HTTPS agent every 2 minutes (configurable), color-coded Online / Warning / Stale / Offline cards
- **Fleet Health** — see relays needing attention, RAM / disk / CPU hot lists at a glance
- **SSH tools** — Nyx relay stats, logs, htop summary, and anonrc editor over SSH
- **AI Diagnostics** — tap "Diagnose with AI" on any relay card; the model reads logs and suggests a fix command (OpenAI or Claude)
- **14-day free trial**, then a one-time license key (same format as desktop RelayPulse)

## Install (TestFlight Beta)

[![TestFlight](https://img.shields.io/badge/TestFlight-Join%20Beta-0d96f6?logo=apple)](https://testflight.apple.com/join/PLACEHOLDER)

1. iPhone'unda TestFlight uygulamasını aç (yoksa [App Store'dan](https://apps.apple.com/app/testflight/id899247664) indir)
2. Yukarıdaki linke tıkla → **Accept** → **Install**
3. Uygulama iPhone'una kurulur, güncellemeler otomatik gelir

> TestFlight bağlantısı yakında aktif olacak. Bu repo'yu izle (Watch → Releases).

## Requirements

- iPhone running iOS 17.0+
- Anyone Protocol relay fleet with [agent.py](https://github.com/barisadiy1974-hub/relaypulse-app) installed (`port 19191`)
- A dedicated ed25519 SSH key (phone-only — never share your fleet keys)

## Setup

### 1. Export your fleet from desktop RelayPulse

In the Mac / Linux app: **Tools → Export to iPhone** — saves a JSON you AirDrop or copy to the phone.

### 2. Import on iPhone

Open the app → tap **Import JSON** → pick the exported file. All relays load instantly.

### 3. Add an SSH key (for tools)

**Tools → SSH Key** → paste an unencrypted ed25519 private key dedicated to this phone. Generate one:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_relaypulse_iphone -C "relaypulse-iphone" -N ""
# Copy the public key to each relay's authorized_keys:
ssh-copy-id -i ~/.ssh/id_ed25519_relaypulse_iphone.pub root@<relay-host>
```

### 4. Add an AI key (optional)

**Settings → AI Settings** — paste an OpenAI or Anthropic API key. Used only for on-demand "Diagnose with AI" — never runs automatically.

## Architecture

| Component | Description |
|-----------|-------------|
| `Net/AgentClient.swift` | HTTPS polling to each relay's agent (port 19191, self-signed cert OK) |
| `Net/SSHRunner.swift` | Apple swift-nio-ssh, ed25519 auth, command exec |
| `Net/AIFixer.swift` | OpenAI gpt-4o-mini / Claude claude-haiku-4-5 diagnosis |
| `Store/FleetStore.swift` | Poll loop, flap dampening, metric delta calc |
| `Store/LicenseStore.swift` | Ed25519 offline license verification (14-day trial) |

**SSH library:** Apple's official [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) — no third-party forks.

**Security:** relay IPs, tokens, and SSH keys never appear in this repo. The phone SSH key is stored in the iOS Keychain; the fleet definition is encrypted at rest (FileProtectionType.complete).

## Building

```bash
# Install xcodegen if needed
brew install xcodegen

cd RelayPulse-iOS
xcodegen generate
open RelayPulse.xcodeproj
```

Build target: `RelayPulse` → your iPhone or simulator.

## License

14-day free trial. License keys sold at [relaypulse.app](https://barisadiy1974-hub.github.io/relaypulse) — same key works on iOS and desktop.
