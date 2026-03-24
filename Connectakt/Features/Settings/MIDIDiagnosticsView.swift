import SwiftUI
import CoreMIDI

struct MIDIDiagnosticsView: View {
    @State private var monitor = MIDIMonitor()
    @Environment(ConnectionManager.self) private var connection

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MIDI DIAGNOSTICS")
                    .font(ConnektaktTheme.titleFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(2)
                Spacer()
                statusDot
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .background(ConnektaktTheme.surface)

            Rectangle().fill(ConnektaktTheme.primary.opacity(0.3)).frame(height: 2)

            ScrollView {
                VStack(spacing: ConnektaktTheme.paddingSM) {
                    endpointsSection
                    testCommandsSection
                    logSection
                }
                .padding(ConnektaktTheme.paddingSM)
            }
        }
        .ckScreen()
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    // MARK: - Status dot

    private var statusDot: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(monitor.isRunning ? ConnektaktTheme.online : ConnektaktTheme.offline)
                .frame(width: 6, height: 6)
            Text(monitor.isRunning ? "LIVE" : "OFF")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)
        }
    }

    // MARK: - Endpoints

    private var endpointsSection: some View {
        diagSection("MIDI ENDPOINTS") {
            HStack(spacing: 0) {
                endpointColumn("SOURCES (\(monitor.sources.count))", items: monitor.sources)
                Rectangle().fill(ConnektaktTheme.primary.opacity(0.15)).frame(width: 1)
                endpointColumn("DESTINATIONS (\(monitor.destinations.count))", items: monitor.destinations)
            }

            HStack {
                Spacer()
                CKButton("RESCAN", icon: "arrow.clockwise", variant: .secondary) {
                    monitor.refresh()
                }
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
        }
    }

    @ViewBuilder
    private func endpointColumn(_ title: String, items: [MIDIEndpointInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)
                .padding(.horizontal, ConnektaktTheme.paddingMD)
                .padding(.vertical, ConnektaktTheme.paddingSM)

            if items.isEmpty {
                Text("NONE")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
                    .padding(.horizontal, ConnektaktTheme.paddingMD)
                    .padding(.bottom, ConnektaktTheme.paddingSM)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Text(item.badge)
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(item.isElektron ? ConnektaktTheme.primary : ConnektaktTheme.textMuted)
                        Text(item.name)
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(item.isElektron ? ConnektaktTheme.textPrimary : ConnektaktTheme.textSecondary)
                            .tracking(0.5)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, ConnektaktTheme.paddingMD)
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle().fill(ConnektaktTheme.primary.opacity(0.08)).frame(height: 1),
                        alignment: .bottom
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Test Commands

    private var testCommandsSection: some View {
        diagSection("TEST COMMANDS") {
            let elektronDst = monitor.destinations.first(where: \.isElektron)

            if let dst = elektronDst {
                VStack(spacing: ConnektaktTheme.paddingXS) {
                    infoRow("TARGET", dst.name)

                    HStack(spacing: ConnektaktTheme.paddingSM) {
                        CKButton("DEVICE INFO", icon: "info.circle", variant: .secondary) {
                            monitor.sendDeviceInfoRequest(to: dst.ref)
                        }
                        CKButton("STORAGE INFO", icon: "internaldrive", variant: .secondary) {
                            monitor.sendStorageInfoRequest(to: dst.ref)
                        }
                        CKButton("LIST FILES", icon: "list.bullet", variant: .secondary) {
                            monitor.sendListRequest(to: dst.ref)
                        }
                    }
                    .padding(.horizontal, ConnektaktTheme.paddingMD)
                    .padding(.vertical, ConnektaktTheme.paddingSM)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(ConnektaktTheme.accent)
                        .font(.system(size: 11))
                    Text("NO ELEKTRON DESTINATION FOUND — CONNECT VIA USB")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                        .tracking(1)
                }
                .padding(ConnektaktTheme.paddingMD)
            }
        }
    }

    // MARK: - SysEx Log

    private var logSection: some View {
        diagSection("SysEx LOG  (\(monitor.log.count))") {
            HStack {
                Spacer()
                CKButton("CLEAR", icon: "trash", variant: .ghost) { monitor.clearLog() }
                    .disabled(monitor.log.isEmpty)
                    .opacity(monitor.log.isEmpty ? 0.35 : 1.0)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.top, ConnektaktTheme.paddingXS)

            if monitor.log.isEmpty {
                Text("WAITING FOR MIDI TRAFFIC…")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
                    .padding(ConnektaktTheme.paddingMD)
            } else {
                ForEach(monitor.log) { entry in
                    LogEntryRow(entry: entry)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func diagSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(2)
                .padding(.horizontal, ConnektaktTheme.paddingXS)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .ckPanel()
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)
            Spacer()
            Text(value)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.primary)
                .tracking(1)
                .lineLimit(1)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.1)).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: MIDILogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.directionLabel)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(entry.direction == .tx ? ConnektaktTheme.accent : ConnektaktTheme.waveformGreen)
                    .tracking(1)

                Text(entry.timeString)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(0.5)

                Spacer()

                Text("\(entry.bytes.count)B")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
            }

            if entry.isSysEx {
                Text(entry.parsedDescription)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(0.5)
            }

            Text(entry.hexString)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(entry.direction == .tx
                    ? ConnektaktTheme.accent.opacity(0.8)
                    : ConnektaktTheme.waveformGreen.opacity(0.8))
                .lineLimit(3)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 8)
        .overlay(
            Rectangle().fill(ConnektaktTheme.primary.opacity(0.08)).frame(height: 1),
            alignment: .bottom
        )
    }
}

#Preview {
    MIDIDiagnosticsView()
        .environment(ConnectionManager())
}
