import SwiftUI
import CoreMIDI

struct MIDIDiagnosticsView: View {
    @Environment(ConnectionManager.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEntry: MIDILogEntry?
    @State private var testPath: String = ""

    private var monitor: MIDIMonitor { connection.midiMonitor }

    var body: some View {
        VStack(spacing: 0) {
            header
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
        .sheet(item: $selectedEntry) { entry in
            LogDetailView(entry: entry)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("MIDI DIAGNOSTICS")
                .font(ConnektaktTheme.titleFont)
                .foregroundStyle(ConnektaktTheme.textPrimary)
                .tracking(2)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(monitor.isRunning ? ConnektaktTheme.online : ConnektaktTheme.offline)
                    .frame(width: 6, height: 6)
                Text(monitor.isRunning ? "LIVE" : "OFF")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }
            CKButton("CLOSE", icon: "xmark", variant: .ghost) { dismiss() }
                .padding(.leading, ConnektaktTheme.paddingSM)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, ConnektaktTheme.paddingSM)
        .background(ConnektaktTheme.surface)
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
                CKButton("RESCAN", icon: "arrow.clockwise", variant: .secondary) { monitor.refresh() }
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
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, ConnektaktTheme.paddingMD)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.08)).frame(height: 1), alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Test Commands

    private var testCommandsSection: some View {
        diagSection("TEST COMMANDS") {
            let dst = monitor.destinations.first(where: \.isElektron)

            if let dst {
                VStack(spacing: ConnektaktTheme.paddingXS) {
                    infoRow("TARGET", dst.name)
                    HStack(spacing: ConnektaktTheme.paddingSM) {
                        CKButton("DEVICE INFO", icon: "info.circle", variant: .secondary) {
                            monitor.sendDeviceInfoRequest(to: dst.ref)
                        }
                        CKButton("STORAGE", icon: "internaldrive", variant: .secondary) {
                            monitor.sendStorageInfoRequest(to: dst.ref)
                        }
                        CKButton("LIST /", icon: "list.bullet", variant: .secondary) {
                            monitor.sendListRequest(to: dst.ref)
                        }
                    }
                    .padding(.horizontal, ConnektaktTheme.paddingMD)
                    .padding(.top, ConnektaktTheme.paddingSM)

                    // Open-reader probe: lets you test whether a specific path is readable
                    HStack(spacing: ConnektaktTheme.paddingSM) {
                        TextField("PATH TO TEST (e.g. /FOLDER/FILE.wav)", text: $testPath)
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(ConnektaktTheme.textPrimary)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(ConnektaktTheme.background)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(ConnektaktTheme.primary.opacity(0.4), lineWidth: 1))
                            #if os(iOS)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            #endif

                        CKButton("OPEN READER", icon: "doc.badge.arrow.up", variant: .secondary) {
                            monitor.sendOpenReaderRequest(path: testPath, to: dst.ref)
                        }
                        .disabled(testPath.isEmpty)
                        .opacity(testPath.isEmpty ? 0.35 : 1)
                    }
                    .padding(.horizontal, ConnektaktTheme.paddingMD)
                    .padding(.bottom, ConnektaktTheme.paddingSM)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(ConnektaktTheme.accent)
                        .font(.system(size: 11))
                    Text("NO ELEKTRON DESTINATION — CONNECT VIA USB")
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
            // Controls row
            HStack(spacing: ConnektaktTheme.paddingSM) {
                // PAUSE / RESUME
                CKButton(
                    monitor.isPaused ? "RESUME" : "PAUSE",
                    icon: monitor.isPaused ? "play.fill" : "pause.fill",
                    variant: monitor.isPaused ? .primary : .secondary
                ) {
                    monitor.isPaused.toggle()
                }

                CKButton("CLEAR", icon: "trash", variant: .ghost) { monitor.clearLog() }
                    .disabled(monitor.log.isEmpty)
                    .opacity(monitor.log.isEmpty ? 0.35 : 1.0)

                Spacer()

                Text("TAP ENTRY TO EXPAND")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(0.5)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.1)).frame(height: 1), alignment: .bottom)

            if monitor.log.isEmpty {
                Text("WAITING FOR MIDI TRAFFIC…")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
                    .padding(ConnektaktTheme.paddingMD)
            } else {
                // Scrollable log, newest at bottom, auto-scrolls to latest entry
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(monitor.log) { entry in
                                LogEntryRow(entry: entry)
                                    .onTapGesture { selectedEntry = entry }
                                    .id(entry.id)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: monitor.log.count) { _, _ in
                        guard !monitor.isPaused, let last = monitor.log.last else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        if let last = monitor.log.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
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
            VStack(alignment: .leading, spacing: 0) { content() }
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

// MARK: - Log Entry Row (compact, tap to expand)

private struct LogEntryRow: View {
    let entry: MIDILogEntry

    var body: some View {
        HStack(spacing: 8) {
            // Direction badge
            Text(entry.directionLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.direction == .tx ? ConnektaktTheme.accent : ConnektaktTheme.waveformGreen)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                // Time + length
                HStack(spacing: 6) {
                    Text(entry.timeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ConnektaktTheme.textMuted)
                    Text("\(entry.bytes.count)B")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ConnektaktTheme.textMuted)
                    if entry.isSysEx {
                        Text("SYSEX")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(ConnektaktTheme.primary.opacity(0.7))
                    }
                }
                // First 16 bytes preview
                Text(entry.hexString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(entry.direction == .tx
                        ? ConnektaktTheme.accent.opacity(0.9)
                        : ConnektaktTheme.waveformGreen.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(ConnektaktTheme.textMuted)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 7)
        .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.06)).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
    }
}

// MARK: - Log Detail View (full hex dump + parsed breakdown)

private struct LogDetailView: View {
    let entry: MIDILogEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(entry.directionLabel)
                            .font(ConnektaktTheme.titleFont)
                            .foregroundStyle(entry.direction == .tx ? ConnektaktTheme.accent : ConnektaktTheme.waveformGreen)
                        Text(entry.timeString)
                            .font(ConnektaktTheme.bodyFont)
                            .foregroundStyle(ConnektaktTheme.textMuted)
                        Text("· \(entry.bytes.count) BYTES")
                            .font(ConnektaktTheme.bodyFont)
                            .foregroundStyle(ConnektaktTheme.textMuted)
                    }
                    if entry.isSysEx {
                        Text(entry.parsedDescription)
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(ConnektaktTheme.textSecondary)
                            .tracking(0.5)
                    }
                }
                Spacer()
                CKButton("CLOSE", icon: "xmark", variant: .ghost) { dismiss() }
            }
            .padding(ConnektaktTheme.paddingMD)
            .background(ConnektaktTheme.surface)

            Rectangle().fill(ConnektaktTheme.primary.opacity(0.3)).frame(height: 2)

            ScrollView {
                VStack(alignment: .leading, spacing: ConnektaktTheme.paddingMD) {
                    // Formatted hex dump — 16 bytes per line with offsets
                    hexDump

                    // Elektron frame breakdown (if SysEx)
                    if entry.isSysEx {
                        frameBreakdown
                    }

                    // Copy button
                    HStack {
                        Spacer()
                        CKButton("COPY HEX", icon: "doc.on.doc", variant: .secondary) {
                            copyToClipboard(entry.fullHexDump)
                        }
                    }
                }
                .padding(ConnektaktTheme.paddingMD)
            }
        }
        .ckScreen()
    }

    // MARK: - Hex dump

    private var hexDump: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HEX DUMP")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(2)
                .padding(.bottom, 4)

            let lines = entry.bytes.chunked(into: 16)
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIdx, chunk in
                HStack(alignment: .top, spacing: 8) {
                    // Offset
                    Text(String(format: "%04X", lineIdx * 16))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .frame(width: 36, alignment: .leading)

                    // Hex bytes
                    Text(chunk.map { String(format: "%02X", $0) }.joined(separator: " "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(entry.direction == .tx ? ConnektaktTheme.accent : ConnektaktTheme.waveformGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(ConnektaktTheme.paddingMD)
        .ckPanel()
    }

    // MARK: - Elektron frame breakdown

    private var frameBreakdown: some View {
        let bytes = entry.bytes
        return VStack(alignment: .leading, spacing: 4) {
            // Raw header
            Text("ELEKTRON FRAME  (RAW BYTES)")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(2)
                .padding(.bottom, 4)

            if bytes.count >= 8 {
                let devFamily = bytes[4]
                frameRow("F0",       "SysEx start",           bytes[0])
                frameRow("MFR[0]",   "Elektron ID byte 1",    bytes[1])
                frameRow("MFR[1]",   "Elektron ID byte 2",    bytes[2])
                frameRow("MFR[2]",   "Elektron ID byte 3",    bytes[3])
                frameRow("FAMILY",   "Device family",         devFamily,
                         note: devFamily == 0x10 ? "✓ NEW-GEN (DIGITAKT)" : "⚠ UNKNOWN")
                frameRow("RESERVED", "Reserved (always 0x00)", bytes[5])
                let encodedLen = bytes.count - 7   // minus header(6) + F7(1)
                frameRow("BODY",     "7-bit encoded body",
                         note: "\(encodedLen) encoded bytes → ~\(encodedLen * 7 / 8) decoded")
                frameRow("F7",       "SysEx end",             bytes[bytes.count - 1])

                // Decoded body
                Divider().background(ConnektaktTheme.primary.opacity(0.2)).padding(.vertical, 4)

                Text("DECODED BODY  (AFTER 7-BIT DECODE)")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(2)
                    .padding(.bottom, 4)

                let encoded = Array(bytes[6..<bytes.count - 1])
                let decoded = ElektronSysEx.decode7bit(encoded)

                if decoded.count >= 5 {
                    let seq    = (UInt16(decoded[0]) << 8) | UInt16(decoded[1])
                    let cmdByte = decoded[4]
                    let isResp  = cmdByte & 0x80 != 0
                    let cmdName = ElektronMsgType(rawValue: cmdByte).map { "\($0)" }
                              ?? String(format: "0x%02X (UNKNOWN)", cmdByte)

                    frameRow("SEQ",   "Sequence number",
                             note: "\(seq)")
                    frameRow("CMD",   "Command byte",          cmdByte,
                             note: cmdName)

                    if isResp, decoded.count >= 6 {
                        let status = decoded[5]
                        frameRow("STATUS", "Response status",   status,
                                 note: status == 1 ? "✓ SUCCESS" : "✗ ERROR/REJECTED")
                        if decoded.count > 6 {
                            let payloadBytes = Array(decoded[6...])
                            let hex = payloadBytes.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                            let suffix = payloadBytes.count > 16 ? " …" : ""
                            frameRow("PAYLOAD", "\(payloadBytes.count) bytes",
                                     note: hex + suffix)
                        }
                    } else if !isResp, decoded.count > 5 {
                        let payloadBytes = Array(decoded[5...])
                        let hex = payloadBytes.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                        let suffix = payloadBytes.count > 16 ? " …" : ""
                        frameRow("PAYLOAD", "\(payloadBytes.count) bytes",
                                 note: hex + suffix)
                    }
                } else {
                    Text("DECODED BODY TOO SHORT")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.accent)
                }
            } else {
                Text("TOO SHORT TO PARSE")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.accent)
            }
        }
        .padding(ConnektaktTheme.paddingMD)
        .ckPanel()
    }

    @ViewBuilder
    private func frameRow(_ field: String, _ desc: String, _ byte: UInt8, note: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(field)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(String(format: "0x%02X", byte))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.primary)
            Text(desc)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.textMuted)
            if let note {
                Spacer()
                Text(note)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(note.hasPrefix("✓") ? ConnektaktTheme.waveformGreen : ConnektaktTheme.accent)
            }
        }
    }

    @ViewBuilder
    private func frameRow(_ field: String, _ desc: String, note: String) -> some View {
        HStack(spacing: 8) {
            Text(field)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(desc)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.textMuted)
            Spacer()
            Text(note)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.textMuted)
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - MIDILogEntry full hex dump

private extension MIDILogEntry {
    var fullHexDump: String {
        let lines = bytes.chunked(into: 16).enumerated().map { idx, chunk in
            let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            return String(format: "%04X: %@", idx * 16, hex)
        }
        return "[\(directionLabel) \(timeString) \(bytes.count)B]\n" + lines.joined(separator: "\n")
    }
}

// MARK: - Array chunked helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

#Preview {
    MIDIDiagnosticsView()
        .environment(ConnectionManager())
}
