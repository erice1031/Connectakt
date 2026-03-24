import SwiftUI

/// Canvas-based waveform that re-renders only when the `levels` array changes.
/// Unlike CKWaveformView (TimelineView animation), this reacts to real audio data.
struct CKLiveWaveformView: View {
    /// 0.0 … 1.0 amplitudes, oldest first, newest last.
    let levels: [Float]
    var color: Color = ConnektaktTheme.danger
    var backgroundColor: Color = ConnektaktTheme.surface

    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }

            let barWidth = size.width / CGFloat(count)
            let midY = size.height / 2

            for (i, level) in levels.enumerated() {
                let x = CGFloat(i) * barWidth
                let half = CGFloat(level) * midY
                // Fade older bars toward transparent
                let alpha = 0.3 + 0.7 * Double(i) / Double(count)

                let rect = CGRect(
                    x: x,
                    y: midY - half,
                    width: max(barWidth - 1, 1),
                    height: half * 2
                )
                context.fill(Path(rect), with: .color(color.opacity(alpha)))
            }
        }
        .background(backgroundColor)
    }
}

#Preview {
    CKLiveWaveformView(
        levels: (0..<60).map { Float(sin(Double($0) * 0.2) * 0.5 + 0.5) }
    )
    .frame(height: 80)
    .padding()
    .background(ConnektaktTheme.background)
}
