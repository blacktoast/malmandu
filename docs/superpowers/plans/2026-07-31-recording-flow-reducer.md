---
title: Recording Flow Reducer Implementation Plan
created: 2026-07-31
modified:
  - 2026-07-31
---

# Recording Flow Reducer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make recording lifecycle, focus state, pending text, and overlay presentation one reducer-owned flow so focus-loss controls cannot outlive recording.

**Architecture:** `AppState` owns one `RecordingFlowState` and mutates it only through `send(_:)`. `RecordingCoordinator` dispatches actions, executes returned effects with the existing audio/STT/focus/text services, and dispatches their results. SwiftUI renders one derived `RecordingOverlayPresentation`.

**Tech Stack:** Swift 6, Observation, SwiftUI, AppKit, Swift Testing, Swift Package Manager

## Global Constraints

- Limit changes to recording, focus, pending transcription, and recording overlay behavior.
- Add no dependency, generic store, middleware, protocol, or unrelated abstraction.
- Preserve focus-safe buffering, pending-text order, cancellation discard behavior, and final segments emitted by `finishStreaming()`.
- Keep shortcut capture and persistence unchanged.
- Use RED → GREEN for each behavior change.

---

### Task 1: Lock the reducer transition contract

**Files:**
- Modify: `Tests/MalmanduCoreTests/AppStateTests.swift`
- Modify: `Tests/MalmanduCoreTests/AppStatePartialTests.swift`
- Modify: `Sources/MalmanduCore/Models/AppState.swift`

**Interfaces:**

```swift
enum RecordingFlowState {
    case idle
    case starting(RecordingSession)
    case recording(RecordingSession)
    case stopping(RecordingSession, RecordingStopMode)
    case transcribing(RecordingSession)
    case failed(RecordingFailure)
}

enum RecordingAction {
    case toggleRequested(targetBundleIdentifier: String?, targetName: String?)
    case cancelRequested
    case retryRequested(targetBundleIdentifier: String?, targetName: String?)
    case startSucceeded(sessionID: UUID)
    case startFailed(sessionID: UUID, AppError)
    case captureStopped(sessionID: UUID, URL)
    case captureUnavailable(sessionID: UUID)
    case captureStopFailed(sessionID: UUID, AppError)
    case cancelCompleted(sessionID: UUID)
    case focusChanged(sessionID: UUID, isTargetActive: Bool)
    case partialUpdated(sessionID: UUID, text: String?)
    case audioLevelsUpdated(sessionID: UUID, levels: [CGFloat])
    case segmentFinalized(sessionID: UUID, text: String, isTargetActive: Bool)
    case segmentDeliveryFailed(sessionID: UUID, text: String)
    case pastePendingRequested(isTargetActive: Bool)
    case pendingPasteSucceeded(sessionID: UUID, text: String)
    case pendingPasteFailed(sessionID: UUID)
    case transcriptionSucceeded(sessionID: UUID)
    case transcriptionFailed(sessionID: UUID, AppError, audioURL: URL?)
}

enum RecordingEffect {
    case startCapture(sessionID: UUID)
    case stopCapture(sessionID: UUID)
    case cancelCapture(sessionID: UUID)
    case finishTranscription(sessionID: UUID, URL)
    case retryTranscription(sessionID: UUID, URL)
    case pasteSegment(sessionID: UUID, text: String)
    case pastePending(sessionID: UUID, text: String)
}
```

- [x] **Step 1: Replace mutable-field tests with reducer transition tests**

Cover `idle → starting → recording`, stop during `starting`, `recording → stopping → transcribing → idle`, repeated stop/cancel no-ops, focus projection, pending-paste prefix removal, late final segments in finish states, and discard-state rejection.

- [x] **Step 2: Run the reducer tests and verify RED**

Run: `swift test --filter AppState`

Expected: compile/test failure because the reducer types and `AppState.send(_:)` do not exist.

- [x] **Step 3: Add the minimal state, action, effect, and reducer**

Store only `flowState`. Expose the existing read APIs (`status`, error/audio URL, recording time, partial/pending text, app name, focus flags, audio levels) as computed values. Derive `RecordingOverlayPresentation` in one switch.

