import SwiftUI

/// Digitakt-style storage usage bar — segmented blocks like a hardware meter.
struct CKStorageMeter: View {
    let usedMB: Int
    let totalMB: Int
    var segmentCount: Int = 20

    private var fillRatio: Double {
        guard totalMB > 0 else { return 0 }
        return Double(usedMB) / Double(totalMB)
    }

    private var filledSegments: Int {
        Int((fillRatio * Double(segmentCount)).rounded())
    }

    private var meterColor: Color {
        switch fillRatio {
        case ..<0.70: return ConnektaktTheme.waveformGreen
        case ..<0.90: return ConnektaktTheme.accent
        default:      return ConnektaktTheme.danger
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.15))
                .frame(height: 1)

            HStack(spacing: ConnektaktTheme.paddingMD) {
                Text("STORAGE")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)

                // Segmented bar
                HStack(spacing: 2) {
                    ForEach(0..<segmentCount, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < filledSegments ? meterColor : ConnektaktTheme.surfaceHigh)
                            .frame(height: 10)
                    }
                }

                Text("\(usedMB) / \(totalMB) MB")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .background(ConnektaktTheme.surface)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        CKStorageMeter(usedMB: 487, totalMB: 700)
        CKStorageMeter(usedMB: 620, totalMB: 700)
        CKStorageMeter(usedMB: 690, totalMB: 700)
    }
    .background(ConnektaktTheme.background)
}
