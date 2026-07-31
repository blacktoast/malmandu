---
title: Recording Flow Reducer Design
created: 2026-07-31
modified: []
---

# Recording Flow Reducer Design

## Goal

Make recording, focus handling, and overlay presentation one deterministic flow:

```text
event -> action -> reducer -> state -> effect -> result action
```

The reducer is the only production writer of recording UI state. Existing audio, STT, focus, and text-injection services remain effect implementations.

## Problem

`AppStatus`, `focusLost`, `isAwaitingPendingPaste`, and pending text can currently change independently. The UI then chooses a branch using its own priority rules.

This permits contradictory states. For example:

1. Focus loss sets `focusLost = true`.
2. “종료” changes `status` to `transcribing` without clearing `focusLost`.
3. The overlay still renders the focus-loss recording controls because it checks `focusLost` first.
4. A shortcut reaches the coordinator but is ignored because toggles are disabled during transcription.

The shortcut monitor is still active; the rendered controls no longer describe the actual lifecycle state.

## Scope

Included:

- Shortcut, menu, and overlay recording intents
- Start, stop, cancel, transcription, retry, and completion transitions
- Original-app focus tracking
- Pending transcription buffering and paste confirmation
- Recording overlay presentation
- Errors produced by this flow

Excluded:

- Shortcut capture and persistence
- STT provider, model, language, and API-key settings
- Audio, STT, and text-injection implementation changes
- A generic Redux framework or external dependency
- Unrelated application settings and windows

## Architecture

`RecordingCoordinator` remains the effect runner and public event entry point. `AppState` stores a single `RecordingFlowState`. A small reducer converts `RecordingAction` values into a new state and zero or more `RecordingEffect` values.

```text
AppDelegate / MenuBar / Overlay / NSWorkspace / STT callback
                            |
                            v
                RecordingCoordinator.send(action)
                            |
                            v
                        reducer
                      /         \
                     v           v
           RecordingFlowState   effects
                     |           |
                     v           v
              overlay rendering  existing services
                                  |
                                  v
                             result action
```

There is no generic store, middleware, protocol, or dependency. The implementation reuses `RecordingCoordinator` and `AppState`.

## State Model

```swift
enum RecordingFlowState {
    case idle
    case starting(RecordingSession)
    case recording(RecordingSession)
    case stopping(RecordingSession, StopMode)
    case transcribing(RecordingSession)
    case failed(RecordingFailure)
}

enum StopMode {
    case finish
    case discard
}

enum RecordingFocus {
    case target
    case away
    case awaitingPaste
}
```

`RecordingSession` owns data that must live only for one active recording:

- Starting application bundle identifier and display name
- Focus state
- Partial transcription
- Pending transcription
- Audio levels

`RecordingFailure` owns the error and optional audio URL required for retry.

The old independently writable recording fields become derived read-only values or are removed after callers migrate. Active session data cannot survive in `idle`, and focus UI cannot be selected from `transcribing`.

## Actions

User and system inputs:

- `toggleRequested`
- `stopRequested`
- `cancelRequested`
- `retryRequested(targetBundleIdentifier:targetName:)`
- `focusChanged(isTargetActive:)`
- `pastePendingRequested`

Effect results:

- `startSucceeded`
- `startFailed(error:)`
- `captureStopped(audioURL:)`
- `cancelCompleted`
- `segmentFinalized(text:)`
- `partialUpdated(text:)`
- `audioLevelsUpdated(levels:)`
- `pendingPasteSucceeded(text:)`
- `pendingPasteFailed(error:)`
- `transcriptionSucceeded`
- `transcriptionFailed(error:audioURL:)`

Callbacks never mutate state directly. They dispatch a result action.

## Transition Rules

