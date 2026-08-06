# Graph Report - /Users/eom-yunseong/orca/workspaces/malmandu/dace  (2026-07-31)

## Corpus Check
- 62 files · ~201,587 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 620 nodes · 1339 edges · 23 communities detected
- Extraction: 70% EXTRACTED · 30% INFERRED · 0% AMBIGUOUS · INFERRED: 406 edges (avg confidence: 0.8)
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
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]

## God Nodes (most connected - your core abstractions)
1. `RecordingCoordinator` - 29 edges
2. `RecordingCoordinatorTests` - 28 edges
3. `Data` - 26 edges
4. `SonioxRealtimeClient` - 24 edges
5. `RecordingAction` - 23 edges
6. `UnifiedRecorderNSView` - 20 edges
7. `AppState` - 20 edges
8. `AudioRecorder` - 20 edges
9. `MockStreamingSTTClient` - 17 edges
10. `RecordingCoordinatorFocusBufferTests` - 16 edges

## Surprising Connections (you probably didn't know these)
- `makeTranscriptionJSON()` --calls--> `Data`  [INFERRED]
  /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Tests/MalmanduCoreTests/GroqAPIClientTests.swift → /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Sources/MalmanduCore/Services/GroqAPIClient.swift
- `makeTemporaryAudioFile()` --calls--> `Data`  [INFERRED]
  /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Tests/MalmanduCoreTests/GroqAPIClientTests.swift → /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Sources/MalmanduCore/Services/GroqAPIClient.swift
- `readBody()` --calls--> `Data`  [INFERRED]
  /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Tests/MalmanduCoreTests/GroqAPIClientTests.swift → /Users/eom-yunseong/orca/workspaces/malmandu/eagleray/Sources/MalmanduCore/Services/GroqAPIClient.swift

## Communities

### Community 0 - "Community 0"
Cohesion: 0.03
Nodes (79): AccessibilityServiceProtocol, AppError, accessibilityPermissionDenied, apiKeyInvalid, apiKeyMissing, fileTooLarge, microphonePermissionDenied, AppStatus (+71 more)

### Community 1 - "Community 1"
Cohesion: 0.08
Nodes (7): recordingFailed, AudioRecorder, AppDomainContext, FocusDetector, RecordingCoordinator, TextInjector, TextInjectorProtocol

### Community 2 - "Community 2"
Cohesion: 0.05
Nodes (17): AccessibilityService, AccessibilityServiceProtocol, App, AppDelegate, KeyboardShortcuts.Name, MalmanduApp, SpaceShortcutPollState, ModifierOnlyShortcut (+9 more)

### Community 3 - "Community 3"
Cohesion: 0.12
Nodes (14): networkError, transcriptionFailed, transcriptionFailed, Data, GroqAPIClient, GroqAPIClientTests, makeHTTPResponse(), makeMockSession() (+6 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (30): ActionButtonsPillView, PressablePillButtonStyle, ButtonStyle, Layout, ManduIconGroupView, MenuBarView, APIKeyField, Color (+22 more)

### Community 5 - "Community 5"
Cohesion: 0.09
Nodes (11): AudioRecorderProtocol, MockAudioProcessor, MockAudioRecorder, MockSoundService, MockTextInjector, FocusBufferStreamingClient, MutableFocusProvider, RecordingCoordinatorFocusBufferTests (+3 more)

### Community 6 - "Community 6"
Cohesion: 0.13
Nodes (3): MockStreamingSTTClient, CoordinatorFocusProvider, RecordingCoordinatorTests

### Community 7 - "Community 7"
Cohesion: 0.11
Nodes (8): AppState, AppStatePartialTests, AppStateTests, ClickThroughHostingView, NSHostingView<Content>, OverlayInteractionTests, RecordingOverlayView, RecordingOverlayViewLayoutTests

### Community 8 - "Community 8"
Cohesion: 0.07
Nodes (15): CaseIterable, Identifiable, SettingsSection, apiModel, general, preferences, DefaultSTTProviderFactory, STTProviderFactory (+7 more)

### Community 9 - "Community 9"
Cohesion: 0.13
Nodes (9): KeychainService, KeychainServiceProtocol, KeychainServiceTests, UnifiedRecorderRepresentable, UnifiedShortcutRecorderField, Key, toggleRecording, NSViewRepresentable (+1 more)

### Community 10 - "Community 10"
Cohesion: 0.22
Nodes (3): UnifiedRecorderNSView, NSView, UnifiedRecorderNSViewTests

### Community 11 - "Community 11"
Cohesion: 0.13
Nodes (10): SystemVolumeDucker, PreferenceKey, RecordingOverlayChrome, async, focusLost, hidden, pendingPaste, realtime (+2 more)

### Community 12 - "Community 12"
Cohesion: 0.21
Nodes (5): DynamicSTTClient, DynamicSTTClientTests, GroqAPIClientProtocol, MockGroqAPIClient, STTServiceProtocol

### Community 13 - "Community 13"
Cohesion: 0.26
Nodes (2): SoundService, SoundServiceTests

### Community 14 - "Community 14"
Cohesion: 0.23
Nodes (8): Codable, TranscriptionResponse, RTToken, RTTranscriptionResponse, FileUploadResponse, TranscriptionCreateResponse, TranscriptionStatusResponse, TranscriptResponse

### Community 15 - "Community 15"
Cohesion: 0.32
Nodes (2): TextPolisher, TextPolisherTests

### Community 16 - "Community 16"
Cohesion: 0.18
Nodes (5): Shape, SpeechBubbleBackground, View, SpeechBubbleShape, ViewModifier

### Community 17 - "Community 17"
Cohesion: 0.4
Nodes (2): MockURLProtocol, URLProtocol

### Community 18 - "Community 18"
Cohesion: 0.4
Nodes (2): AudioProcessor, AudioProcessorProtocol

### Community 19 - "Community 19"
Cohesion: 1.0
Nodes (1): Color

### Community 20 - "Community 20"
Cohesion: 1.0
Nodes (1): AudioConstants

### Community 21 - "Community 21"
Cohesion: 1.0
Nodes (0): 

### Community 22 - "Community 22"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **71 isolated node(s):** `SettingsTheme`, `general`, `apiModel`, `preferences`, `KeyboardShortcuts.Name` (+66 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 19`** (2 nodes): `Color`, `Color+Theme.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 20`** (2 nodes): `AudioConstants`, `AudioConstants.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 21`** (1 nodes): `Package.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 22`** (1 nodes): `cask-template.rb`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ModifierOnlyShortcut` connect `Community 2` to `Community 0`, `Community 14`?**
  _High betweenness centrality (0.072) - this node is a cross-community bridge._
- **Why does `AppState` connect `Community 7` to `Community 0`, `Community 5`, `Community 6`?**
  _High betweenness centrality (0.071) - this node is a cross-community bridge._
- **Why does `RecordingCoordinator` connect `Community 1` to `Community 0`, `Community 8`, `Community 5`, `Community 6`?**
  _High betweenness centrality (0.067) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `RecordingCoordinator` (e.g. with `.makeSUT()` and `.multilineRealtimeText()`) actually correct?**
  _`RecordingCoordinator` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `Data` (e.g. with `makeTranscriptionJSON()` and `makeTemporaryAudioFile()`) actually correct?**
  _`Data` has 22 INFERRED edges - model-reasoned connections that need verification._
- **What connects `SettingsTheme`, `general`, `apiModel` to the rest of the system?**
  _71 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.03 - nodes in this community are weakly interconnected._