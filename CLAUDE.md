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
│   ├── Connection/
│   │   ├── DigitaktConnection.swift    # USB session manager
│   │   └── ElektronTransfer.swift      # Elektron Transfer protocol
│   ├── Browser/
│   │   ├── BrowserView.swift           # Sample/project list UI
│   │   └── BrowserViewModel.swift      # File listing logic
│   ├── Optimizer/
│   │   ├── AudioOptimizer.swift        # Convert → Digitakt WAV spec
│   │   └── BatchOptimizer.swift        # Batch conversion
│   ├── Recorder/
│   │   ├── RecorderView.swift          # Record UI
│   │   └── USBAudioRecorder.swift      # AVCaptureSession USB audio
│   ├── Editor/
│   │   ├── EditorView.swift            # Waveform editor UI
│   │   ├── WaveformRenderer.swift      # GPU waveform drawing (Metal)
│   │   └── AUV3Host.swift             # AUV3 plugin hosting
│   ├── Backup/
│   │   ├── SysExDumper.swift           # Digitakt SysEx backup
│   │   └── ProjectArchiver.swift       # ZIP export/import
│   └── Store/
│       └── PurchaseManager.swift       # StoreKit 2 IAP
├── Shared/
│   ├── UI/
│   │   ├── Theme.swift                 # Elektron color palette + typography
│   │   └── Components/                 # Reusable UI components
│   ├── Audio/
│   │   └── AudioFileUtils.swift        # Shared audio utilities
│   └── Models/
│       ├── Sample.swift                # Sample domain model
│       ├── Project.swift               # Digitakt project model
│       └── DeviceState.swift           # USB connection state
├── ConnektaktAU/                        # AUV3 extension target
│   ├── ConnektaktAUExtension.swift
│   └── ConnektaktAUUI.swift
└── ConnektaktTests/
    └── OptimizerTests.swift
```

---

## Key Technologies

| Technology | Purpose |
|-----------|---------|
| SwiftUI | All UI (universal: iOS, iPadOS, macOS) |
| AVFoundation | Audio file reading, conversion, recording |
| AVAudioConverter | Sample rate / bit depth conversion |
| CoreUSB (iOS 16+) | USB device discovery |
| ExternalAccessory | MFi accessory communication |
| Metal | GPU-accelerated waveform rendering |
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

---

## Known Bugs / TODOs

*(Empty — project just started)*

---

## External References

- Elektron Digitakt manual: https://www.elektron.se/digitakt-support/
- Elektron Transfer protocol hints: `elektron-ctl` on GitHub
- CoreUSB framework: Apple documentation (iOS 16+)
- USB Audio Class 2.0: USB-IF specification
