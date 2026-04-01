# Connectakt — Codex Task Handoff

> This file is for AI coding agents working in the repo.
> Read `AGENTS.md`, `CLAUDE.md`, `tasks/lessons.md`, `tasks/todo.md`, and `WORKFLOW_ORCHESTRATION.md` before changing code.
> Verify current file signatures before editing; this project has moved quickly.

---

## Build & Verify

```bash
# Build macOS target
xcodebuild -project Connectakt.xcodeproj \
  -scheme Connectakt_macOS \
  -derivedDataPath /tmp/ConnectaktDerived \
  build

# Build iOS simulator target
xcodebuild -project Connectakt.xcodeproj \
  -scheme Connectakt_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/ConnectaktDerived \
  build

# Run iOS tests
xcodebuild -project Connectakt.xcodeproj \
  -scheme Connectakt_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/ConnectaktDerived \
  test
```

Build one target at a time. Do not run multiple `xcodebuild` commands in parallel.

---

## Current Verified Status

- macOS build succeeds with `Connectakt_macOS`
- iOS simulator build succeeds with `Connectakt_iOS`
- iOS test suite succeeds: `48 tests` across `10 suites`

---

## Task 1 — Project Bootstrap & Theme Foundation [✅ DONE]

> Completed: 2026-03-23
> Commit: 5d8346d
> Notes: Project shell, theme, tab navigation, and initial mock connection flow are in place.

## Task 2 — Sample Transfer & Optimization [✅ DONE]

> Completed: 2026-03-23
> Commit: bd24c96
> Notes: Audio optimization, import workflow UI, and transfer abstractions landed.

## Task 3 — Recording Workflow [✅ DONE]

> Completed: 2026-03-23
> Commit: d3ad842
> Notes: Recorder flow, waveform capture, BPM detection, session history, and optimize-upload workflow are in place.

## Task 4 — MIDI Transfer / SysEx Foundation [✅ DONE]

> Completed: 2026-03-23
> Commit: TBD
> Notes: `ElektronProtocol`, `ElektronMIDITransfer`, and `USBDeviceMonitor` replaced the earlier stub transfer path. Real-hardware validation is still pending.

## Task 5 — Sample Editor Workspace [✅ DONE]

> Completed: 2026-03-29
> Commit: TBD
> Notes: `EditorView` is now an import-driven editor with waveform trim, destructive edits, BPM/key analysis, preview/export rendering, and optimize-upload integration. Loop-point editing is still outstanding.

### Key files
| File | Description |
|------|-------------|
| `Connectakt/Features/Editor/EditorView.swift` | Editor UI plus `EditorScreenModel` and processing pipeline |
| `ConnektaktTests/ConnektaktTests.swift` | Sample editor helper coverage |
| `ConnektaktTests/AudioOptimizerTests.swift` | Thread-safe optimizer progress assertions |
| `ConnektaktTests/ElektronProtocolTests.swift` | Updated current-protocol coverage |

### Acceptance criteria
- [x] Waveform viewer with zoom/trim controls
- [x] Normalize, fade in/out, and reverse controls
- [x] Pitch shift and time-stretch controls with offline preview rendering
- [x] BPM detection for imported samples
- [x] Key estimation for melodic material
- [x] Export path produces Digitakt-optimized WAV
- [ ] Loop point editor for sustain loops

---

## Task 6 — AUV3 Integration & Processing Chain [✅ DONE]

> Completed: 2026-03-31
> Commit: 64e8bc6
> Notes: Third-party App Store AUV3 discovery and on-device loading/preview validation are now working after splitting iOS/macOS entitlements and adding `inter-app-audio` to the iOS host build. The remaining follow-up is performance tuning for the initial discovery list load on-device.

### Read first
- `Connectakt/Features/Editor/EditorView.swift`
- `Connectakt/Features/Optimizer/OptimizationModels.swift`
- `Connectakt/Features/Transfer/DigitaktTransferProtocol.swift`
- `tasks/todo.md`
- `tasks/lessons.md`

### Goal
Add an AUV3 effect chain to the sample editor so imported audio can be previewed and rendered through third-party effects before export or upload.

### Suggested implementation order
1. Introduce an editor-safe effect chain model that can persist selected AU components plus parameter snapshots.
2. Build a lightweight AUV3 host service that can discover installed audio effects and instantiate one effect at a time reliably.
3. Add editor UI for browsing/loading effects and reordering or removing items from the chain.
4. Route editor preview rendering through the hosted AUV3 chain.
5. Add freeze/render support so processed output becomes a new export/upload source.
6. Add preset save/load for effect chains if time permits in the same slice.

### Acceptance criteria
- [x] Installed AUV3 effects can be discovered from the editor
- [x] A selected effect can be inserted into a chain and previewed
- [x] Offline render path includes the active AUV3 chain
- [x] Frozen/rendered output remains Digitakt-compatible WAV
- [x] Tests cover effect-chain state serialization or other non-UI core logic
- [x] Third-party App Store AUV3 effects appear in the discovery list on-device
- [x] Third-party AUV3 loading/preview is validated on-device

### Notes
- Keep shared code compatible with both iOS and macOS targets.
- Avoid introducing an iOS-only audio unit API into shared compile paths.
- Apple built-in AU effects have been validated on-device: preview, parameter editing, freeze, render/share, and preset reload all worked.
- Third-party App Store AU effects now enumerate on-device as well; a user-reported device check surfaced roughly 140 effects in the list.
- Discovery is currently correct but can take a noticeable amount of time on-device before the full list appears.