| Current state | Action | Next state | Effect |
| --- | --- | --- | --- |
| `idle`, `failed` | `toggleRequested` | `starting` | Start capture/stream |
| `starting`, `recording` | `toggleRequested`, `stopRequested` | `stopping(.finish)` | Stop capture |
| `starting`, `recording` | `cancelRequested` | `stopping(.discard)` | Discard capture/stream |
| `stopping(.finish)` | `captureStopped` | `transcribing` | Finish STT and deliver/copy text |
| `stopping(.discard)` | `cancelCompleted` | `idle` | None |
| `failed` with retry audio | `retryRequested` | `transcribing` | Retry transcription for the newly captured target app |
| `transcribing` | `transcriptionSucceeded` | `idle` | Remove temporary audio |
| Active state | Relevant failure | `failed` | Show existing error toast |
| `recording` | Focus/paste action | Updated `recording` session | Existing focus-safe effect |
| `recording`, `stopping(.finish)`, `transcribing` | `segmentFinalized` | Same phase with updated session | Deliver or buffer final text |
| `stopping`, `transcribing` | New toggle/stop/cancel | Unchanged | None |

The first stop action changes state before asynchronous cleanup begins. Repeated clicks and shortcut presses therefore cannot start a second stop pipeline.

Late callbacks are accepted only where meaningful:

- Final segments are accepted during `recording`, `stopping(.finish)`, and `transcribing`; `finishStreaming()` can emit its last segment after transcription has begun.
- Final segments are discarded during `stopping(.discard)`.
- Focus changes do not replace `stopping` or `transcribing` presentation.
- Results that do not match the current phase are ignored.

## Effects

Effects call the existing collaborators:

- `AudioRecorderProtocol`
- `StreamingSTTServiceProtocol`
- `STTServiceProtocol`
- `TextInjectorProtocol`
- `SoundServiceProtocol`
- `FocusDetector`
- `OverlayManager`

Resource-level flags needed to close an initializing stream safely may remain private to `RecordingCoordinator`; they cannot write UI state. Every visible outcome returns through an action.

The existing focus-safe delivery rules remain:

- Never paste into a different application.
- Buffer finalized text while focus is away.
- Recheck the frontmost application before pending paste.
- Preserve pending plus final text order during normal stop.
- Discard all pending and final callbacks during cancel.

## Overlay Projection

Overlay presentation is derived from `RecordingFlowState` in one switch:

- `idle`, `failed` -> hidden
- `starting` -> starting/progress presentation
- `recording(.target)` -> normal recording presentation
- `recording(.away)` -> focus-loss presentation
- `recording(.awaitingPaste)` -> pending-paste presentation
- `stopping`, `transcribing` -> non-interactive progress presentation

`RecordingOverlayView` no longer independently prioritizes lifecycle and focus booleans. The focus-loss “종료” button cannot remain visible after the reducer enters `stopping`.

## Error Handling

- Start and stop failures transition to `failed` after best-effort resource cleanup.
- Cancel cleanup remains best-effort and always finishes in `idle`.
- Transcription failures retain the retry audio URL.
- Retry captures the currently focused target application before entering `transcribing`.
- Accessibility failure keeps text in the clipboard/pending path and uses the existing toast.
- Stale asynchronous results cannot move an incompatible phase.
- No automatic retry or action queue is added.

## Verification

Add one reducer transition test table and focused integration coverage:

1. `idle -> starting -> recording`
2. Stop during `starting`
3. `recording -> stopping -> transcribing -> idle`
4. Focus loss followed by stop renders progress, not focus-loss controls
5. Shortcut during `stopping` or `transcribing` has no duplicate effect
6. Shortcut after completion starts a new recording
7. Repeated stop and cancel are idempotent
8. Pending text ordering and focus-safe copy behavior remain unchanged
9. Cancel discards late finalized segments
10. Failure and retry retain the current audio-file behavior

Existing coordinator, focus-buffer, overlay, and shortcut tests remain regression coverage.

## Stop Condition

The migration is complete when:

- Production code has one recording state writer: the reducer.
- All recording/focus callbacks dispatch actions.
- Overlay presentation is derived only from `RecordingFlowState`.
- The exact focus-loss/stop/shortcut regression passes.
- Existing tests, type checking/build, and static checks pass without a new dependency.
