import SwiftUI

/// Blinking connection status indicator pill — like an LED on the hardware.
struct CKStatusBadge: View {
    let status: ConnectionStatus
    @State private var blinkOn = true

    private var dotColor: Color {
        switch status {
        case .disconnected: return ConnektaktTheme.offline
        case .scanning:     return ConnektaktTheme.accent
        case .connected:    return ConnektaktTheme.online
        }
    }

    private var isBlinking: Bool {
        status == .scanning
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .opacity(isBlinking ? (blinkOn ? 1.0 : 0.2) : 1.0)

            Text(status.label)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(status.isConnected ? ConnektaktTheme.textPrimary : ConnektaktTheme.textSecondary)
                .tracking(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ConnektaktTheme.surfaceHigh)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(dotColor.opacity(0.3), lineWidth: 1))
        .onAppear {
            guard isBlinking else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                blinkOn = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        CKStatusBadge(status: .disconnected)
        CKStatusBadge(status: .scanning)
        CKStatusBadge(status: .connected(deviceName: "DIGITAKT"))
    }
    .padding()
    .background(ConnektaktTheme.background)
}
