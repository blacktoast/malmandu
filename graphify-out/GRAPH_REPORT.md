# Graph Report - /Users/eom-yunseong/orca/workspaces/malmandu/eagleray  (2026-07-30)

## Corpus Check
- 58 files · ~181,460 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 483 nodes · 943 edges · 21 communities detected
- Extraction: 70% EXTRACTED · 30% INFERRED · 0% AMBIGUOUS · INFERRED: 280 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]

## God Nodes (most connected - your core abstractions)
1. `Data` - 26 edges
2. `AppState` - 25 edges
3. `RecordingCoordinatorTests` - 24 edges
4. `SonioxRealtimeClient` - 24 edges
5. `AudioRecorder` - 20 edges
6. `GroqAPIClient` - 16 edges
7. `RecordingCoordinator` - 15 edges
8. `MockStreamingSTTClient` - 14 edges
9. `AppError` - 13 edges
10. `FocusDetector` - 13 edges

## Surprising Connections (you probably didn't know these)
- `makeTranscriptionJSON()` --calls--> `Data`  [INFERRED]
  /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Tests/MalmanduCoreTests/GroqAPIClientTests.swift → /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Sources/MalmanduCore/Services/GroqAPIClient.swift
- `makeTemporaryAudioFile()` --calls--> `Data`  [INFERRED]
  /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Tests/MalmanduCoreTests/GroqAPIClientTests.swift → /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Sources/MalmanduCore/Services/GroqAPIClient.swift
- `readBody()` --calls--> `Data`  [INFERRED]
  /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Tests/MalmanduCoreTests/GroqAPIClientTests.swift → /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Sources/MalmanduCore/Services/GroqAPIClient.swift

## Communities

### Community 0 - "Community 0"
Cohesion: 0.04
Nodes (42): AccessibilityServiceProtocol, AppError, accessibilityPermissionDenied, apiKeyInvalid, apiKeyMissing, fileTooLarge, microphonePermissionDenied, AppStatus (+34 more)

### Community 1 - "Community 1"
Cohesion: 0.05
Nodes (33): ActionButtonsPillView, PressablePillButtonStyle, ButtonStyle, Layout, ManduIconGroupView, MenuBarView, PreferenceKey, RecordingOverlayView (+25 more)

### Community 2 - "Community 2"
Cohesion: 0.08
Nodes (6): AppDomainContext, FocusDetector, RecordingCoordinator, SonioxRealtimeClient, String, TextInjector

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (15): AccessibilityService, AccessibilityServiceProtocol, App, ClickThroughHostingView, AppDelegate, KeyboardShortcuts.Name, MalmanduApp, NSApplicationDelegate (+7 more)

### Community 4 - "Community 4"
Cohesion: 0.14
Nodes (3): MockStreamingSTTClient, RecordingCoordinatorTests, StreamingSTTServiceProtocol

### Community 5 - "Community 5"
Cohesion: 0.19
Nodes (11): networkError, transcriptionFailed, Data, GroqAPIClient, GroqAPIClientTests, makeHTTPResponse(), makeMockSession(), makeTemporaryAudioFile() (+3 more)

### Community 6 - "Community 6"
Cohesion: 0.15
Nodes (8): recordingFailed, KeychainService, KeychainServiceProtocol, KeychainServiceTests, UnifiedShortcutRecorderField, Key, toggleRecording, APIModelPane

### Community 7 - "Community 7"
Cohesion: 0.14
Nodes (3): AudioRecorder, SystemVolumeDucker, SystemVolumeDuckerTests

### Community 8 - "Community 8"
Cohesion: 0.17
Nodes (3): AppState, AppStatePartialTests, AppStateTests

### Community 9 - "Community 9"
Cohesion: 0.13
Nodes (3): DefaultSTTProviderFactory, STTProviderFactory, STTProviderTests

### Community 10 - "Community 10"
Cohesion: 0.11
Nodes (7): AudioProcessor, AudioProcessorProtocol, AudioRecorderProtocol, MockAudioProcessor, MockAudioRecorder, MockTextInjector, TextInjectorProtocol

### Community 11 - "Community 11"
Cohesion: 0.14
Nodes (6): UnifiedRecorderNSView, UnifiedRecorderRepresentable, ModifierOnlyShortcut, ModifierOnlyShortcutStore, NSView, NSViewRepresentable

### Community 12 - "Community 12"
Cohesion: 0.19
Nodes (4): MockSoundService, SoundService, SoundServiceProtocol, SoundServiceTests

### Community 13 - "Community 13"
Cohesion: 0.21
Nodes (5): DynamicSTTClient, DynamicSTTClientTests, GroqAPIClientProtocol, MockGroqAPIClient, STTServiceProtocol

### Community 14 - "Community 14"
Cohesion: 0.32
Nodes (2): TextPolisher, TextPolisherTests

### Community 15 - "Community 15"
Cohesion: 0.23
Nodes (8): Codable, TranscriptionResponse, RTToken, RTTranscriptionResponse, FileUploadResponse, TranscriptionCreateResponse, TranscriptionStatusResponse, TranscriptResponse

### Community 16 - "Community 16"
Cohesion: 0.18
Nodes (5): Shape, SpeechBubbleBackground, View, SpeechBubbleShape, ViewModifier

### Community 17 - "Community 17"
Cohesion: 1.0
Nodes (1): Color

### Community 18 - "Community 18"
Cohesion: 1.0
Nodes (1): AudioConstants

### Community 19 - "Community 19"
Cohesion: 1.0
Nodes (0): 

### Community 20 - "Community 20"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **24 isolated node(s):** `SettingsTheme`, `general`, `apiModel`, `preferences`, `KeyboardShortcuts.Name` (+19 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 17`** (2 nodes): `Color`, `Color+Theme.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 18`** (2 nodes): `AudioConstants`, `AudioConstants.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 19`** (1 nodes): `Package.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 20`** (1 nodes): `cask-template.rb`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `APIModelPane` connect `Community 6` to `Community 1`, `Community 9`?**
  _High betweenness centrality (0.103) - this node is a cross-community bridge._
- **Why does `KeychainService` connect `Community 6` to `Community 0`, `Community 9`?**
  _High betweenness centrality (0.093) - this node is a cross-community bridge._
- **Why does `AppState` connect `Community 8` to `Community 0`, `Community 2`, `Community 4`, `Community 7`?**
  _High betweenness centrality (0.090) - this node is a cross-community bridge._
- **Are the 22 inferred relationships involving `Data` (e.g. with `makeTranscriptionJSON()` and `makeTemporaryAudioFile()`) actually correct?**
  _`Data` has 22 INFERRED edges - model-reasoned connections that need verification._
- **Are the 16 inferred relationships involving `AppState` (e.g. with `.makeSUT()` and `.initialState()`) actually correct?**
  _`AppState` has 16 INFERRED edges - model-reasoned connections that need verification._
- **What connects `SettingsTheme`, `general`, `apiModel` to the rest of the system?**
  _24 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.04 - nodes in this community are weakly interconnected._