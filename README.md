# Malmandu (말만두)

> [한국어 README](docs/README.ko.md)

A macOS menu bar voice-to-text tool. Press a global shortcut to start recording, press again to transcribe the audio via an STT API and automatically paste it into the focused text field.

**Supported STT providers:** Groq Whisper, Soniox (async + realtime WebSocket)

## System requirements

- macOS 15.0 or later
- Swift 6.0 or later (Xcode 16+)
- An STT API key:
  - [Groq API key](https://console.groq.com) (free tier available)
  - [Soniox API key](https://console.soniox.com) (optional)

## Build and run

```bash
# Build
swift build

# Run tests (44 tests)
swift test

# Run directly from terminal
swift build && .build/debug/Malmandu

# Run as a wrapped .app bundle (recommended — ensures the menu bar icon appears)
./scripts/run.sh

# Open in Xcode
open Package.swift
```

> **Note:** `swift run Malmandu` works, but because it isn't wrapped in a `.app` bundle the menu bar icon may not appear. `scripts/run.sh` builds and wraps the binary automatically.

## API key setup

### Groq

1. Create an account at [console.groq.com](https://console.groq.com) and generate an API key
2. Launch the app → click the menu bar icon → **Settings...**
3. In the **API** tab, choose **Groq** under **Service provider**
4. Paste the API key → click **Test connection** to verify

### Soniox

1. Create an account at [console.soniox.com](https://console.soniox.com) and generate an API key
2. In the **API** tab, choose **Soniox** under **Service provider**
3. Paste the API key → click **Test connection**
4. Select a model from the **STT model** dropdown

API keys are stored securely in the macOS Keychain, namespaced per provider.

## STT models

| Provider | Model | Mode | Notes |
|---|---|---|---|
| Groq | `whisper-large-v3` | Sync REST | Accuracy-first (default) |
| Groq | `whisper-large-v3-turbo` | Sync REST | Speed-first |
| Soniox | `stt-rt-v4` | Realtime WebSocket | Live transcription (default) |
| Soniox | `stt-async-v4` | Async REST | Upload + poll |
| Soniox | `stt-async-v3` | Async REST | Legacy |

## Keyboard shortcuts

| Action | Default shortcut |
|---|---|
| Start / stop recording | `⌥ + ⌃ + Space` (Option+Control+Space) |
| Start / stop recording (alternate) | `Fn` key |

Remap under Settings → **Recording**.

## Usage

1. Focus the text field where you want text inserted
2. Press `⌥ + ⌃ + Space` or `Fn` to start recording (menu bar icon switches to a filled microphone)
3. Speak
4. Press the same shortcut again to stop
5. The selected STT provider transcribes the audio and auto-pastes the result

## System permissions

The app requests two permissions on first run.

### Microphone

**System Settings → Privacy & Security → Microphone** — enable Malmandu.

### Accessibility

Required for automatic text pasting.

**System Settings → Privacy & Security → Accessibility** — enable Malmandu.

> Without Accessibility, transcription still works but auto-paste does not.

## Settings

| Tab | Item | Description |
|---|---|---|
| API | Service provider | Choose Groq or Soniox |
| API | API key | Auth key for the selected provider (Keychain) |
| API | STT model | Provider-specific model selection |
| API | Test connection | Validate API key |
| Recording | Recording shortcut | Customize the global shortcut |
| Recording | Default language | Korean, English, 日本語, 中文, Español, Français, Deutsch |
| General | Sound effects | Toggle start/stop sound cues |

## Project structure

```
Sources/
├── MalmanduCore/          # Core business logic (testable)
│   ├── Models/
│   │   └── AppState.swift  # App state (@Observable)
│   ├── Services/
│   │   ├── STTServiceProtocol.swift      # STT protocol + STTProvider enum
│   │   ├── DynamicSTTClient.swift        # Runtime provider switch proxy
│   │   ├── GroqAPIClient.swift           # Groq Whisper API client
│   │   ├── SonioxSTTClient.swift         # Soniox async REST client
│   │   ├── SonioxRealtimeClient.swift    # Soniox realtime WebSocket client
│   │   ├── RecordingCoordinator.swift    # Record → STT → paste pipeline
│   │   ├── AudioRecorder.swift           # AVFoundation mic capture
│   │   ├── AudioProcessor.swift          # FluidAudio VAD silence removal
│   │   ├── KeychainService.swift         # API key Keychain storage
│   │   ├── TextInjector.swift            # Accessibility-based text paste
│   │   └── SoundService.swift            # Sound effects
│   └── Overlay/
│       ├── OverlayPanel.swift            # Transparent NSPanel
│       ├── OverlayManager.swift          # Overlay lifecycle
│       └── OverlayContentView.swift      # State-driven SwiftUI views
└── Malmandu/
    └── MalmanduApp.swift  # Entry point, menu bar, settings UI

Tests/
└── MalmanduCoreTests/     # 44 unit tests
```

## Architecture

```
┌─────────────────┐   ┌──────────────────┐   ┌─────────────────────┐
│  AudioRecorder  │──>│  AudioProcessor  │──>│ STTServiceProtocol  │
│  (mic capture)  │   │  (VAD silence)   │   │  (speech → text)    │
└─────────────────┘   └──────────────────┘   └──────────┬──────────┘
                                                        │
                         ┌──────────────────────────────┤
                         │         DynamicSTTClient     │
                         │        (runtime routing)     │
                         ├────────────┬─────────────────┤
                         │            │                 │
                   GroqAPIClient  SonioxSTT      SonioxRealtime
                   (sync REST)   (async REST)    (WebSocket)
```

## Tech stack

- **Swift 6** + Swift Concurrency (async/await, actor)
- **SwiftUI** — menu bar, settings, overlay
- **AVFoundation** — mic capture (M4A)
- **URLSession WebSocket** — Soniox realtime streaming
- **Groq Whisper API** — speech → text
- **Soniox API** — async REST + realtime WebSocket STT
- **FluidAudio** — Silero VAD silence removal
- **Security framework** — Keychain API key storage
- **KeyboardShortcuts** — global shortcuts
- **Swift Testing** — unit tests (`@Test`, `#expect`)
