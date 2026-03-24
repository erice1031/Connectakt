import SwiftUI

/// Animated waveform visualization — flat when idle, animated bars when active.
struct CKWaveformView: View {
    var isActive: Bool = false
    var color: Color = ConnektaktTheme.waveformGreen
    var barCount: Int = 80

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !isActive)) { timeline in
            Canvas { context, size in
                let t = isActive ? timeline.date.timeIntervalSinceReferenceDate : 0
                drawBars(context: context, size: size, time: t)
            }
        }
    }

    private func drawBars(context: GraphicsContext, size: CGSize, time: Double) {
        let spacing = size.width / CGFloat(barCount)
        let barWidth = spacing * 0.55
        let midY = size.height / 2

        for i in 0..<barCount {
            let x = CGFloat(i) * spacing + (spacing - barWidth) / 2
            let height: CGFloat

            if isActive {
                let f = Double(i)
                let wave = sin(f * 0.22 + time * 3.1) * 0.40
                       + sin(f * 0.55 + time * 2.3) * 0.30
                       + sin(f * 1.10 + time * 1.7) * 0.20
                       + sin(f * 2.20 + time * 4.1) * 0.10
                height = CGFloat((wave + 1) * 0.5) * size.height * 0.85 + 3
            } else {
                height = 2
            }

            let rect = CGRect(
                x: x,
                y: midY - height / 2,
                width: barWidth,
                height: max(height, 2)
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: 1),
                with: .color(color.opacity(isActive ? 1.0 : 0.35))
            )
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        CKWaveformView(isActive: false)
            .frame(height: 60)
            .padding()
            .background(ConnektaktTheme.surface)

        CKWaveformView(isActive: true)
            .frame(height: 60)
            .padding()
            .background(ConnektaktTheme.surface)
    }
    .padding()
    .background(ConnektaktTheme.background)
}
