# Connectakt — Development Roadmap

> **Handoff note:** This roadmap is kept up-to-date as features land.
> Check `CLAUDE.md` for architecture details and key file locations.
> Check `CODEX.md` for detailed agent task handoffs.
> Last updated: 2026-03-23

---

## ✅ Completed

| Phase | Feature | Commit |
|-------|---------|--------|
| 0 | Project bootstrap, repo init, workflow docs | dae8193 |
| 1 | Xcode project, Elektron UI shell, 4-tab nav, ConnectionManager, 10 unit tests | 5d8346d |
| 2 | AudioOptimizer, DigitaktTransferProtocol, import flow UI, 18 unit tests | bd24c96 |
| 3 | AudioRecorder, BPMDetector, RecordingSession/History, live waveform, 32 tests | d3ad842 |
| 3b | ElektronProtocol (SysEx), ElektronMIDITransfer, USBDeviceMonitor (CoreMIDI), 53 tests | TBD |

---

## 🔜 Next Up

### Phase 1 — Foundation & USB Connectivity

The core of the app: establishing a reliable USB communication channel with the Digitakt and building the Elektron-themed UI shell.

- [ ] Xcode project setup (iOS/iPadOS/macOS universal, SwiftUI)
- [ ] Core project structure (packages, modules, targets)
- [ ] Elektron-themed UI shell (yellow #F5C400 / black #1A1A1A, monospace font, OLED aesthetic)
- [ ] USB device detection via CoreUSB / ExternalAccessory framework
- [ ] MTP/Elektron Transfer protocol research & implementation
- [ ] Basic project/sample directory browsing (read-only)
- [ ] Waveform thumbnail rendering for sample list

**Acceptance criteria**
- [ ] App launches on iPhone 15 Pro simulator
- [ ] USB connection detected when Digitakt attached
- [ ] Sample list populates from Digitakt storage
- [ ] Visual style matches Digitakt screen aesthetic

---

### Phase 2 — Sample Transfer & Optimization Engine

- [ ] Sample optimizer: convert any audio to Digitakt-spec WAV (16-bit, 44.1kHz, mono)
- [ ] Drag-and-drop / Files app integration for importing audio
- [ ] Upload samples from iPhone → Digitakt with progress indicator
- [ ] Download samples from Digitakt → iPhone
- [ ] Batch import/export (folder operations)
- [ ] Storage usage display (used/total MB on Digitakt)

**Acceptance criteria**
- [ ] Any audio file (MP3, AAC, WAV stereo, etc.) converts correctly to Digitakt spec
- [ ] Round-trip transfer verified (upload → Digitakt plays it)
- [ ] Batch operation completes without corruption

---

### Phase 3 — Audio Recording / Resampling Mode

- [ ] USB audio interface mode (record Digitakt output → iPhone)
- [ ] Live waveform visualization during recording
- [ ] One-tap: Record → Optimize → Upload workflow
- [ ] Recording history / session manager
- [ ] Auto-name with BPM + timestamp

**Acceptance criteria**
- [ ] Audio recorded from Digitakt at 16-bit/48kHz
- [ ] Waveform renders in real-time during capture
- [ ] Full resample loop: record → convert → upload in < 10 taps

---

### Phase 4 — Sample Editor

- [ ] Waveform viewer with zoom/scroll
- [ ] Trim (set start/end points)
- [ ] Normalize, fade in/out
- [ ] Reverse
- [ ] Pitch shift (semitones, fine-tune)
- [ ] Time stretch (tempo-sync)
- [ ] BPM detection for loop samples
- [ ] Key detection for melodic samples
- [ ] Loop point editor (for sustain loops)

**Acceptance criteria**
- [ ] All edits render correctly and non-destructively
- [ ] Preview playback reflects edits in real-time
- [ ] Exports to Digitakt-optimized WAV

---

### Phase 5 — AUV3 Integration & Processing Chain

- [ ] AUV3 host within the sample editor
- [ ] Browse/load installed AUV3 effects
- [ ] Signal chain: Sample → AUV3 effects → Output
- [ ] Render/freeze AUV3 chain to new sample
- [ ] Preset save/load for effect chains

**Acceptance criteria**
- [ ] Third-party AUV3 loads and processes audio
- [ ] Rendered output is valid Digitakt-spec WAV
- [ ] Chain presets persist across sessions

---

### Phase 6 — AUV3 App Extension

- [ ] Connectakt AUV3 plugin target (instrument/effect)
- [ ] Plugin exposes sample browser + Digitakt transfer within a DAW
- [ ] Logic Pro for iPad integration testing
- [ ] AUM / Audiobus compatibility

**Acceptance criteria**
- [ ] Plugin appears in Logic Pro for iPad's AU browser
- [ ] Transfer functions work from within the plugin
- [ ] No sandbox/entitlement issues in App Store build

---

### Phase 7 — Project Management & Backup

- [ ] Full Digitakt project backup to iPhone (SysEx dump)
- [ ] Project restore from backup
- [ ] Project metadata viewer (pattern grid overview)
- [ ] iCloud backup of projects
- [ ] Export project as ZIP archive (share/archive)

**Acceptance criteria**
- [ ] SysEx dump/restore round-trip verified on hardware
- [ ] iCloud sync works across devices

---

### Phase 8 — Polish, Monetization & App Store

- [ ] StoreKit 2 monetization ($7.99 / intro 60% off = ~$3.19)
- [ ] Free tier: browse + single sample transfer
- [ ] Pro unlock: full editor, AUV3, batch ops, recording mode
- [ ] App Store screenshots (Digitakt aesthetic)
- [ ] App preview video
- [ ] Landing page
- [ ] TestFlight beta

**Acceptance criteria**
- [ ] Purchase flow tested in sandbox
- [ ] App Store review guidelines compliance
- [ ] TestFlight build accepted

---

## Future / Backlog

- **Sample Pack Marketplace** — Browse/import Elektron-optimized packs from community
- **Pattern Visualization** — Read Digitakt patterns via MIDI/SysEx and show step grid
- **Elektron Cloud Sync** — If Elektron ever opens an API
- **Digitakt II Support** — Extended specs for the newer hardware
- **Android Version** — USB OTG support if market demand justifies
- **Web Audio Preview** — Generate shareable audio previews
- **Genre Starter Kits** — Curated sample collections optimized for Digitakt

---

## Architecture Quick Reference

```
Connectakt/
├── App/                      # App entry point, routing, theme
├── Features/
│   ├── Connection/           # USB device discovery & communication
│   ├── Browser/              # Project & sample file browser
│   ├── Optimizer/            # Audio conversion engine (AVFoundation)
│   ├── Recorder/             # USB audio capture
│   ├── Editor/               # Waveform editor + AUV3 host
│   ├── Backup/               # SysEx dump/restore
│   └── Store/                # StoreKit 2 IAP
├── Shared/
│   ├── UI/                   # Elektron theme components
│   ├── Audio/                # Core audio utilities
│   └── Models/               # Domain models
└── ConnektaktAU/             # AUV3 extension target
```

### Key Files
| File | Purpose |
|------|---------|
| `Features/Connection/DigitaktConnection.swift` | USB device session manager |
| `Features/Optimizer/AudioOptimizer.swift` | Convert to Digitakt-spec WAV |
| `Features/Recorder/USBAudioRecorder.swift` | Record from Digitakt via USB audio |
| `Shared/UI/Theme.swift` | Elektron color palette + typography |
