# Overlay Actions and Focus Buffer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore X/✓ overlay actions and buffer real-time transcription across focus loss until the user explicitly pastes it.

**Architecture:** Preserve the current `AppState` and `RecordingCoordinator` ownership model. Restore native AppKit hit testing, add one pending-paste state flag, and route finalized transcription through the coordinator so text is either delivered to the original app or retained in order.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, Swift Package Manager

## Global Constraints

- Do not add dependencies.
- Do not paste transcription into an application other than the one active when recording began.
- X must remain destructive and ✓ must preserve every not-yet-delivered phrase.
- Pending paste must not stop the active recording.
- Preserve the uncommitted crash fix already present in `RecordingCoordinator.swift`, `Mocks.swift`, and `RecordingOverlayViewLayoutTests.swift`.

---

### Task 1: Restore overlay button hit testing

**Files:**
- Create: `Tests/MalmanduCoreTests/OverlayInteractionTests.swift`
- Modify: `Sources/MalmanduCore/Overlay/ClickThroughHostingView.swift`

**Interfaces:**
- Consumes: `ClickThroughHostingView.init(rootView:)`
- Produces: native `NSHostingView.hitTest(_:)` behavior for SwiftUI controls

- [ ] **Step 1: Write the failing test**

Create a fixed-size hosting view containing a SwiftUI `Button`, lay it out, and assert that `hitTest(_:)` at its center is not `nil`.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter OverlayInteractionTests`

Expected: FAIL because the current override converts the hosting view hit into `nil`.

- [ ] **Step 3: Apply the minimal implementation**

Remove the custom `hitTest(_:)` and diagnostic `mouseDown(with:)` overrides. Keep `acceptsFirstMouse(for:)` so a non-activating panel accepts the first click.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `swift test --filter OverlayInteractionTests`

Expected: PASS.

---

### Task 2: Preserve streaming text through focus loss

**Files:**
- Create: `Tests/MalmanduCoreTests/RecordingCoordinatorFocusBufferTests.swift`
- Modify: `Sources/MalmanduCore/Models/AppState.swift`
- Modify: `Sources/MalmanduCore/Services/RecordingCoordinator.swift`
- Modify: `Tests/MalmanduCoreTests/Mocks.swift`

**Interfaces:**
- Consumes: streaming partial/final callbacks and application activation changes
- Produces: `AppState.isAwaitingPendingPaste`, `RecordingCoordinator.pastePendingTranscription()`, and one testable coordinator focus-transition entry point

- [ ] **Step 1: Write failing coordinator tests**

Cover these behaviors independently:

```swift
#expect(appState.pendingCopyText == "포커스 밖 문장")
#expect(appState.isAwaitingPendingPaste == true)
#expect(textInjector.lastPastedText == "포커스 밖 문장")
#expect(appState.status == .recording)
#expect(textInjector.lastPastedText == "대기 문장마지막 문장")
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter RecordingCoordinatorFocusBufferTests`

Expected: FAIL because focus loss pauses streaming and no pending-paste transition/API exists.

- [ ] **Step 3: Add the minimum state and transitions**

Add `isAwaitingPendingPaste` to `AppState`, reset it with the other recording state, stop calling `pauseStreaming()`/`resumeStreaming()`, and route finalized segments to `pendingCopyText` whenever focus is lost or pending paste awaits confirmation.

- [ ] **Step 4: Add pending paste delivery**

Implement `pastePendingTranscription()` so success clears the pending buffer and prompt while leaving `.recording`; permission failure retains the buffer and reports the existing accessibility error.

- [ ] **Step 5: Preserve pending text on ✓**

In the real-time finish path, concatenate `pendingCopyText` before `finishStreaming()`'s remaining text and paste the combined value once before completing.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run: `swift test --filter RecordingCoordinatorFocusBufferTests`

Expected: PASS.

---

### Task 3: Expose the pending-paste action in the overlay

**Files:**
- Modify: `Sources/MalmanduCore/Overlay/RecordingOverlayView.swift`
- Modify: `Sources/MalmanduCore/Overlay/OverlayRootView.swift`
- Modify: `Sources/MalmanduCore/Overlay/OverlayManager.swift`
- Modify: `Sources/Malmandu/MalmanduApp.swift`
- Test: `Tests/MalmanduCoreTests/RecordingOverlayViewLayoutTests.swift`

**Interfaces:**
- Consumes: `AppState.isAwaitingPendingPaste` and `RecordingCoordinator.pastePendingTranscription()`
- Produces: `onPastePending` callback from the SwiftUI button to the app coordinator

- [ ] **Step 1: Extend the overlay regression test**

Render the real overlay with pending text and assert the panel remains fixed at `280×200` without animated transcript constraints.

- [ ] **Step 2: Run the focused layout test and verify RED**

Run: `swift test --filter RecordingOverlayViewLayoutTests`

Expected: FAIL because the pending-paste branch does not exist.

- [ ] **Step 3: Wire the callback**

Pass `onPastePending` through `OverlayManager` → `OverlayRootView` → `RecordingOverlayView`; bind it in `MalmanduApp` to `coordinator.pastePendingTranscription()`.

- [ ] **Step 4: Add the pending-paste branch**

Display buffered text, “붙여넣기”, and the existing action pill. Keep the panel and existing design tokens.

- [ ] **Step 5: Run the focused layout test and verify GREEN**

Run: `swift test --filter RecordingOverlayViewLayoutTests`

Expected: PASS.

---

### Task 4: Integration verification

**Files:**
- Verify only

**Interfaces:**
- Consumes: Tasks 1–3
- Produces: completion evidence

- [ ] **Step 1: Run all tests**

Run: `swift test`

Expected: all suites pass with zero failures.

- [ ] **Step 2: Build release**

Run: `swift build -c release`

Expected: exit code 0.

- [ ] **Step 3: Run the packaged app interaction smoke test**

Verify X dismisses without paste, ✓ pastes and dismisses, focus-away speech accumulates, return shows “붙여넣을까요?”, and pending paste keeps recording active.

- [ ] **Step 4: Review the diff**

Run: `git diff --check`

Expected: no whitespace errors and no unrelated changes.
