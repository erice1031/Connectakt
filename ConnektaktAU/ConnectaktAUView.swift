import SwiftUI

struct ConnectaktAUView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.05),
                    Color(red: 0.1, green: 0.1, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 14) {
                Text("CONNECTAKT AU")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.02))

                Text("PHASE 6 SHELL")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 0.22))

                Text("PASS-THROUGH EFFECT TARGET")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)

                Text("This first extension slice is focused on host registration, loading, and UI presentation inside AU hosts. Audio currently passes through unchanged while we wire the extension surface.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .overlay(Color(red: 0.96, green: 0.77, blue: 0.02).opacity(0.4))

                HStack(spacing: 12) {
                    statusPill("AUv3", tone: Color(red: 0.96, green: 0.77, blue: 0.02))
                    statusPill("Effect", tone: Color(red: 0.22, green: 1.0, blue: 0.08))
                    statusPill("Pass Through", tone: Color(red: 1.0, green: 0.45, blue: 0.0))
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func statusPill(_ title: String, tone: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(tone)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tone.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ConnectaktAUView()
}
