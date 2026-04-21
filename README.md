# Wooly

Hold Action Button on iPhone 15 Pro+ → speak → Mac drives iOS Simulator with [`mobile-use`](https://github.com/minitap-ai/mobile-use).

```
┌─────────────┐  voice   ┌──────────────┐  HTTP+SSE  ┌──────────────┐  idb  ┌────────────────┐
│ Action Btn  │─────────▶│ Cactus iOS   │───────────▶│ Mac FastAPI  │──────▶│ iOS Simulator  │
│ (iPhone)    │          │ Whisper+Qwen │            │ + mobile-use │       │ (target app)   │
└─────────────┘          └──────────────┘            └──────────────┘       └────────────────┘
```

## On-device pipeline (iPhone, no cloud)

1. AppIntent fires from Action Button → app foregrounds, recording starts.
2. AVAudioEngine 16 kHz mono PCM → `cactusStreamTranscribeProcess` (Whisper-base GGUF).
3. RMS silence gate stops recording → final transcript.
4. Qwen3-1.7B (or Gemma 3 4B) normalizes transcript → JSON intent `{ instruction, output_description?, urgency }`.
5. POST intent to paired Mac over local Wi-Fi (Bearer auth).
6. SSE stream brings status back, surfaced via Live Activity.

## Mac side

7. FastAPI accepts intent, spawns [`mobile-use`](https://github.com/minitap-ai/mobile-use) via `uv run`.
8. `mobile-use` drives iOS Simulator via `idb` (or any paired iOS device).
9. Stdout streamed back over SSE → Lock Screen / Dynamic Island update.

## Repo layout

| Path | What |
| --- | --- |
| `ios/CactusVoice/` | Native SwiftUI app (Xcode 15+, iOS 17+) |
| `mac-server/` | Python FastAPI receiver wrapping `mobile-use` |
| `docs/` | ARCHITECTURE / PROTOCOL / SETUP |

## Quick start

See [`docs/SETUP.md`](docs/SETUP.md). Short version:

```bash
# Mac
brew install cactus-compute/cactus/cactus xcodegen idb-companion uv
cd mac-server && uv sync && uv run cactus-voice-mac --pair

# iOS app
cd ios/CactusVoice && ./scripts/fetch_cactus.sh && xcodegen generate
open CactusVoice.xcodeproj   # set signing team, build to device
```

Bind the **Start Cactus listening** Shortcut to the Action Button:
**Settings → Action Button → Shortcut → Start Cactus listening**.

## Status

Greenfield. iOS code targets a buildable XcodeGen project; physical-device verification (Action Button, mic, Live Activity) requires deploy to iPhone 15 Pro+. Mac server has pytest coverage for auth + runner subprocess wiring.


