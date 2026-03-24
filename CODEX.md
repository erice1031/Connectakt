# Connectakt — Codex Task Handoff

> This file is for AI coding agents (Codex, Claude, etc.).
> Each task is self-contained with specific files, function signatures, and acceptance criteria.
> **Verify**: read the referenced files before making changes to confirm signatures match.
> Mark tasks complete with commit hash when done.

---

## Build & Run

```bash
# Build (iOS Simulator)
xcodebuild -workspace Connectakt.xcworkspace \
  -scheme Connectakt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build

# Run tests
xcodebuild -workspace Connectakt.xcworkspace \
  -scheme ConnektaktTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

**Important**: Build one target at a time. Do not run multiple xcodebuild commands in parallel.

---

## Task 1 — Xcode Project Bootstrap & Theme Foundation

### What exists
| File | Description |
|------|-------------|
| *(nothing yet)* | Project has not been created in Xcode |

### Step-by-step

**Step 1 — Create Xcode project**

- New project → Multiplatform App (Swift, SwiftUI)
- Product Name: `Connectakt`
- Bundle ID: `com.ericerwin.connectakt`
- Minimum deployment: iOS 17.0, macOS 14.0

**Step 2 — Set up folder structure**

```
Connectakt/
├── App/
│   ├── ConnektaktApp.swift
│   └── ContentView.swift
├── Features/
│   ├── Connection/
│   ├── Browser/
│   ├── Optimizer/
│   ├── Recorder/
│   ├── Editor/
│   ├── Backup/
│   └── Store/
├── Shared/
│   ├── UI/
│   │   ├── Theme.swift
│   │   └── Components/
│   ├── Audio/
│   └── Models/
└── Resources/
    └── Assets.xcassets
```

**Step 3 — Implement Theme.swift**

File: `Connectakt/Shared/UI/Theme.swift`

```swift
import SwiftUI

enum ConnektaktTheme {
    // Digitakt color palette
    static let primary = Color(hex: "#F5C400")      // Digitakt yellow
    static let background = Color(hex: "#0D0D0D")   // Deep black (OLED)
    static let surface = Color(hex: "#1A1A1A")      // Slightly lighter black
    static let surfaceElevated = Color(hex: "#242424")
    static let textPrimary = Color(hex: "#F5C400")  // Yellow text
    static let textSecondary = Color(hex: "#8A7A3A") // Dimmed yellow
    static let accent = Color(hex: "#FF6B00")        // Orange accent
    static let waveformGreen = Color(hex: "#39FF14") // Neon green (VU meters)

    // Typography — monospace to mimic Digitakt screen
    static let fontMono = Font.system(.body, design: .monospaced)
    static let fontMonoSm = Font.system(.caption, design: .monospaced)
    static let fontMonoLg = Font.system(.title3, design: .monospaced)
    static let fontMonoXl = Font.system(.title, design: .monospaced, weight: .bold)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
```

**Step 4 — Main app shell (ContentView)**

File: `Connectakt/App/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BrowserView()
                .tabItem { Label("SAMPLES", systemImage: "waveform") }
            RecorderView()
                .tabItem { Label("RECORD", systemImage: "record.circle") }
            EditorView()
                .tabItem { Label("EDITOR", systemImage: "slider.horizontal.3") }
            SettingsView()
                .tabItem { Label("SETTINGS", systemImage: "gear") }
        }
        .tint(ConnektaktTheme.primary)
        .background(ConnektaktTheme.background)
        .preferredColorScheme(.dark)
    }
}
```

### Acceptance criteria
- [ ] App builds for iOS 17+ simulator with zero errors
- [ ] App launches and shows 4-tab navigation
- [ ] Background is deep black, accents are Digitakt yellow (#F5C400)
- [ ] Monospace font used throughout
- [ ] Folder structure matches spec above

---

## Task 2 — USB Connection Manager

*(Pending Task 1 completion)*

### What will be needed
- `ExternalAccessory` framework for MFi accessories
- `CoreUSB` (iOS 16+) for USB device enumeration
- Research into Elektron Transfer protocol (USB bulk transfer)

### Acceptance criteria (TBD)
- [ ] App detects when Digitakt is connected via USB
- [ ] Connection status shown in UI (connected/disconnected)
- [ ] USB device vendor/product ID confirmed: Elektron VID = 0x1935

---

## Task 3 — Audio Optimizer

*(Pending Task 1 completion)*

### What will be needed
- `AVFoundation` for audio file reading/writing
- `AVAudioConverter` for sample rate and bit depth conversion
- Mono downmix (stereo L+R → mono)
- Output: WAV, 16-bit, 44.1kHz, mono

### Acceptance criteria (TBD)
- [ ] MP3 → Digitakt WAV conversion works
- [ ] Stereo WAV → mono WAV conversion works
- [ ] Output is exactly: 16-bit PCM, 44100 Hz, 1 channel

---

*More tasks will be added as phases are completed.*
