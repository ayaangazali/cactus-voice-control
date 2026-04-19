# Setup

## Prerequisites

- macOS 14+
- iPhone 15 Pro / Air or newer running iOS 17+ (Action Button required for one-press flow; iOS 17 mic + Live Activity work on any A12+ phone)
- Both devices on the **same Wi-Fi network**
- Apple Developer signing identity (free is fine)

## 1. Mac side

```bash
brew install cactus-compute/cactus/cactus xcodegen idb-companion uv
brew tap facebook/fb && brew install idb-companion   # if not yet present
cd mac-server
uv sync --all-extras
cp .env.example .env
uv run cactus-voice-mac --pair
```

`--pair` prints a terminal QR + writes a fresh `CACTUS_TOKEN` to `.env`. Leave it running.

Sanity check:

```bash
xcrun simctl list devices booted     # confirm a Simulator is booted
idb list-targets                      # confirm idb sees it
mobile-use "Open Settings"           # confirm mobile-use itself works
```

Run the test suite:

```bash
uv run pytest -q
```

## 2. iOS side

```bash
cd ios/CactusVoice
./scripts/fetch_cactus.sh             # downloads cactus-ios.xcframework + Cactus.swift
xcodegen generate
open CactusVoice.xcodeproj
```

In Xcode:
- Select the **CactusVoice** target → Signing & Capabilities → set your Team.
- Select your physical iPhone (not Simulator) as the run destination.
- Capabilities are pre-wired: Push Notifications and App Groups are NOT used (Live Activity uses local-only updates).
- Build & Run (⌘R). Trust the dev certificate in **Settings → General → VPN & Device Management** on the phone.

First launch:
1. Grant microphone permission.
2. Grant Local Network permission (so the app can reach the Mac on Wi-Fi).
3. Download the 3 GGUF models (~3.6 GB total). Use Wi-Fi.
4. Open **Settings ⚙** in the app → scan the QR from the Mac terminal (or type host/port/token manually).

## 3. Bind Action Button

**Settings → Action Button → swipe to "Shortcut" → Choose Shortcut → "Start Cactus listening"**.

(Apple does not let an app bind itself to the Action Button programmatically — this manual step is unavoidable.)

## 4. End-to-end smoke test

1. Hold the Action Button. Cactus opens, Live Activity appears on Lock Screen.
2. Speak: *"open notes and write hello world"*.
3. Pause for ≈1 s. The phase chip moves through `transcribing → thinking → sending → running`.
4. The Mac terminal shows the spawned `mobile-use` invocation; the iOS Simulator opens Notes and types.
5. Lock Screen activity flips to ✅ and dismisses after 8 s.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `mobile-use not found` in Mac log | `MOBILE_USE_CMD` wrong or `uv` not on PATH | `which mobile-use && pipx install minitap-mobile-use` |
| Phone says "No Mac paired" | Token mismatch or wrong IP | Re-scan QR; confirm `ifconfig en0` matches |
| `urlSession ... -1004` on phone | Mac not reachable | Same Wi-Fi? Firewall on Mac blocking 8731? |
| Live Activity never appears | Activities disabled | Settings → Cactus Voice → Live Activities ON |
| Gemma model fails to load | <6 GB RAM device | Switch picker to Qwen, or run on iPhone 15 Pro+ |
| Whisper transcript is empty | Mic muted / silent room | Check input level: tap mic in app, the partial chip should show text within ~1 s |

## Re-pairing / token rotation

```bash
# Mac
rm .env
uv run cactus-voice-mac --pair    # writes a fresh token, prints new QR
```

```
# iOS
Settings → Unpair → scan new QR
```