- [x] **Step 4: Run the reducer tests and verify GREEN**

Run: `swift test --filter AppState`

Expected: all reducer tests pass.

---

### Task 2: Reproduce the focus-loss stop regression

**Files:**
- Modify: `Tests/MalmanduCoreTests/RecordingCoordinatorFocusBufferTests.swift`

- [x] **Step 1: Add the failing integration test**

Start real-time recording, move focus away, stop in a child task, and assert:

```swift
#expect(appState.overlayPresentation == .transcribing)
```

while `finishStreaming()` is suspended. Complete transcription, invoke the shortcut entry point again, and assert recording restarts.

- [x] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter RecordingCoordinatorFocusBufferTests`

Expected: failure because the coordinator still writes independent flags and the overlay projection is not reducer-owned.

---

### Task 3: Route coordinator callbacks through the reducer

**Files:**
- Modify: `Sources/MalmanduCore/Services/RecordingCoordinator.swift`
- Modify: `Tests/MalmanduCoreTests/RecordingCoordinatorTests.swift`
- Test: `Tests/MalmanduCoreTests/RecordingCoordinatorFocusBufferTests.swift`

- [x] **Step 1: Add one coordinator dispatch/effect loop**

`dispatch(_:)` calls `appState.send(_:)`, reports derived status changes through `onStatusChange`, then executes each returned effect sequentially.

- [x] **Step 2: Convert public intents**

Route toggle, cancel, retry, focus change, and pending paste through actions. Repeated intents in `stopping`/`transcribing` must return no effect.

- [x] **Step 3: Convert asynchronous callbacks**

Route start/stop/transcription results, partial text, audio levels, finalized segments, and pending-paste results through actions. Keep only resource cleanup flags inside the coordinator.

- [x] **Step 4: Preserve initialization-stop behavior**

If stop/cancel arrives before capture starts, keep the flow in `stopping` until the in-flight start effect observes it and dispatches `captureUnavailable` or `cancelCompleted`. If streaming connection is initializing, close it before completion.

- [x] **Step 5: Run coordinator tests and verify GREEN**

Run:

```bash
swift test --filter RecordingCoordinatorTests
swift test --filter RecordingCoordinatorFocusBufferTests
```

Expected: both suites pass, including focus loss → stop → progress → completion → restart.

---

### Task 4: Render only the reducer projection

**Files:**
- Modify: `Sources/MalmanduCore/Overlay/RecordingOverlayView.swift`
- Modify: `Sources/MalmanduCore/Overlay/OverlayRootView.swift`
- Modify: `Tests/MalmanduCoreTests/RecordingOverlayViewLayoutTests.swift`

- [x] **Step 1: Update overlay test setup**

Build recording/pending states through reducer actions instead of direct property writes, and assert stopping/transcribing uses the progress projection.

- [x] **Step 2: Switch on `overlayPresentation`**

Render focus-loss and pending-paste controls only for recording focus projections. Keep the selected RT/async chrome stable through `starting` and `transcribing`; reducer no-ops keep terminal transitions non-interactive without swapping to the other mode's UI.

- [x] **Step 3: Run overlay tests**

Run: `swift test --filter RecordingOverlayViewLayoutTests`

Expected: pass with the panel fixed at `280×200`.

- [x] **Step 4: Lock RT transition chrome**

Verify `starting → recording → transcribing` continues to project the RT chrome so insertion/removal uses the existing blur transition without flashing the async card.

---

### Task 5: Verify the bounded migration

**Files:**
- Verify only

- [x] **Step 1: Prove there are no production direct writes**

Run:

```bash
rg -n "appState\.(status|focusLost|isAwaitingPendingPaste|partialTranscription|pendingCopyText|startingAppName|audioLevels)\s*=" Sources
```

Expected: no matches.

- [x] **Step 2: Run full validation**

Run:

```bash
swift test
swift build -c release
graphify update .
git diff --check
```

Expected: all commands exit successfully.

- [x] **Step 3: Review scope**

Confirm the diff adds no dependency or generic Redux infrastructure and changes only the approved flow, its overlay projection, tests, and plan.
