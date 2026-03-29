# Connectakt — Task Tracker

## Current Task: Phase 5 — AUV3 Integration & Processing Chain

## In Progress — Phase 5 AUV3 integration
- [x] Discover installed AUV3 effect components from the editor
- [x] Add chain-building UI with insert, bypass, reorder, and remove actions
- [x] Route preview renders through the active AUV3 chain
- [x] Add freeze action to bake the current chain into a new editable sample
- [x] Add effect-chain preset save/load/delete support
- [x] Add hosted-parameter inspection and editing UI with parameter snapshot persistence
- [x] Add unit tests for effect-chain state serialization and preset persistence
- [x] Verify iOS simulator build and test pass after the Phase 5 slice
- [x] Verify macOS build still succeeds with shared editor code
- [x] Validate runtime loading, preview, freeze, render/share, and preset persistence with Apple built-in AU effects on-device
- [ ] Diagnose why purchased third-party AUV3 effects are still missing from the discovery list on-device

### ✅ Done
- Project brief defined
- Notion project page created
- Workflow docs created (ROADMAP.md, AGENTS.md, CODEX.md, WORKFLOW_ORCHESTRATION.md)
- tasks/ directory initialized
- GitHub repo created: https://github.com/erice1031/Connectakt
- Xcode project (xcodegen, universal iOS 17+ / macOS 14+)
- Elektron theme: #F5C400 yellow / #0D0D0D black / monospace
- 4-tab navigation shell (Samples, Record, Editor, Settings)
- ConnectionManager (@Observable) with mock USB simulation
- CKHeaderBar, CKStatusBadge, CKButton, CKWaveformView, CKStorageMeter components
- BrowserView, RecorderView, EditorView, SettingsView
- 10 unit tests — all passing (commit 5d8346d)

### ✅ Done — Phase 2 (commit bd24c96)
- AudioOptimizer actor: AVAssetReaderTrackOutput pipeline (any format → 16-bit/44.1kHz/mono WAV)
- OptimizationModels: AudioFormatInfo, OptimizationOptions, OptimizationResult
- DigitaktTransferProtocol + MockDigitaktTransfer + ElektronTransfer stub
- ImportCoordinator state machine (idle → analyzing → optimizing → uploading → done)
- OptimizationSheet + UploadProgressSheet
- BrowserView: UPLOAD wired to .fileImporter
- 18 unit tests — all passing

### ✅ Done — Phase 3 (commit TBD)
- AudioRecorder actor: AVAudioEngine + installTap pipeline (native format → temp CAF)
- BPMDetector: rising-edge onset detection, NSLock thread-safe
- RecordingSession: Identifiable + Codable model with auto-name (timestamp + BPM)
- RecordingHistoryManager: @Observable, JSON persistence, max 20 sessions
- CKLiveWaveformView: Canvas-based, re-renders on [Float] levels change
- RecordingHistoryView: scrollable session list with delete
- RecorderView: full rewrite — live waveform, BPM badge, transport, one-tap optimize + upload
- ConnectionManager: AVAudioSession routeChangeNotification for real USB audio detection
- ConnektaktApp: AudioRecorder + RecordingHistoryManager injected as environments
- project.yml: NSMicrophoneUsageDescription + com.apple.security.device.audio-input
- 32 unit tests — all passing

### ✅ Done — Phase 3 completion (commit TBD)
- USBDeviceMonitor: CoreMIDI device enumeration (USB MIDI class-compliant, no entitlements)
- ElektronProtocol: Full SysEx message format, nibble encoding/decoding, checksum, payload helpers
- ElektronMIDITransfer: Full DigitaktTransferProtocol impl — actor mailbox, chunked upload/download
- ConnectionManager: USBDeviceMonitor-driven connection lifecycle, falls back to mock on sim
- Removed ElektronTransfer stub — replaced by ElektronMIDITransfer
- ElektronProtocolTests: 21 new tests (SysEx build/parse, nibble round-trip, payload helpers)
- 53 unit tests total — all passing

### ✅ Done — Phase 4 sample editor (commit TBD)
- `EditorView`: import-driven sample editor workspace with analysis, waveform, trim handles, edit controls, preview, export, and optimize + upload
- `EditorScreenModel`: editor state machine with non-destructive settings, rendered preview invalidation, and transfer flow integration
- `SampleEditorProcessor`: waveform peak generation, trim/fade/reverse processing, preview/export WAV rendering, and simple key estimation
- BPM analysis wired through `AudioAnalyzer`
- Editor helper coverage added in `ConnektaktTests`
- `AudioOptimizerTests` updated for thread-safe progress callback assertions
- `ElektronProtocolTests` refreshed to match the current SysEx/7-bit implementation
- Verified locally: macOS build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_macOS -derivedDataPath /tmp/ConnectaktDerived build`
- Verified locally: iOS simulator build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ConnectaktDerived build`
- Verified locally: iOS tests succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ConnectaktDerived test` (`46 tests` across `9 suites`)

### ✅ Done — Phase 5 slice 1 (commit TBD)
- AUV3 discovery UI in `EditorView` with chain management, bypass, reorder, and clear signal-path messaging
- Preview, freeze, render/share, and optimize/upload paths route through the active AUV3 chain
- Hosted parameter inspection/editing with parameter snapshot persistence per chain item
- Effect-chain preset save/load/delete persists across app relaunches
- On-device validation completed with Apple built-in AU effects: preview playback, parameter editing, freeze, render/share, and preset reload all succeeded
- Verified locally: iOS simulator build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ConnectaktDerived build`
- Verified locally: macOS build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_macOS -derivedDataPath /tmp/ConnectaktDerived build`
- Verified locally: iOS tests succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ConnectaktDerived test` (`48 tests` across `10 suites`)

### Backlog (hardware-dependent)
- [ ] Verify ElektronMsgType command byte values against real Digitakt hardware
- [ ] Stress-test chunked file upload/download with large samples

### Backlog
- AUV3 plugin target
- StoreKit 2 monetization
- iCloud backup
- SysEx dump/restore
- App Store submission
