import SwiftUI

struct RecordingHistoryView: View {
    @Environment(RecordingHistoryManager.self) private var history
    @Environment(ConnectionManager.self) private var connection

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("RECENT RECORDINGS")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)
                Spacer()
                Text("\(history.sessions.count)/20")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)

            if history.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.microphone")
                        .font(.system(size: 24))
                        .foregroundStyle(ConnektaktTheme.textMuted)
                    Text("NO RECORDINGS YET")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ConnektaktTheme.paddingLG)
            } else {
                ForEach(history.sessions) { session in
                    SessionRow(session: session)
                }
            }
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: RecordingSession
    @Environment(RecordingHistoryManager.self) private var history
    @Environment(ConnectionManager.self) private var connection

    var body: some View {
        HStack(spacing: ConnektaktTheme.paddingSM) {
            Image(systemName: "waveform")
                .font(.system(size: 11))
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(session.durationString)
                    if let bpm = session.bpm { Text("• \(bpm) BPM") }
                    Text("• \(session.sizeString)")
                }
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
            }

            Spacer()

            Button {
                history.remove(id: session.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(ConnektaktTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.1))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
