# Connectakt — Task Tracker

## Current Task: Project Bootstrap

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

### 🔶 Remaining Phase 3 TODOs
- [ ] CoreUSB device enumeration (VID 0x1935) — real hardware detection (file transfer)
- [ ] Elektron Transfer protocol (ref: elektron-ctl on GitHub) — replace MockDigitaktTransfer

### Backlog
- USB connection manager (CoreUSB / ExternalAccessory)
- Audio optimizer (AVFoundation)
- Sample browser UI
- Recording mode
- Sample editor
- AUV3 host
- AUV3 plugin target
- StoreKit 2 monetization
- iCloud backup
- SysEx dump/restore
- App Store submission
