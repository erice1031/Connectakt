import SwiftUI

// MARK: - Button Style

enum CKButtonVariant {
    case primary    // Yellow fill, black text
    case secondary  // Yellow border, yellow text
    case ghost      // No border, muted text
    case danger     // Red border, red text
}

struct CKButton: View {
    let label: String
    let icon: String?
    let variant: CKButtonVariant
    let action: () -> Void

    init(_ label: String, icon: String? = nil, variant: CKButtonVariant = .primary, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.variant = variant
        self.action = action
    }

    private var fg: Color {
        switch variant {
        case .primary:   return ConnektaktTheme.background
        case .secondary: return ConnektaktTheme.primary
        case .ghost:     return ConnektaktTheme.textSecondary
        case .danger:    return ConnektaktTheme.danger
        }
    }

    private var bg: Color {
        switch variant {
        case .primary:   return ConnektaktTheme.primary
        case .secondary: return .clear
        case .ghost:     return .clear
        case .danger:    return .clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary:   return .clear
        case .secondary: return ConnektaktTheme.primary.opacity(0.6)
        case .ghost:     return .clear
        case .danger:    return ConnektaktTheme.danger.opacity(0.6)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(ConnektaktTheme.smallFont)
                    .tracking(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack(spacing: 8) {
        CKButton("UPLOAD", icon: "arrow.up") {}
        CKButton("CANCEL", variant: .secondary) {}
        CKButton("DELETE", variant: .danger) {}
        CKButton("BROWSE", variant: .ghost) {}
    }
    .padding()
    .background(ConnektaktTheme.background)
}
