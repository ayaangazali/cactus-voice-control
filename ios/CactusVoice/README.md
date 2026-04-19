# CactusVoice iOS

SwiftUI app that captures voice via Action Button, transcribes + reasons on-device with [cactus-compute/cactus](https://github.com/cactus-compute/cactus), and ships a JSON intent to the paired Mac gateway.

## Build

```bash
brew install xcodegen cactus-compute/cactus/cactus
./scripts/fetch_cactus.sh        # vendors cactus-ios.xcframework + Cactus.swift
xcodegen generate
open CactusVoice.xcodeproj
```

In Xcode:
1. Set Signing Team on **CactusVoice** and **CactusVoiceWidget** targets.
2. Run on a physical device (iPhone 15 Pro+ for full Action Button + Live Activity flow).
3. Grant microphone + Local Network permissions on first launch.
4. **Settings → Action Button → Shortcut → Start Cactus listening** to bind the button.

## Targets

| Target | Bundle ID | Purpose |
| --- | --- | --- |
| CactusVoice | `com.ayaangazali.cactusvoice` | Main app |
| CactusVoiceWidget | `com.ayaangazali.cactusvoice.widget` | Live Activity (Lock Screen + Dynamic Island) |
| CactusVoiceTests | `com.ayaangazali.cactusvoice.tests` | XCTest unit tests for downloader / VAD / intent / pairing |

## Tests

```bash
xcodebuild test -scheme CactusVoice -destination "platform=iOS Simulator,name=iPhone 15 Pro"
```

## Re-fetch cactus on a new release

```bash
./scripts/fetch_cactus.sh --pin v0.4.0
```
