# Connectakt — Task Tracker

## Current Task: Phase 6 — AUV3 App Extension

## In Progress — Phase 6 planning / setup
- [x] Create `ConnektaktAU` app extension target
- [x] Decide first plugin scope: effect shell with pass-through audio and Connectakt-branded UI
- [x] Validate extension bundle structure and embedding in the iOS app
- [x] Validate host loading in a real AU host (Ableton Live)
- [ ] Reuse editor/transfer code safely inside extension sandbox
- [ ] Decide whether the second slice should add plugin-side browsing first or transfer actions first

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

### ✅ Done — Phase 5 slice 1 (commit 64e8bc6)
- AUV3 discovery UI in `EditorView` with chain management, bypass, reorder, and clear signal-path messaging
- Preview, freeze, render/share, and optimize/upload paths route through the active AUV3 chain
- Hosted parameter inspection/editing with parameter snapshot persistence per chain item
- Effect-chain preset save/load/delete persists across app relaunches
- On-device validation completed with Apple built-in AU effects: preview playback, parameter editing, freeze, render/share, and preset reload all succeeded
- Host entitlements split by platform: iOS now signs with `Connectakt_iOS.entitlements` and includes `inter-app-audio`; macOS continues using the sandbox entitlement file
- On-device validation completed with third-party App Store AUV3 effects: the full device plugin catalog now appears in the discovery list and third-party effects can be inserted
- Verified locally: iOS simulator build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ConnectaktDerived build`
- Verified locally: macOS build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_macOS -derivedDataPath /tmp/ConnectaktDerived build`
- Verified locally: iOS tests succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ConnectaktDerived test` (`48 tests` across `10 suites`)

### ✅ Done — Phase 6 slice 1 (commit bca5b4e)
- `ConnektaktAU` iOS app-extension target scaffold added
- Minimal pass-through `ConnectaktAudioUnit` effect implementation added
- `AudioUnitViewController` + `ConnectaktAUView` provide a branded AU host UI shell
- `ConnektaktAU` embeds in the iOS app only; macOS build excludes the iOS extension correctly
- User validation completed: `ConnektaktAU` appears and loads in Ableton Live as an Audio Unit pass-through effect
- Verified locally: macOS build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_macOS -derivedDataPath /tmp/ConnectaktDerived build`
- Verified locally: iOS simulator build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ConnectaktDerived build`
- Verified locally: iPhoneOS build succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'generic/platform=iOS' -derivedDataPath /tmp/ConnectaktDeviceDerived build`
- Verified locally: iOS tests succeeded with `xcodebuild -project Connectakt.xcodeproj -scheme Connectakt_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ConnectaktDerived test` (`48 tests` across `10 suites`)

### Follow-up
- [ ] Improve on-device AUV3 discovery performance; the full effect list now loads correctly but can take a noticeable amount of time to populate
- [ ] Validate the new `ConnektaktAU` extension in Logic Pro for iPad and AUM after the initial Ableton Live confirmation
- [ ] Add plugin parameters or a small functional control surface once host loading is confirmed

### Backlog (hardware-dependent)
- [ ] Verify ElektronMsgType command byte values against real Digitakt hardware
- [ ] Stress-test chunked file upload/download with large samples

### Backlog
- AUV3 plugin target
- StoreKit 2 monetization
- iCloud backup
- SysEx dump/restore
- App Store submission
