import SwiftUI

// MARK: - Connectakt Theme
// Inspired by the Elektron Digitakt OLED screen: deep black, yellow text, monospace.

enum ConnektaktTheme {

    // MARK: Colors
    static let primary        = Color(hex: "#F5C400")   // Digitakt yellow
    static let background     = Color(hex: "#0D0D0D")   // OLED deep black
    static let surface        = Color(hex: "#1A1A1A")   // Elevated surface
    static let surfaceHigh    = Color(hex: "#242424")   // Higher elevation
    static let textPrimary    = Color(hex: "#F5C400")   // Yellow text
    static let textSecondary  = Color(hex: "#8A7A3A")   // Dimmed yellow
    static let textMuted      = Color(hex: "#4A4020")   // Very dimmed
    static let accent         = Color(hex: "#FF6B00")   // Orange accent
    static let waveformGreen  = Color(hex: "#39FF14")   // Neon green (meters/waveform)
    static let danger         = Color(hex: "#FF3B3B")   // Red (recording indicator)
    static let online         = Color(hex: "#39FF14")   // Connected green
    static let offline        = Color(hex: "#4A4020")   // Disconnected muted

    // MARK: Typography
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let titleFont   = Font.system(size: 13, weight: .bold, design: .monospaced)
    static let bodyFont    = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let smallFont   = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let largeFont   = Font.system(size: 16, weight: .bold, design: .monospaced)

    // MARK: Spacing
    static let paddingXS: CGFloat = 4
    static let paddingSM: CGFloat = 8
    static let paddingMD: CGFloat = 12
    static let paddingLG: CGFloat = 16
    static let paddingXL: CGFloat = 24

    // MARK: Geometry
    static let cornerRadius: CGFloat = 4
    static let dividerHeight: CGFloat = 1
    static let accentBarHeight: CGFloat = 2
}

// MARK: - View Modifiers

struct CKPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ConnektaktTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius)
                    .strokeBorder(ConnektaktTheme.primary.opacity(0.2), lineWidth: 1)
            )
    }
}

struct CKScreenStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ConnektaktTheme.background)
    }
}

extension View {
    func ckPanel() -> some View {
        modifier(CKPanelStyle())
    }

    func ckScreen() -> some View {
        modifier(CKScreenStyle())
    }
}

// MARK: - Color from Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
