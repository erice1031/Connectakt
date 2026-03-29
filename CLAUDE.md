# CLAUDE.md — Connectakt

> Architecture reference for AI agents. Keep this updated as the codebase evolves.

---

## Project Overview

**Connectakt** is a universal iOS/iPadOS/macOS companion app for the Elektron Digitakt hardware drum sampler. It connects via USB and provides:

1. **Sample Management** — Browse, transfer, and organize samples between iPhone and Digitakt
2. **Sample Optimization** — Auto-convert any audio to Digitakt-spec WAV (16-bit, 44.1kHz, mono)
3. **Audio Recording** — Record Digitakt output via USB audio interface mode
4. **Sample Editor** — Full waveform editor with trim, normalize, pitch, time-stretch
5. **AUV3 Host** — Process samples through third-party audio plugins
6. **AUV3 Plugin** — Connectakt as a plugin inside Logic Pro for iPad / AUM

---

## Digitakt Hardware Specs (Critical Reference)

| Spec | Value |
|------|-------|
| USB Port | USB-B (Standard USB) |
| USB Protocol | Elektron Transfer (proprietary), USB Audio Class 2.0 |
| USB Vendor ID | 0x1935 (Elektron Music Machines) |
| Sample Format | WAV, 16-bit PCM, 44.1kHz or 48kHz |
| Sample Channels | Mono preferred (stereo supported, uses 2× RAM) |
| Sample RAM | 64 MB |
| Internal Storage | ~1 GB |
| Tracks | 8 audio + 8 MIDI |
| Patterns | 128 per project, 16 steps to 64 steps |

---

## Architecture

```
Connectakt/
├── App/
│   ├── ConnektaktApp.swift        # App entry point
│   └── ContentView.swift          # Root navigation (TabView)
├── Features/
│   ├── Browser/
│   │   ├── BrowserView.swift           # Sample browser and import entry point
│   │   ├── ImportCoordinator.swift     # Analyze/optimize/upload workflow state
│   │   └── OptimizationSheet.swift     # Import optimization UI
│   ├── Editor/
│   │   └── EditorView.swift            # Import-driven sample editor, analysis, preview, export/upload
│   ├── Recorder/
│   │   ├── RecorderView.swift          # Record UI with history and upload actions
│   │   ├── AudioRecorder.swift         # AVAudioEngine capture pipeline
│   │   ├── AudioAnalyzer.swift         # BPM/onset analysis helpers
│   │   └── RecordingSession.swift      # Persisted session model/history support
│   └── Settings/
│       └── SettingsView.swift          # App settings and status
├── Shared/
│   ├── Models/
│   │   ├── ConnectionManager.swift     # USB/MIDI connection lifecycle
│   │   ├── DigitaktTransferProtocol.swift # Transfer abstraction and mock transport
│   │   ├── ElektronMIDITransfer.swift  # CoreMIDI transport for Digitakt transfers
│   │   ├── ElektronProtocol.swift      # SysEx framing, 7-bit encoding, payload helpers
│   │   ├── OptimizationModels.swift    # Audio optimizer domain models
│   │   ├── RecordingHistoryManager.swift # JSON-backed recorder history store
│   │   └── SampleFile.swift            # Sample metadata model
│   └── UI/
│       ├── Theme.swift                 # Elektron color palette + typography
│       └── Components/                 # Shared controls, waveform, badges, meters
├── ConnektaktTests/
│   ├── AudioOptimizerTests.swift       # Optimizer coverage + progress callback assertions
│   ├── ConnektaktTests.swift           # UI/model tests + sample editor helper tests
│   └── ElektronProtocolTests.swift     # SysEx, payload, and file-list parsing tests
└── Connectakt.xcodeproj
```

---

## Key Technologies

| Technology | Purpose |
|-----------|---------|
| SwiftUI | All UI (universal: iOS, iPadOS, macOS) |
| AVFoundation | Audio file reading, conversion, recording |
| AVAudioConverter | Sample rate / bit depth conversion |
| CoreMIDI | Current USB MIDI-class Digitakt discovery and transport path |
| CoreUSB (iOS 16+) | Future direct USB device discovery path |
| ExternalAccessory | Future MFi accessory communication fallback |
| AudioUnit v3 | AUV3 plugin hosting + plugin target |
| StoreKit 2 | In-app purchases |
| CloudKit | iCloud project backup |

---

## UI Design Language

| Element | Value |
|---------|-------|
| Background | #0D0D0D (deep black, OLED) |
| Surface | #1A1A1A |
| Primary / Text | #F5C400 (Digitakt yellow) |
| Secondary Text | #8A7A3A (dimmed yellow) |
| Accent | #FF6B00 (orange) |
| Waveform / Meters | #39FF14 (neon green) |
| Font | System monospaced (design: .monospaced) |

The UI mimics the Digitakt's hardware screen: dark OLED background, yellow text/icons, minimal chrome, function-first layout.

---

## Monetization

| Tier | Price | Features |
|------|-------|---------|
| Free | $0 | Browse samples, single transfer, basic preview |
| Pro | $7.99 | Full editor, batch ops, recording, AUV3, backup |
| Intro Offer | ~$3.19 (~60% off) | First month promotional |

---

## Known Constraints & Gotchas

1. **Elektron Transfer is proprietary** — Not standard MTP. Reference: `elektron-ctl` open-source project for protocol hints.
2. **USB requires real hardware** — No simulator support for USB connection or USB audio recording.
3. **AVAudioUnitDynamicsProcessor** — iOS-only, will NOT compile on macOS target. Avoid in shared code.
4. **AUV3 requires entitlements** — Separate target, specific App Store entitlements required.
5. **CoreUSB vs ExternalAccessory** — CoreUSB (iOS 16+) is preferred for non-MFi USB; ExternalAccessory requires MFi certification from Elektron.
6. **xcodebuild parallel builds** — Always build one target at a time; shared derived data causes conflicts.
7. **Current verified build entry points** — This repo currently builds via `Connectakt.xcodeproj` with `Connectakt_iOS` and `Connectakt_macOS` schemes, not the older `Connectakt.xcworkspace` instructions.
8. **Editor preview path is offline-rendered** — `EditorView` currently uses `AVAudioEngine` manual rendering plus `AVAudioUnitTimePitch` and chained AUV3 effects for preview/export/freeze.

---

## Known Bugs / TODOs

- Phase 4 editor still lacks loop point editing.
- Phase 5 AUV3 chain browsing/hosting plus parameter editing is implemented in the editor; Apple built-in AU validation succeeded on-device, but purchased third-party AUV3 discovery/runtime validation is still pending.
- Real hardware validation is still needed for `ElektronMsgType` command bytes and large transfer chunking.
- `EditorView` currently builds with a small number of AVFoundation deprecation warnings that should be cleaned up in a follow-up pass.

---

## External References

- Elektron Digitakt manual: https://www.elektron.se/digitakt-support/
- Elektron Transfer protocol hints: `elektron-ctl` on GitHub
- CoreUSB framework: Apple documentation (iOS 16+)
- USB Audio Class 2.0: USB-IF specification
