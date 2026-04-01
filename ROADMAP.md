# Connectakt — Development Roadmap

> **Handoff note:** This roadmap is kept up-to-date as features land.
> Check `CLAUDE.md` for architecture details and key file locations.
> Check `CODEX.md` for detailed agent task handoffs.
> Last updated: 2026-03-31

---

## ✅ Completed

| Phase | Feature | Commit |
|-------|---------|--------|
| 0 | Project bootstrap, repo init, workflow docs | dae8193 |
| 1 | Xcode project, Elektron UI shell, 4-tab nav, ConnectionManager, 10 unit tests | 5d8346d |
| 2 | AudioOptimizer, DigitaktTransferProtocol, import flow UI, 18 unit tests | bd24c96 |
| 3 | AudioRecorder, BPMDetector, RecordingSession/History, live waveform, 32 tests | d3ad842 |
| 3b | ElektronProtocol (SysEx), ElektronMIDITransfer, USBDeviceMonitor (CoreMIDI), 53 tests | TBD |
| 4 | Sample editor workspace, waveform trim/edit flow, preview/export/upload path, 46 tests in current verified suite | TBD |
| 5 | AUV3 editor host, chain presets, parameter editing, freeze/render/share path, and third-party on-device validation | 64e8bc6 |

---

## 🔜 Next Up

### Phase 6 — AUV3 App Extension

- [x] Connectakt AUV3 effect extension scaffold compiles and embeds in the iOS app
- [x] Plugin exposes an initial in-host sample browser shell within a DAW
- [ ] Plugin-side sample selection triggers transfer or shared-app handoff
- [x] Initial real-host validation: loads in Ableton Live as an AU pass-through effect
- [x] Browser-shell validation: renders correctly in Ableton Live
- [ ] Logic Pro for iPad integration testing
- [ ] AUM / Audiobus compatibility

**Acceptance criteria**
- [x] Plugin appears in at least one real AU host
- [x] Plugin browser shell is usable inside at least one real AU host
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
