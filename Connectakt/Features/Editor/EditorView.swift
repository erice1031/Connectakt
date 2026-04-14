import AVFoundation
import AudioToolbox
import ExtensionFoundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(ConnectionManager.self) private var connection
    @State private var model = EditorScreenModel()

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: "EDITOR", status: headerStatus)

            if model.hasLoadedSample {
                EditorWorkspaceView(model: model, connection: connection)
            } else {
                EditorEmptyView(
                    isLoading: model.isLoading,
                    onImport: { model.showFileImporter = true }
                )
            }
        }
        .ckScreen()
        .fileImporter(
            isPresented: $model.showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.load(url: url)
            case .failure(let error):
                model.errorMessage = error.localizedDescription.uppercased()
            }
        }
        .alert("EDITOR ERROR", isPresented: errorPresented) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "UNKNOWN ERROR")
        }
        .onChange(of: connection.pendingEditorURL) { _, url in
            guard let url else { return }
            model.load(url: url)
            connection.pendingEditorURL = nil
        }
    }

    private var headerStatus: ConnectionStatus {
        if let fileName = model.formatInfo?.fileName, model.hasLoadedSample {
            return .connected(deviceName: fileName)
        }
        return connection.status
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct EditorEmptyView: View {
    let isLoading: Bool
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(ConnektaktTheme.textMuted, lineWidth: 1)
                        .frame(width: 92, height: 92)

                    if isLoading {
                        ProgressView()
                            .tint(ConnektaktTheme.primary)
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 38, weight: .ultraLight))
                            .foregroundStyle(ConnektaktTheme.textSecondary)
                    }
                }

                VStack(spacing: 6) {
                    Text(isLoading ? "ANALYZING SAMPLE" : "NO SAMPLE LOADED")
                        .font(ConnektaktTheme.largeFont)
                        .foregroundStyle(ConnektaktTheme.textPrimary)
                        .tracking(2)

                    Text("IMPORT A FILE TO OPEN THE PHASE 4 EDITOR")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                        .tracking(1)
                }
                .multilineTextAlignment(.center)

                CKButton("IMPORT AUDIO FILE", icon: "doc.badge.plus", variant: .primary, action: onImport)
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.4 : 1.0)
            }

            Spacer()

            VStack(spacing: 8) {
                Rectangle()
                    .fill(ConnektaktTheme.primary.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal)

                VStack(spacing: 4) {
                    Text("PHASE 4 TOOLSET")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(2)

                    HStack(spacing: ConnektaktTheme.paddingMD) {
                        featureTag("TRIM")
                        featureTag("FADE")
                        featureTag("PITCH")
                        featureTag("STRETCH")
                        featureTag("UPLOAD")
                    }
                }
                .padding(.bottom, ConnektaktTheme.paddingLG)
            }
        }
    }

    @ViewBuilder
    private func featureTag(_ text: String) -> some View {
        Text(text)
            .font(ConnektaktTheme.smallFont)
            .foregroundStyle(ConnektaktTheme.textMuted)
            .tracking(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ConnektaktTheme.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct EditorWorkspaceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: EditorScreenModel
    let connection: ConnectionManager

    var body: some View {
        VStack(spacing: 0) {
            metadataBar

            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.15))
                .frame(height: 1)

            ScrollView {
                VStack(spacing: ConnektaktTheme.paddingMD) {
                    analysisStrip
                    waveformSection
                    trimStrip
                    transportStrip
                    editControls
                    effectsSection
                    exportSection
                }
                .padding(ConnektaktTheme.paddingMD)
            }
        }
        .task {
            model.primeEffectBrowser()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            model.refreshAvailableEffects()
        }
    }

    private var metadataBar: some View {
        HStack(spacing: ConnektaktTheme.paddingSM) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.formatInfo?.fileName ?? "UNKNOWN")
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .lineLimit(1)

                Text(model.fileSummaryLine)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)
                    .lineLimit(1)
            }

            Spacer()

            CKButton("NEW FILE", icon: "doc.badge.plus", variant: .secondary) {
                model.showFileImporter = true
            }

            CKButton("CLOSE", variant: .ghost) {
                model.close()
            }
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, ConnektaktTheme.paddingSM)
        .background(ConnektaktTheme.surface)
    }

    private var analysisStrip: some View {
        HStack(spacing: ConnektaktTheme.paddingSM) {
            badge("LEN", model.trimLengthDisplay, tone: .primary)
            badge("BPM", model.analysis?.bpmLabel ?? "SCAN", tone: .secondary)
            badge("KEY", model.analysis?.keyLabel ?? "SCAN", tone: .secondary)
            badge("FX", "\(model.effectChainState.items.count)", tone: .secondary)
            badge("ZOOM", "\(Int(model.settings.zoom * 100))%", tone: .secondary)
            Spacer()
            if !model.operationLabel.isEmpty {
                Text(model.operationLabel)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.accent)
                    .tracking(1)
            }
        }
        .padding(.horizontal, ConnektaktTheme.paddingSM)
        .padding(.vertical, ConnektaktTheme.paddingSM)
        .background(ConnektaktTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius)
                .strokeBorder(ConnektaktTheme.primary.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func badge(_ label: String, _ value: String, tone: BadgeTone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)
            Text(value)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(tone.color)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tone.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var waveformSection: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                let width = max(geo.size.width, geo.size.width * model.settings.zoom)
                ZStack {
                    waveformCanvas(width: width)
                }
                .frame(width: width, height: 180)
                .background(ConnektaktTheme.surface)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius)
                .strokeBorder(ConnektaktTheme.primary.opacity(0.15), lineWidth: 1)
        )
    }

    private func waveformCanvas(width: CGFloat) -> some View {
        Canvas { context, size in
            drawWaveform(context: &context, size: size)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    model.handleWaveformDrag(
                        locationX: drag.location.x,
                        contentWidth: width
                    )
                }
                .onEnded { _ in
                    model.endWaveformDrag()
                }
        )
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        let midY = height / 2
        let duration = max(model.durationSeconds, 0.001)
        let peaks = model.waveformPeaks

        if !peaks.isEmpty {
            let barWidth = width / CGFloat(peaks.count)
            for (index, peak) in peaks.enumerated() {
                let x = CGFloat(index) * barWidth
                let time = Double(index) / Double(max(peaks.count - 1, 1)) * duration
                let amplitude = CGFloat(peak) * midY * 0.9
                let inTrim = time >= model.settings.trimStart && time <= model.settings.trimEnd
                let color = inTrim
                    ? ConnektaktTheme.waveformGreen
                    : ConnektaktTheme.waveformGreen.opacity(0.18)
                let rect = CGRect(
                    x: x,
                    y: midY - amplitude,
                    width: max(barWidth - 0.5, 0.5),
                    height: max(amplitude * 2, 1)
                )
                context.fill(Path(rect), with: .color(color))
            }
        }

        if let grid = model.makeMusicalGrid() {
            let range = 0.0...duration
            for t in grid.barTimes(in: range) {
                let x = CGFloat(t / duration) * width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(ConnektaktTheme.primary.opacity(0.45)), lineWidth: 1)
            }
            for t in grid.beatTimes(in: range) where !grid.barTimes(in: range).contains(where: { abs($0 - t) < 0.001 }) {
                let x = CGFloat(t / duration) * width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(ConnektaktTheme.primary.opacity(0.16)), lineWidth: 0.5)
            }
        }

        let startX = CGFloat(model.settings.trimStart / duration) * width
        let endX = CGFloat(model.settings.trimEnd / duration) * width
        let shade = ConnektaktTheme.background.opacity(0.6)
        context.fill(Path(CGRect(x: 0, y: 0, width: startX, height: height)), with: .color(shade))
        context.fill(Path(CGRect(x: endX, y: 0, width: width - endX, height: height)), with: .color(shade))

        let knobHeight: CGFloat = 18
        context.stroke(
            Path { path in
                path.move(to: CGPoint(x: startX, y: 0))
                path.addLine(to: CGPoint(x: startX, y: height))
            },
            with: .color(ConnektaktTheme.waveformGreen),
            lineWidth: 2
        )
        context.fill(
            Path(roundedRect: CGRect(x: startX - 7, y: 0, width: 14, height: knobHeight), cornerRadius: 3),
            with: .color(ConnektaktTheme.waveformGreen)
        )

        context.stroke(
            Path { path in
                path.move(to: CGPoint(x: endX, y: 0))
                path.addLine(to: CGPoint(x: endX, y: height))
            },
            with: .color(ConnektaktTheme.accent),
            lineWidth: 2
        )
        context.fill(
            Path(roundedRect: CGRect(x: endX - 7, y: height - knobHeight, width: 14, height: knobHeight), cornerRadius: 3),
            with: .color(ConnektaktTheme.accent)
        )
    }

    private var trimStrip: some View {
        VStack(spacing: ConnektaktTheme.paddingSM) {
            HStack(spacing: ConnektaktTheme.paddingMD) {
                trimValue(label: "IN", value: model.trimStartDisplay, color: ConnektaktTheme.waveformGreen)
                trimValue(label: "OUT", value: model.trimEndDisplay, color: ConnektaktTheme.accent)
                trimValue(label: "LEN", value: model.trimLengthDisplay, color: ConnektaktTheme.textPrimary)
                Spacer()
            }

            VStack(spacing: 10) {
                labeledSlider(
                    title: "TRIM START",
                    value: $model.settings.trimStart,
                    range: 0...max(model.settings.trimEnd - 0.01, 0.01),
                    step: 0.01
                )
                labeledSlider(
                    title: "TRIM END",
                    value: $model.settings.trimEnd,
                    range: min(model.settings.trimStart + 0.01, model.durationSeconds)...max(model.durationSeconds, 0.01),
                    step: 0.01
                )
                labeledSlider(
                    title: "ZOOM",
                    value: $model.settings.zoom,
                    range: 1...8,
                    step: 0.1
                )
            }
        }
        .padding(ConnektaktTheme.paddingMD)
        .background(ConnektaktTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius))
    }

    @ViewBuilder
    private func trimValue(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
            Text(value)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func labeledSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
                Spacer()
                Text(formattedValue(for: title, value: value.wrappedValue))
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
                .tint(ConnektaktTheme.primary)
        }
    }

    private func formattedValue(for title: String, value: Double) -> String {
        switch title {
        case "ZOOM":
            return "\(Int(value * 100))%"
        default:
            return model.formatSeconds(value)
        }
    }

    private var transportStrip: some View {
        HStack(spacing: ConnektaktTheme.paddingSM) {
            CKButton(
                model.isPlayingPreview ? "STOP" : "PREVIEW",
                icon: model.isPlayingPreview ? "stop.fill" : "play.fill",
                variant: .secondary
            ) {
                model.isPlayingPreview ? model.stopPreview() : model.preview()
            }

            if model.isBusy {
                ProgressView()
                    .tint(ConnektaktTheme.primary)
            }

            if let shareURL = model.shareURL {
                ShareLink(item: shareURL) {
                    label("SHARE WAV", icon: "square.and.arrow.up")
                }
            } else {
                CKButton("RENDER WAV", icon: "square.and.arrow.up", variant: .ghost) {
                    model.renderShareFile()
                }
            }

            Spacer()

            toggle("NORMALIZE", isOn: $model.settings.normalize)
            toggle("REVERSE", isOn: $model.settings.reverse)
        }
        .padding(ConnektaktTheme.paddingMD)
        .background(ConnektaktTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius))
    }

    @ViewBuilder
    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(isOn.wrappedValue ? ConnektaktTheme.background : ConnektaktTheme.textSecondary)
                .tracking(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? ConnektaktTheme.primary : ConnektaktTheme.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func label(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(ConnektaktTheme.smallFont)
        .foregroundStyle(ConnektaktTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ConnektaktTheme.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var editControls: some View {
        VStack(spacing: ConnektaktTheme.paddingSM) {
            editorSection(title: "LEVEL + ENVELOPE") {
                labeledSlider(title: "FADE IN", value: $model.settings.fadeInDuration, range: 0...model.maxFadeDuration, step: 0.01)
                labeledSlider(title: "FADE OUT", value: $model.settings.fadeOutDuration, range: 0...model.maxFadeDuration, step: 0.01)
            }

            editorSection(title: "PITCH + STRETCH") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("PITCH")
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(ConnektaktTheme.textMuted)
                        Spacer()
                        Text(String(format: "%+.1f ST", model.settings.pitchSemitones))
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(ConnektaktTheme.textSecondary)
                    }
                    Slider(value: $model.settings.pitchSemitones, in: -12...12, step: 0.5)
                        .tint(ConnektaktTheme.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("STRETCH")
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(ConnektaktTheme.textMuted)
                        Spacer()
                        Text(String(format: "%.0f%%", model.settings.timeStretchRatio * 100))
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(ConnektaktTheme.textSecondary)
                    }
                    Slider(value: $model.settings.timeStretchRatio, in: 0.5...2.0, step: 0.05)
                        .tint(ConnektaktTheme.primary)
                }
            }
        }
    }

    private var effectsSection: some View {
        editorSection(title: "AUV3 CHAIN") {
            HStack(spacing: ConnektaktTheme.paddingSM) {
                if model.isScanningEffects {
                    ProgressView()
                        .tint(ConnektaktTheme.primary)
                }

                Text("\(model.availableEffects.count) EFFECTS")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)

                Spacer()

                CKButton("REFRESH FX", icon: "arrow.clockwise", variant: .ghost) {
                    model.refreshAvailableEffects()
                }
                .disabled(model.isScanningEffects)
                .opacity(model.isScanningEffects ? 0.4 : 1.0)
            }

            Text("SIGNAL PATH RUNS TOP → BOTTOM → OUTPUT. NEW EFFECTS APPEND TO THE BOTTOM OF THE CHAIN.")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)

            if model.discoveredAudioUnits.count != model.availableEffects.count {
                Text("\(model.discoveredAudioUnits.count) TOTAL AUDIO UNITS DISCOVERED • \(model.availableEffects.count) SUPPORTED FOR THE SAMPLE CHAIN")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }

            if let extensionSummary = model.audioUnitExtensionSummary {
                Text(extensionSummary)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }

            Text("IF A PURCHASED AU IS MISSING, OPEN ITS MAIN APP ON THIS DEVICE ONCE, RETURN TO CONNECTAKT, AND REFRESH FX.")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)

            if model.availableEffects.isEmpty {
                Text("NO AUDIO UNITS DISCOVERED YET")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            } else {
                Picker("AVAILABLE FX", selection: $model.selectedAvailableEffectID) {
                    Text("SELECT EFFECT").tag(Optional<String>.none)
                    ForEach(model.availableEffects) { effect in
                        Text(effect.menuLabel).tag(Optional(effect.id))
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text(model.selectedEffectSummary)
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    CKButton("ADD TO BOTTOM", icon: "plus", variant: .secondary) {
                        model.addSelectedEffect()
                    }
                    .disabled(model.selectedAvailableEffectID == nil)
                    .opacity(model.selectedAvailableEffectID == nil ? 0.4 : 1.0)
                }
            }

            if model.effectChainState.items.isEmpty {
                Text("CHAIN IS EMPTY. ADD AN EFFECT TO ROUTE PREVIEW, FREEZE, AND EXPORT THROUGH AUV3.")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.effectChainState.items.enumerated()), id: \.element.id) { index, item in
                        effectRow(item: item, index: index)
                    }
                }
            }

            if !model.unsupportedDiscoveredAudioUnits.isEmpty {
                unsupportedUnitsSection
            }

            if !model.audioUnitExtensionIdentities.isEmpty {
                extensionIdentitySection
            }

            if !model.effectChainState.items.isEmpty {
                effectParameterSection
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("CHAIN PRESETS")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)

                TextField("Preset Name", text: $model.presetNameDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: ConnektaktTheme.paddingSM) {
                    CKButton("SAVE PRESET", icon: "square.and.arrow.down", variant: .secondary) {
                        model.saveCurrentPreset()
                    }
                    .disabled(model.effectChainState.items.isEmpty)
                    .opacity(model.effectChainState.items.isEmpty ? 0.4 : 1.0)

                    Picker("SAVED PRESETS", selection: $model.selectedPresetID) {
                        Text("SELECT PRESET").tag(Optional<UUID>.none)
                        ForEach(model.effectPresets) { preset in
                            Text(preset.name).tag(Optional(preset.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: ConnektaktTheme.paddingSM) {
                    CKButton("LOAD PRESET", icon: "square.and.arrow.down.on.square", variant: .ghost) {
                        model.loadSelectedPreset()
                    }
                    .disabled(model.selectedPresetID == nil)
                    .opacity(model.selectedPresetID == nil ? 0.4 : 1.0)

                    CKButton("DELETE PRESET", icon: "trash", variant: .ghost) {
                        model.deleteSelectedPreset()
                    }
                    .disabled(model.selectedPresetID == nil)
                    .opacity(model.selectedPresetID == nil ? 0.4 : 1.0)
                }
            }
        }
    }

    @ViewBuilder
    private func effectRow(item: EditorEffectChainItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: ConnektaktTheme.paddingSM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(ConnektaktTheme.bodyFont)
                        .foregroundStyle(item.isBypassed ? ConnektaktTheme.textMuted : ConnektaktTheme.textPrimary)
                        .lineLimit(1)
                    Text(item.descriptor.menuLabel)
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(String(format: "%02d", index + 1))
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.accent)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Button {
                    model.selectChainEffect(id: item.id)
                } label: {
                    Text(model.selectedChainEffectID == item.id ? "EDITING" : "EDIT")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(model.selectedChainEffectID == item.id ? ConnektaktTheme.background : ConnektaktTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(model.selectedChainEffectID == item.id ? ConnektaktTheme.accent : ConnektaktTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                Button {
                    model.toggleEffectBypass(id: item.id)
                } label: {
                    Text(item.isBypassed ? "BYPASSED" : "ACTIVE")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(item.isBypassed ? ConnektaktTheme.textSecondary : ConnektaktTheme.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(item.isBypassed ? ConnektaktTheme.surfaceHigh : ConnektaktTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                Button {
                    model.moveEffect(id: item.id, direction: -1)
                } label: {
                    label("EARLIER", icon: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .opacity(index == 0 ? 0.35 : 1.0)

                Button {
                    model.moveEffect(id: item.id, direction: 1)
                } label: {
                    label("LATER", icon: "arrow.down")
                }
                .buttonStyle(.plain)
                .disabled(index == model.effectChainState.items.count - 1)
                .opacity(index == model.effectChainState.items.count - 1 ? 0.35 : 1.0)

                Button {
                    model.removeEffect(id: item.id)
                } label: {
                    label("REMOVE", icon: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(ConnektaktTheme.paddingSM)
        .background(model.selectedChainEffectID == item.id ? ConnektaktTheme.primary.opacity(0.08) : ConnektaktTheme.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var effectParameterSection: some View {
        VStack(alignment: .leading, spacing: ConnektaktTheme.paddingSM) {
            HStack {
                Text("PARAMETERS")
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(1)
                Spacer()
                Text(model.selectedChainEffectName)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .lineLimit(1)
            }

            if model.isLoadingEffectParameters {
                ProgressView()
                    .tint(ConnektaktTheme.primary)
            } else if model.selectedEffectParameters.isEmpty {
                Text("NO EXPOSED PARAMETERS FOR THE SELECTED EFFECT.")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.selectedEffectParameters) { parameter in
                        parameterRow(parameter)
                    }
                }
            }
        }
        .padding(ConnektaktTheme.paddingMD)
        .background(ConnektaktTheme.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var unsupportedUnitsSection: some View {
        VStack(alignment: .leading, spacing: ConnektaktTheme.paddingSM) {
            Text("OTHER DISCOVERED AUDIO UNITS")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)

            Text("These units are installed, but they are not currently treated as insertable sample-chain effects.")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)

            ForEach(model.unsupportedDiscoveredAudioUnits.prefix(8)) { unit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.menuLabel)
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                    Text(unit.typeSummary)
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                }
            }
        }
        .padding(ConnektaktTheme.paddingMD)
        .background(ConnektaktTheme.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var extensionIdentitySection: some View {
        VStack(alignment: .leading, spacing: ConnektaktTheme.paddingSM) {
            Text("REGISTERED AUDIO UNIT EXTENSIONS")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)

            Text("This comes from the iOS extension registry rather than the audio component picker.")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)

            ForEach(model.audioUnitExtensionIdentities.prefix(12)) { identity in
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.localizedName.uppercased())
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                    Text("\(identity.bundleIdentifier) • \(identity.extensionPointIdentifier)")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                }
            }
        }
        .padding(ConnektaktTheme.paddingMD)
        .background(ConnektaktTheme.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func parameterRow(_ parameter: EditorEffectParameterDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.displayName)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(1)
                Spacer()
                Text(parameter.formattedValue)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(parameter.currentValue) },
                    set: { model.updateSelectedEffectParameter(address: parameter.address, value: Float($0)) }
                ),
                in: Double(parameter.minValue)...Double(parameter.maxValue)
            )
            .tint(ConnektaktTheme.primary)
        }
    }

    @ViewBuilder
    private func editorSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ConnektaktTheme.paddingSM) {
            Text(title)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(2)
            content()
        }
        .padding(ConnektaktTheme.paddingMD)
        .background(ConnektaktTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ConnektaktTheme.cornerRadius))
    }

    private var exportSection: some View {
        HStack(spacing: ConnektaktTheme.paddingMD) {
            CKButton("RENDER WAV", icon: "waveform.path", variant: .secondary) {
                model.renderShareFile()
            }

            CKButton("FREEZE FX", icon: "snowflake", variant: .ghost) {
                model.freezeProcessedSample()
            }
            .disabled(model.effectChainState.items.isEmpty || model.isLoading)
            .opacity(model.effectChainState.items.isEmpty || model.isLoading ? 0.35 : 1.0)

            Spacer()

            CKButton("OPTIMIZE + UPLOAD", icon: "arrow.up.circle.fill", variant: .primary) {
                model.optimizeAndUpload(using: connection.transfer)
            }
            .disabled(!connection.status.isConnected || model.isLoading)
            .opacity(!connection.status.isConnected || model.isLoading ? 0.35 : 1.0)
        }
        .padding(.top, ConnektaktTheme.paddingSM)
    }
}

private enum BadgeTone {
    case primary
    case secondary

    var color: Color {
        switch self {
        case .primary: return ConnektaktTheme.textPrimary
        case .secondary: return ConnektaktTheme.textSecondary
        }
    }
}

@MainActor
@Observable
final class EditorScreenModel {
    var showFileImporter = false
    var isLoading = false
    var isScanningEffects = false
    var waveformPeaks: [Float] = []
    var formatInfo: AudioFormatInfo?
    var analysis: EditorAnalysisSummary?
    var discoveredAudioUnits: [EditorEffectDescriptor] = []
    var availableEffects: [EditorEffectDescriptor] = []
    var audioUnitExtensionIdentities: [EditorAudioUnitExtensionIdentity] = []
    var selectedAvailableEffectID: String?
    var selectedChainEffectID: UUID?
    var selectedEffectParameters: [EditorEffectParameterDescriptor] = []
    var isLoadingEffectParameters = false
    var effectChainState = EditorEffectChainState() {
        didSet {
            if effectChainState != oldValue {
                invalidateRenderedArtifacts()
            }
        }
    }
    var effectPresets: [EditorEffectPreset]
    var selectedPresetID: UUID?
    var presetNameDraft = ""
    var settings = EditorEditSettings() {
        didSet {
            if settings != oldValue {
                invalidateRenderedArtifacts()
            }
        }
    }
    var durationSeconds: Double = 0
    var errorMessage: String?
    var shareURL: URL?
    var isPlayingPreview = false
    var operationPhase: EditorOperationPhase = .idle

    @ObservationIgnored private var monoSamples: [Float] = []
    @ObservationIgnored private var sampleRate: Double = 44100
    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var previewPlayer: AVAudioPlayer?
    @ObservationIgnored private var lastRenderedPreviewURL: URL?

    init() {
        effectPresets = EditorEffectPresetStore.load()
        selectedPresetID = effectPresets.first?.id
    }

    var hasLoadedSample: Bool {
        sourceURL != nil
    }

    var isBusy: Bool {
        switch operationPhase {
        case .idle, .complete, .failed:
            return false
        case .renderingPreview, .renderingShareFile, .optimizing, .uploading:
            return true
        }
    }

    var fileSummaryLine: String {
        guard let info = formatInfo else { return "NO FILE" }
        return "\(info.bitDepthString) / \(info.sampleRateString) / \(info.channelString) / \(info.durationString)"
    }

    var trimStartDisplay: String { formatSeconds(settings.trimStart) }
    var trimEndDisplay: String { formatSeconds(settings.trimEnd) }
    var trimLengthDisplay: String { formatSeconds(max(settings.trimEnd - settings.trimStart, 0)) }

    var maxFadeDuration: Double {
        max((settings.trimEnd - settings.trimStart) * 0.95, 0.01)
    }

    var operationLabel: String {
        switch operationPhase {
        case .idle:
            return ""
        case .renderingPreview:
            return "RENDERING PREVIEW"
        case .renderingShareFile:
            return "PREPARING EXPORT"
        case .optimizing(let progress):
            return String(format: "OPTIMIZING %.0f%%", progress * 100)
        case .uploading(let progress):
            return String(format: "UPLOADING %.0f%%", progress * 100)
        case .complete(let message):
            return message
        case .failed(let message):
            return message
        }
    }

    func load(url: URL) {
        Task {
            await loadSample(url: url)
        }
    }

    func primeEffectBrowser() {
        guard availableEffects.isEmpty, !isScanningEffects else { return }
        refreshAvailableEffects()
    }

    func close() {
        stopPreview()
        cleanupRenderedFiles()
        removeSourceFile()
        monoSamples = []
        waveformPeaks = []
        formatInfo = nil
        analysis = nil
        durationSeconds = 0
        settings = EditorEditSettings()
        effectChainState = EditorEffectChainState()
        selectedChainEffectID = nil
        selectedEffectParameters = []
        sourceURL = nil
        operationPhase = .idle
    }

    func preview() {
        Task {
            do {
                operationPhase = .renderingPreview
                let url = try await renderPreviewWAV()
                lastRenderedPreviewURL = url
                let player = try AVAudioPlayer(contentsOf: url)
                previewPlayer = player
                player.play()
                isPlayingPreview = true
                operationPhase = .idle
                let playbackDuration = player.duration
                Task { [weak self, weak player] in
                    let nanos = UInt64(max(playbackDuration, 0) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    await MainActor.run {
                        guard let self, let player, self.previewPlayer === player, !player.isPlaying else { return }
                        self.isPlayingPreview = false
                    }
                }
            } catch {
                operationPhase = .failed("PREVIEW FAILED")
                errorMessage = error.localizedDescription.uppercased()
            }
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPlayingPreview = false
    }

    func renderShareFile() {
        Task {
            do {
                operationPhase = .renderingShareFile
                shareURL = try await renderDigitaktWAV()
                operationPhase = .complete("EXPORT READY")
            } catch {
                operationPhase = .failed("EXPORT FAILED")
                errorMessage = error.localizedDescription.uppercased()
            }
        }
    }

    func optimizeAndUpload(using transfer: (any DigitaktTransferProtocol)?) {
        guard let transfer else {
            errorMessage = "DIGITAKT NOT CONNECTED"
            return
        }

        Task {
            do {
                let resultURL = try await renderDigitaktWAV()
                operationPhase = .uploading(0)
                try await transfer.uploadSample(
                    localURL: resultURL,
                    remotePath: "SAMPLES/\(resultURL.lastPathComponent)"
                ) { [weak self] transferProgress in
                    Task { @MainActor [weak self] in
                        self?.operationPhase = .uploading(transferProgress.fraction)
                    }
                }

                try? FileManager.default.removeItem(at: resultURL)
                operationPhase = .complete("UPLOAD COMPLETE")
            } catch {
                operationPhase = .failed("UPLOAD FAILED")
                errorMessage = error.localizedDescription.uppercased()
            }
        }
    }

    func refreshAvailableEffects() {
        guard !isScanningEffects else { return }
        isScanningEffects = true
        Task {
            async let discoveredTask = SampleEditorProcessor.discoverAudioUnits()
            async let extensionTask = SampleEditorProcessor.discoverAudioUnitExtensions()
            let discovered = await discoveredTask
            let extensionIdentities = await extensionTask
            discoveredAudioUnits = discovered
            audioUnitExtensionIdentities = extensionIdentities
            let supported = discovered.filter(\.isSupportedEffectType)
            availableEffects = supported
            if selectedAvailableEffectID == nil || !supported.contains(where: { $0.id == selectedAvailableEffectID }) {
                selectedAvailableEffectID = supported.first?.id
            }
            isScanningEffects = false
        }
    }

    func addSelectedEffect() {
        guard let selectedAvailableEffect else { return }
        let item = EditorEffectChainItem(descriptor: selectedAvailableEffect)
        effectChainState.items.append(item)
        selectedChainEffectID = item.id
        inspectSelectedChainEffect()
    }

    func toggleEffectBypass(id: UUID) {
        guard let index = effectChainState.items.firstIndex(where: { $0.id == id }) else { return }
        effectChainState.items[index].isBypassed.toggle()
    }

    func moveEffect(id: UUID, direction: Int) {
        guard let index = effectChainState.items.firstIndex(where: { $0.id == id }) else { return }
        let destination = (index + direction).clamped(to: 0...(effectChainState.items.count - 1))
        guard destination != index else { return }
        let item = effectChainState.items.remove(at: index)
        effectChainState.items.insert(item, at: destination)
    }

    func removeEffect(id: UUID) {
        effectChainState.items.removeAll { $0.id == id }
        if selectedChainEffectID == id {
            selectedChainEffectID = effectChainState.items.first?.id
            inspectSelectedChainEffect()
        }
    }

    func selectChainEffect(id: UUID) {
        guard selectedChainEffectID != id else { return }
        selectedChainEffectID = id
        inspectSelectedChainEffect()
    }

    func updateSelectedEffectParameter(address: UInt64, value: Float) {
        guard let selectedChainEffectID,
              let itemIndex = effectChainState.items.firstIndex(where: { $0.id == selectedChainEffectID }),
              let parameterIndex = selectedEffectParameters.firstIndex(where: { $0.address == address }) else { return }

        selectedEffectParameters[parameterIndex].currentValue = value

        var snapshots = effectChainState.items[itemIndex].parameterSnapshots
        if let snapshotIndex = snapshots.firstIndex(where: { $0.address == address }) {
            snapshots[snapshotIndex].value = value
        } else {
            let descriptor = selectedEffectParameters[parameterIndex]
            snapshots.append(
                EditorEffectParameterSnapshot(
                    address: address,
                    identifier: descriptor.identifier,
                    value: value
                )
            )
        }
        effectChainState.items[itemIndex].parameterSnapshots = snapshots.sorted { $0.address < $1.address }
    }

    func saveCurrentPreset() {
        guard !effectChainState.items.isEmpty else { return }
        let trimmedName = presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "CHAIN \(effectPresets.count + 1)" : trimmedName.uppercased()
        let preset = EditorEffectPreset(name: name, chain: effectChainState)
        effectPresets = EditorEffectPresetStore.upsert(preset: preset, existing: effectPresets)
        selectedPresetID = preset.id
        presetNameDraft = name
    }

    func loadSelectedPreset() {
        guard let preset = selectedPreset else { return }
        effectChainState = preset.chain
        selectedChainEffectID = preset.chain.items.first?.id
        presetNameDraft = preset.name
        operationPhase = .complete("PRESET LOADED")
        inspectSelectedChainEffect()
    }

    func deleteSelectedPreset() {
        guard let selectedPresetID else { return }
        effectPresets = EditorEffectPresetStore.delete(id: selectedPresetID, existing: effectPresets)
        self.selectedPresetID = effectPresets.first?.id
    }

    func freezeProcessedSample() {
        guard hasLoadedSample else { return }
        Task {
            do {
                stopPreview()
                cleanupRenderedFiles()
                operationPhase = .renderingShareFile
                let frozenURL = try await renderPreviewWAV()
                try await loadPreparedSample(localURL: frozenURL, clearEffectChain: true, removePreviousSource: true)
                operationPhase = .complete("CHAIN FROZEN")
            } catch {
                operationPhase = .failed("FREEZE FAILED")
                errorMessage = error.localizedDescription.uppercased()
            }
        }
    }

    func handleWaveformDrag(locationX: CGFloat, contentWidth: CGFloat) {
        guard durationSeconds > 0, contentWidth > 0 else { return }
        let rawTime = Double(locationX / contentWidth) * durationSeconds

        if activeTrimHandle == nil {
            let startX = CGFloat(settings.trimStart / durationSeconds) * contentWidth
            let endX = CGFloat(settings.trimEnd / durationSeconds) * contentWidth
            activeTrimHandle = abs(locationX - startX) <= abs(locationX - endX) ? .start : .end
        }

        let clamped = rawTime.clamped(to: 0...durationSeconds)
        switch activeTrimHandle {
        case .start:
            settings.trimStart = min(clamped, settings.trimEnd - 0.01)
        case .end:
            settings.trimEnd = max(clamped, settings.trimStart + 0.01)
        case .none:
            break
        }
        clampSettings()
    }

    func endWaveformDrag() {
        activeTrimHandle = nil
    }

    func makeMusicalGrid() -> MusicalGrid? {
        guard let bpm = analysis?.bpm, let beatPhase = analysis?.beatPhase else { return nil }
        return MusicalGrid(bpm: bpm, beatPhase: beatPhase)
    }

    func formatSeconds(_ value: Double) -> String {
        let clamped = max(value, 0)
        let minutes = Int(clamped) / 60
        let seconds = clamped - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }

    var selectedEffectSummary: String {
        guard let selectedAvailableEffect else { return "SELECT AN INSTALLED AUDIO UNIT EFFECT" }
        return "\(selectedAvailableEffect.name.uppercased()) • \(selectedAvailableEffect.manufacturerDisplay)"
    }

    var unsupportedDiscoveredAudioUnits: [EditorEffectDescriptor] {
        discoveredAudioUnits.filter { !$0.isSupportedEffectType }
    }

    var audioUnitExtensionSummary: String? {
        guard !audioUnitExtensionIdentities.isEmpty else { return nil }
        return "\(audioUnitExtensionIdentities.count) AUDIO UNIT EXTENSIONS REGISTERED WITH IOS"
    }

    var selectedChainEffectName: String {
        selectedChainItem?.displayName ?? "NO EFFECT SELECTED"
    }

    private var selectedAvailableEffect: EditorEffectDescriptor? {
        guard let selectedAvailableEffectID else { return nil }
        return availableEffects.first(where: { $0.id == selectedAvailableEffectID })
    }

    private var selectedPreset: EditorEffectPreset? {
        guard let selectedPresetID else { return nil }
        return effectPresets.first(where: { $0.id == selectedPresetID })
    }

    private var selectedChainItem: EditorEffectChainItem? {
        guard let selectedChainEffectID else { return nil }
        return effectChainState.items.first(where: { $0.id == selectedChainEffectID })
    }

    @ObservationIgnored private var activeTrimHandle: TrimHandle?

    private enum TrimHandle {
        case start
        case end
    }

    private func loadSample(url: URL) async {
        isLoading = true
        operationPhase = .idle
        stopPreview()
        cleanupRenderedFiles()
        removeSourceFile()

        do {
            let localURL = try Self.copyIntoTemporaryDirectory(url: url)
            try await loadPreparedSample(localURL: localURL, clearEffectChain: false, removePreviousSource: false)
        } catch {
            errorMessage = error.localizedDescription.uppercased()
        }

        isLoading = false
    }

    private func renderPreviewWAV() async throws -> URL {
        guard !monoSamples.isEmpty else {
            throw EditorError.noSampleLoaded
        }

        clampSettings()
        return try await SampleEditorProcessor.renderEditedWAV(
            samples: monoSamples,
            sampleRate: sampleRate,
            settings: settings,
            effectChain: effectChainState,
            baseName: formatInfo?.fileName ?? "EDIT"
        )
    }

    private func renderDigitaktWAV() async throws -> URL {
        let editedURL = try await renderPreviewWAV()
        let optimizer = AudioOptimizer()
        operationPhase = .optimizing(0)
        do {
            let result = try await optimizer.optimize(url: editedURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.operationPhase = .optimizing(progress)
                }
            }
            try? FileManager.default.removeItem(at: editedURL)
            return result.outputURL
        } catch {
            try? FileManager.default.removeItem(at: editedURL)
            throw error
        }
    }

    private func cleanupRenderedFiles() {
        for url in [shareURL, lastRenderedPreviewURL] {
            if let url { try? FileManager.default.removeItem(at: url) }
        }
        shareURL = nil
        lastRenderedPreviewURL = nil
    }

    private func removeSourceFile() {
        if let sourceURL {
            try? FileManager.default.removeItem(at: sourceURL)
        }
    }

    private func invalidateRenderedArtifacts() {
        if let shareURL {
            try? FileManager.default.removeItem(at: shareURL)
        }
        if let lastRenderedPreviewURL {
            try? FileManager.default.removeItem(at: lastRenderedPreviewURL)
        }
        shareURL = nil
        lastRenderedPreviewURL = nil
        stopPreview()
        if case .complete = operationPhase {
            operationPhase = .idle
        }
    }

    private func loadPreparedSample(localURL: URL, clearEffectChain: Bool, removePreviousSource: Bool) async throws {
        let previousSourceURL = sourceURL
        let info = try await AudioOptimizer.analyzeFormat(at: localURL)
        let loaded = try await SampleEditorProcessor.loadMonoSamples(from: localURL)
        let editorAnalysis = await SampleEditorProcessor.analyze(url: localURL, samples: loaded.samples, sampleRate: loaded.sampleRate)

        sourceURL = localURL
        formatInfo = info
        monoSamples = loaded.samples
        sampleRate = loaded.sampleRate
        durationSeconds = loaded.durationSeconds
        waveformPeaks = SampleEditorProcessor.makePeaks(from: loaded.samples, bucketCount: 1024)
        analysis = editorAnalysis
        settings = EditorEditSettings(trimStart: 0, trimEnd: loaded.durationSeconds)
        if clearEffectChain {
            effectChainState = EditorEffectChainState()
            selectedChainEffectID = nil
            selectedEffectParameters = []
        }
        clampSettings()

        if removePreviousSource, let previousSourceURL, previousSourceURL != localURL {
            try? FileManager.default.removeItem(at: previousSourceURL)
        }
    }

    private func inspectSelectedChainEffect() {
        guard let selectedChainItem else {
            selectedEffectParameters = []
            isLoadingEffectParameters = false
            return
        }

        isLoadingEffectParameters = true
        Task {
            do {
                let parameters = try await SampleEditorProcessor.inspectParameters(
                    for: selectedChainItem.descriptor,
                    snapshots: selectedChainItem.parameterSnapshots
                )
                if selectedChainEffectID == selectedChainItem.id {
                    selectedEffectParameters = parameters
                }
            } catch {
                if selectedChainEffectID == selectedChainItem.id {
                    selectedEffectParameters = []
                    errorMessage = error.localizedDescription.uppercased()
                }
            }
            if selectedChainEffectID == selectedChainItem.id {
                isLoadingEffectParameters = false
            }
        }
    }

    private func clampSettings() {
        let duration = max(durationSeconds, 0.01)
        settings.trimStart = settings.trimStart.clamped(to: 0...(duration - 0.01))
        settings.trimEnd = settings.trimEnd.clamped(to: (settings.trimStart + 0.01)...duration)
        let maxFade = maxFadeDuration
        settings.fadeInDuration = min(max(settings.fadeInDuration, 0), maxFade)
        settings.fadeOutDuration = min(max(settings.fadeOutDuration, 0), maxFade)
        settings.zoom = settings.zoom.clamped(to: 1...8)
        settings.timeStretchRatio = settings.timeStretchRatio.clamped(to: 0.5...2.0)
        settings.pitchSemitones = settings.pitchSemitones.clamped(to: -12...12)
    }

    private static func copyIntoTemporaryDirectory(url: URL) throws -> URL {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor_\(UUID().uuidString)_\(url.lastPathComponent)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}

struct EditorEditSettings: Equatable {
    var trimStart: Double = 0
    var trimEnd: Double = 0.01
    var fadeInDuration: Double = 0
    var fadeOutDuration: Double = 0
    var normalize = false
    var reverse = false
    var pitchSemitones: Double = 0
    var timeStretchRatio: Double = 1
    var zoom: Double = 1
}

struct EditorAnalysisSummary: Equatable {
    let bpm: Double?
    let beatPhase: Double?
    let keyName: String?

    var bpmLabel: String {
        guard let bpm else { return "NONE" }
        return "\(Int(bpm.rounded()))"
    }

    var keyLabel: String {
        keyName ?? "NONE"
    }
}

enum EditorOperationPhase: Equatable {
    case idle
    case renderingPreview
    case renderingShareFile
    case optimizing(Double)
    case uploading(Double)
    case complete(String)
    case failed(String)
}

enum EditorError: LocalizedError {
    case noSampleLoaded
    case couldNotReadBuffer
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noSampleLoaded:
            return "NO SAMPLE LOADED"
        case .couldNotReadBuffer:
            return "FAILED TO READ AUDIO BUFFER"
        case .renderFailed:
            return "FAILED TO RENDER AUDIO"
        }
    }
}

enum SampleEditorProcessor {
    static func loadMonoSamples(from url: URL) async throws -> LoadedEditorSample {
        try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let processingFormat = file.processingFormat
            let totalFrames = AVAudioFrameCount(file.length)
            guard totalFrames > 0 else {
                throw EditorError.couldNotReadBuffer
            }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: totalFrames) else {
                throw EditorError.couldNotReadBuffer
            }
            try file.read(into: buffer)

            let frameCount = Int(buffer.frameLength)
            let sampleRate = processingFormat.sampleRate
            let channelCount = Int(processingFormat.channelCount)
            guard let channelData = buffer.floatChannelData else {
                throw EditorError.couldNotReadBuffer
            }

            var mono = [Float](repeating: 0, count: frameCount)
            if channelCount == 1 {
                mono = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            } else {
                for channel in 0..<channelCount {
                    let source = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                    for index in 0..<frameCount {
                        mono[index] += source[index]
                    }
                }
                let scale = 1.0 / Float(channelCount)
                for index in 0..<frameCount {
                    mono[index] *= scale
                }
            }

            return LoadedEditorSample(
                samples: mono,
                sampleRate: sampleRate,
                durationSeconds: Double(frameCount) / sampleRate
            )
        }.value
    }

    static func analyze(url: URL, samples: [Float], sampleRate: Double) async -> EditorAnalysisSummary {
        async let audioAnalysis = AudioAnalyzer.analyze(url: url)
        async let key = estimateKeyName(samples: samples, sampleRate: sampleRate)

        let analysis = await audioAnalysis
        let keyName = await key
        return EditorAnalysisSummary(
            bpm: analysis?.bpm,
            beatPhase: analysis?.beatPhase,
            keyName: keyName
        )
    }

    static func makePeaks(from samples: [Float], bucketCount: Int) -> [Float] {
        guard !samples.isEmpty, bucketCount > 0 else { return [] }
        let framesPerBucket = max(1, samples.count / bucketCount)
        var peaks = [Float]()
        peaks.reserveCapacity(bucketCount)

        var index = 0
        while index < samples.count {
            let upperBound = min(index + framesPerBucket, samples.count)
            let bucketPeak = samples[index..<upperBound].reduce(0) { max($0, abs($1)) }
            peaks.append(bucketPeak)
            index = upperBound
        }

        if let maxPeak = peaks.max(), maxPeak > 0 {
            return peaks.map { $0 / maxPeak }
        }
        return peaks
    }

    static func processedSamples(samples: [Float], sampleRate: Double, settings: EditorEditSettings) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let trimStartIndex = max(Int(settings.trimStart * sampleRate), 0)
        let trimEndIndex = min(Int(settings.trimEnd * sampleRate), samples.count)
        guard trimEndIndex > trimStartIndex else { return [] }

        var edited = Array(samples[trimStartIndex..<trimEndIndex])

        if settings.reverse {
            edited.reverse()
        }

        applyFade(samples: &edited, sampleRate: sampleRate, fadeInDuration: settings.fadeInDuration, fadeOutDuration: settings.fadeOutDuration)

        if settings.normalize, let peak = edited.map({ abs($0) }).max(), peak > 0 {
            let gain = 0.99 / peak
            for index in edited.indices {
                edited[index] *= gain
            }
        }

        return edited
    }

    static func renderEditedWAV(
        samples: [Float],
        sampleRate: Double,
        settings: EditorEditSettings,
        effectChain: EditorEffectChainState,
        baseName: String
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let edited = processedSamples(samples: samples, sampleRate: sampleRate, settings: settings)
            guard !edited.isEmpty else { throw EditorError.renderFailed }

            let renderChannels: AVAudioChannelCount = effectChain.activeItems.isEmpty ? 1 : 2
            let renderFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: renderChannels,
                interleaved: false
            )!

            guard let sourceBuffer = makeBuffer(samples: edited, format: renderFormat) else {
                throw EditorError.renderFailed
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(baseName)_EDIT_\(UUID().uuidString).wav")

            if settings.pitchSemitones == 0, settings.timeStretchRatio == 1, effectChain.activeItems.isEmpty {
                let file = try AVAudioFile(forWriting: outputURL, settings: wavSettings(sampleRate: sampleRate, channels: 1))
                try file.write(from: sourceBuffer)
                return outputURL
            }

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch()
            timePitch.pitch = Float(settings.pitchSemitones * 100)
            timePitch.rate = Float(1.0 / settings.timeStretchRatio)

            engine.attach(player)
            engine.attach(timePitch)
            engine.connect(player, to: timePitch, format: renderFormat)

            let effectUnits = try await instantiateEffects(for: effectChain)
            var previousNode: AVAudioNode = timePitch
            for unit in effectUnits {
                engine.attach(unit)
                engine.connect(previousNode, to: unit, format: renderFormat)
                previousNode = unit
            }
            engine.connect(previousNode, to: engine.mainMixerNode, format: renderFormat)

            try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
            try engine.start()

            player.scheduleBuffer(sourceBuffer, completionHandler: nil)
            player.play()

            let outputFile = try AVAudioFile(forWriting: outputURL, settings: wavSettings(sampleRate: sampleRate, channels: renderChannels))
            let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!
            let estimatedFrameCount = AVAudioFramePosition(Double(sourceBuffer.frameLength) * settings.timeStretchRatio) + 4096

            while engine.manualRenderingSampleTime < estimatedFrameCount {
                let remainingFrames = estimatedFrameCount - engine.manualRenderingSampleTime
                let framesToRender = min(
                    engine.manualRenderingMaximumFrameCount,
                    AVAudioFrameCount(max(remainingFrames, 1))
                )

                let status = try engine.renderOffline(framesToRender, to: renderBuffer)
                switch status {
                case .success:
                    if renderBuffer.frameLength > 0 {
                        try outputFile.write(from: renderBuffer)
                    }
                case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                    continue
                case .error:
                    throw EditorError.renderFailed
                @unknown default:
                    throw EditorError.renderFailed
                }
            }

            player.stop()
            engine.stop()
            return outputURL
        }.value
    }

    static func estimateKeyName(samples: [Float], sampleRate: Double) async -> String? {
        await Task.detached(priority: .utility) {
            estimateKeyNameSync(samples: samples, sampleRate: sampleRate)
        }.value
    }

    private static func estimateKeyNameSync(samples: [Float], sampleRate: Double) -> String? {
        guard sampleRate > 0, samples.count > 4096 else { return nil }

        let center = samples.count / 2
        let windowLength = min(16384, samples.count)
        let start = max(center - windowLength / 2, 0)
        let segment = Array(samples[start..<(start + windowLength)])
        let mean = segment.reduce(0, +) / Float(segment.count)
        let centered = segment.map { $0 - mean }

        let minFrequency = 55.0
        let maxFrequency = 1760.0
        let minLag = Int(sampleRate / maxFrequency)
        let maxLag = min(Int(sampleRate / minFrequency), centered.count / 2)
        guard maxLag > minLag else { return nil }

        var bestLag = minLag
        var bestScore: Float = 0
        for lag in minLag...maxLag {
            var score: Float = 0
            for index in 0..<(centered.count - lag) {
                score += centered[index] * centered[index + lag]
            }
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        guard bestScore > 0 else { return nil }
        let frequency = sampleRate / Double(bestLag)
        let midi = Int((69 + 12 * log2(frequency / 440.0)).rounded())
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = ((midi % 12) + 12) % 12
        return noteNames[noteIndex]
    }

    private static func applyFade(
        samples: inout [Float],
        sampleRate: Double,
        fadeInDuration: Double,
        fadeOutDuration: Double
    ) {
        let fadeInSamples = min(Int(fadeInDuration * sampleRate), samples.count)
        if fadeInSamples > 0 {
            for index in 0..<fadeInSamples {
                let gain = Float(index) / Float(max(fadeInSamples - 1, 1))
                samples[index] *= gain
            }
        }

        let fadeOutSamples = min(Int(fadeOutDuration * sampleRate), samples.count)
        if fadeOutSamples > 0 {
            for offset in 0..<fadeOutSamples {
                let index = samples.count - fadeOutSamples + offset
                let gain = 1 - (Float(offset) / Float(max(fadeOutSamples - 1, 1)))
                samples[index] *= gain
            }
        }
    }

    private static func makeBuffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channelData = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelCount = Int(format.channelCount)
        for channelIndex in 0..<channelCount {
            let channel = channelData[channelIndex]
            samples.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return }
                channel.update(from: baseAddress, count: samples.count)
            }
        }
        return buffer
    }

    private static func instantiateEffects(for chain: EditorEffectChainState) async throws -> [AVAudioUnit] {
        var units: [AVAudioUnit] = []
        for item in chain.activeItems {
            let unit = try await instantiateAudioUnit(descriptor: item.descriptor.componentDescription)
            applyParameterSnapshots(item.parameterSnapshots, to: unit)
            units.append(unit)
        }
        return units
    }

    private static func instantiateAudioUnit(descriptor: AudioComponentDescription) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: descriptor, options: []) { audioUnit, error in
                if let audioUnit {
                    continuation.resume(returning: audioUnit)
                } else {
                    continuation.resume(throwing: error ?? EditorError.renderFailed)
                }
            }
        }
    }

    static func discoverAudioUnits() async -> [EditorEffectDescriptor] {
        await Task.detached(priority: .utility) {
            var descriptorsByID: [String: EditorEffectDescriptor] = [:]
            let managerDescriptors = AVAudioUnitComponentManager.shared()
                .components { _, _ in true }
                .map(EditorEffectDescriptor.init(component:))

            let registryDescriptors = discoverAudioUnitsFromRegistry()

            for descriptor in managerDescriptors + registryDescriptors {
                descriptorsByID[descriptor.id] = descriptorsByID[descriptor.id].map {
                    $0.merging(with: descriptor)
                } ?? descriptor
            }

            return descriptorsByID.values.sorted { lhs, rhs in
                if lhs.insertionPriority == rhs.insertionPriority {
                    return lhs.menuLabel < rhs.menuLabel
                }
                return lhs.insertionPriority > rhs.insertionPriority
            }
        }.value
    }

    private static func discoverAudioUnitsFromRegistry() -> [EditorEffectDescriptor] {
        var searchDescription = AudioComponentDescription(
            componentType: 0,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        var results: [EditorEffectDescriptor] = []
        var current = AudioComponentFindNext(nil, &searchDescription)
        while let component = current {
            var description = AudioComponentDescription()
            AudioComponentGetDescription(component, &description)

            var unmanagedName: Unmanaged<CFString>?
            let componentNameStatus = AudioComponentCopyName(component, &unmanagedName)
            let componentName = if componentNameStatus == noErr, let unmanagedName {
                unmanagedName.takeRetainedValue() as String
            } else {
                EditorEffectDescriptor.fourCC(description.componentSubType)
            }
            let parsedName = parseComponentName(componentName)
            let configuration = configurationInfo(for: component)
            results.append(
                EditorEffectDescriptor(
                    name: parsedName.name,
                    manufacturerName: parsedName.manufacturer,
                    componentType: description.componentType,
                    componentSubType: description.componentSubType,
                    componentManufacturer: description.componentManufacturer,
                    componentFlags: description.componentFlags,
                    discoverySource: .audioComponentRegistry,
                    initialInputCount: configuration?.initialInputCount,
                    initialOutputCount: configuration?.initialOutputCount,
                    hasCustomView: configuration?.hasCustomView
                )
            )

            current = AudioComponentFindNext(component, &searchDescription)
        }

        return results
    }

    private static func parseComponentName(_ rawName: String) -> (name: String, manufacturer: String) {
        let separators = [" : ", ": ", ":", " / "]
        for separator in separators {
            if let range = rawName.range(of: separator) {
                let manufacturer = String(rawName[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let name = String(rawName[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !manufacturer.isEmpty, !name.isEmpty {
                    return (name, manufacturer)
                }
            }
        }

        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (normalized.isEmpty ? "UNKNOWN AUDIO UNIT" : normalized, "UNKNOWN")
    }

    private static func configurationInfo(for component: AudioComponent) -> EditorEffectConfigurationSummary? {
        var unmanagedInfo: Unmanaged<CFDictionary>?
        let status = AudioComponentCopyConfigurationInfo(component, &unmanagedInfo)
        guard status == noErr,
              let info = unmanagedInfo?.takeRetainedValue() as? [String: Any] else { return nil }

        return EditorEffectConfigurationSummary(
            initialInputCount: parseConfigurationCount(info["InitialInputs"]),
            initialOutputCount: parseConfigurationCount(info["InitialOutputs"]),
            hasCustomView: info["HasCustomView"] as? Bool
        )
    }

    private static func parseConfigurationCount(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    static func discoverAudioUnitExtensions() async -> [EditorAudioUnitExtensionIdentity] {
        guard #available(iOS 26.0, macOS 26.0, *) else { return [] }

        return await Task.detached(priority: .utility) {
            do {
                let monitor = AppExtensionPoint.Monitor()
                let audioUnitPoint = try AppExtensionPoint(identifier: "com.apple.AudioUnit")
                let audioUnitUIPoint = try AppExtensionPoint(identifier: "com.apple.AudioUnit-UI")
                try await monitor.addAppExtensionPoint(audioUnitPoint)
                try await monitor.addAppExtensionPoint(audioUnitUIPoint)

                return monitor.identities
                    .map {
                        EditorAudioUnitExtensionIdentity(
                            id: $0.id,
                            bundleIdentifier: $0.bundleIdentifier,
                            localizedName: $0.localizedName,
                            extensionPointIdentifier: $0.extensionPointIdentifier
                        )
                    }
                    .sorted { $0.localizedName < $1.localizedName }
            } catch {
                return []
            }
        }.value
    }

    static func inspectParameters(
        for descriptor: EditorEffectDescriptor,
        snapshots: [EditorEffectParameterSnapshot]
    ) async throws -> [EditorEffectParameterDescriptor] {
        let unit = try await instantiateAudioUnit(descriptor: descriptor.componentDescription)
        applyParameterSnapshots(snapshots, to: unit)
        guard let parameters = unit.auAudioUnit.parameterTree?.allParameters else { return [] }

        return parameters
            .filter { $0.flags.contains(.flag_IsReadable) && $0.flags.contains(.flag_IsWritable) }
            .prefix(16)
            .map { parameter in
                EditorEffectParameterDescriptor(
                    address: parameter.address,
                    identifier: parameter.identifier,
                    displayName: parameter.displayName.uppercased(),
                    minValue: parameter.minValue,
                    maxValue: parameter.maxValue,
                    currentValue: parameter.value,
                    unitName: parameter.unitName ?? ""
                )
            }
    }

    private static func applyParameterSnapshots(_ snapshots: [EditorEffectParameterSnapshot], to unit: AVAudioUnit) {
        guard let parameters = unit.auAudioUnit.parameterTree?.allParameters, !snapshots.isEmpty else { return }
        let valueByAddress = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.address, $0.value) })
        for parameter in parameters {
            if let value = valueByAddress[parameter.address], parameter.flags.contains(.flag_IsWritable) {
                parameter.value = value
            }
        }
    }

    private static func wavSettings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
}

struct LoadedEditorSample {
    let samples: [Float]
    let sampleRate: Double
    let durationSeconds: Double
}

struct EditorEffectChainState: Codable, Equatable {
    var items: [EditorEffectChainItem] = []

    var activeItems: [EditorEffectChainItem] {
        items.filter { !$0.isBypassed }
    }
}

struct EditorEffectChainItem: Identifiable, Codable, Equatable {
    let id: UUID
    let descriptor: EditorEffectDescriptor
    var isBypassed: Bool
    var parameterSnapshots: [EditorEffectParameterSnapshot]

    init(
        id: UUID = UUID(),
        descriptor: EditorEffectDescriptor,
        isBypassed: Bool = false,
        parameterSnapshots: [EditorEffectParameterSnapshot] = []
    ) {
        self.id = id
        self.descriptor = descriptor
        self.isBypassed = isBypassed
        self.parameterSnapshots = parameterSnapshots
    }

    var displayName: String {
        descriptor.name.uppercased()
    }
}

struct EditorEffectParameterSnapshot: Codable, Equatable {
    let address: UInt64
    let identifier: String
    var value: Float
}

struct EditorEffectParameterDescriptor: Identifiable, Equatable {
    let address: UInt64
    let identifier: String
    let displayName: String
    let minValue: Float
    let maxValue: Float
    var currentValue: Float
    let unitName: String

    var id: UInt64 { address }

    var formattedValue: String {
        if unitName.isEmpty {
            return String(format: "%.3f", currentValue)
        }
        return String(format: "%.3f %@", currentValue, unitName)
    }
}

struct EditorEffectDescriptor: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let manufacturerName: String
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32
    let componentFlags: UInt32
    let discoverySource: EditorEffectDiscoverySource
    let initialInputCount: Int?
    let initialOutputCount: Int?
    let hasCustomView: Bool?

    init(component: AVAudioUnitComponent) {
        let description = component.audioComponentDescription
        name = component.name
        manufacturerName = component.manufacturerName
        componentType = description.componentType
        componentSubType = description.componentSubType
        componentManufacturer = description.componentManufacturer
        componentFlags = description.componentFlags
        discoverySource = .componentManager
        initialInputCount = nil
        initialOutputCount = nil
        hasCustomView = nil
        id = Self.makeID(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer
        )
    }

    init(
        id: String? = nil,
        name: String,
        manufacturerName: String,
        componentType: UInt32,
        componentSubType: UInt32,
        componentManufacturer: UInt32,
        componentFlags: UInt32 = 0,
        discoverySource: EditorEffectDiscoverySource = .componentManager,
        initialInputCount: Int? = nil,
        initialOutputCount: Int? = nil,
        hasCustomView: Bool? = nil
    ) {
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.componentFlags = componentFlags
        self.discoverySource = discoverySource
        self.initialInputCount = initialInputCount
        self.initialOutputCount = initialOutputCount
        self.hasCustomView = hasCustomView
        self.id = id ?? Self.makeID(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer
        )
    }

    var componentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    var manufacturerDisplay: String {
        manufacturerName.uppercased()
    }

    var menuLabel: String {
        "\(name.uppercased()) • \(manufacturerDisplay)"
    }

    var isSupportedEffectType: Bool {
        [
            kAudioUnitType_Effect,
            kAudioUnitType_MusicEffect,
            kAudioUnitType_Panner,
            kAudioUnitType_FormatConverter,
            kAudioUnitType_Mixer
        ].contains(componentType)
    }

    var insertionPriority: Int {
        isSupportedEffectType ? 1 : 0
    }

    var typeSummary: String {
        "\(componentTypeCode) • \(typeDisplayName) • \(discoverySource.label) • \(ioSummary)"
    }

    var ioSummary: String {
        let inputs = initialInputCount.map(String.init) ?? "?"
        let outputs = initialOutputCount.map(String.init) ?? "?"
        let view = hasCustomView == true ? "VIEW" : "NO VIEW"
        return "IN \(inputs) / OUT \(outputs) / \(view)"
    }

    private var typeDisplayName: String {
        switch componentType {
        case kAudioUnitType_Effect:
            return "EFFECT"
        case kAudioUnitType_MusicEffect:
            return "MUSIC EFFECT"
        case kAudioUnitType_Panner:
            return "PANNER"
        case kAudioUnitType_FormatConverter:
            return "FORMAT CONVERTER"
        case kAudioUnitType_Mixer:
            return "MIXER"
        case kAudioUnitType_Generator:
            return "GENERATOR"
        case kAudioUnitType_MusicDevice:
            return "MUSIC DEVICE"
        case kAudioUnitType_MIDIProcessor:
            return "MIDI PROCESSOR"
        case kAudioUnitType_Output:
            return "OUTPUT"
        default:
            return "OTHER"
        }
    }

    private var componentTypeCode: String {
        Self.fourCC(componentType)
    }

    private static func makeID(componentType: UInt32, componentSubType: UInt32, componentManufacturer: UInt32) -> String {
        "\(componentType)-\(componentSubType)-\(componentManufacturer)"
    }

    func merging(with other: EditorEffectDescriptor) -> EditorEffectDescriptor {
        EditorEffectDescriptor(
            id: id,
            name: preferred(name, over: other.name),
            manufacturerName: preferred(manufacturerName, over: other.manufacturerName),
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: componentFlags | other.componentFlags,
            discoverySource: discoverySource.merging(with: other.discoverySource),
            initialInputCount: initialInputCount ?? other.initialInputCount,
            initialOutputCount: initialOutputCount ?? other.initialOutputCount,
            hasCustomView: hasCustomView ?? other.hasCustomView
        )
    }

    private func preferred(_ current: String, over other: String) -> String {
        if current == "UNKNOWN", other != "UNKNOWN" {
            return other
        }
        if current.count < other.count, !other.isEmpty {
            return other
        }
        return current
    }

    static func fourCC(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        let chars = bytes.map { byte -> Character in
            if (32...126).contains(byte) {
                return Character(UnicodeScalar(byte))
            }
            return "."
        }
        return String(chars)
    }
}

enum EditorEffectDiscoverySource: String, Codable, Equatable {
    case componentManager
    case audioComponentRegistry
    case componentManagerAndRegistry

    var label: String {
        switch self {
        case .componentManager:
            return "MANAGER"
        case .audioComponentRegistry:
            return "REGISTRY"
        case .componentManagerAndRegistry:
            return "MANAGER+REGISTRY"
        }
    }

    func merging(with other: EditorEffectDiscoverySource) -> EditorEffectDiscoverySource {
        if self == other {
            return self
        }
        return .componentManagerAndRegistry
    }
}

struct EditorEffectConfigurationSummary {
    let initialInputCount: Int?
    let initialOutputCount: Int?
    let hasCustomView: Bool?
}

struct EditorAudioUnitExtensionIdentity: Identifiable, Equatable {
    let id: String
    let bundleIdentifier: String
    let localizedName: String
    let extensionPointIdentifier: String
}

struct EditorEffectPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var chain: EditorEffectChainState

    init(id: UUID = UUID(), name: String, chain: EditorEffectChainState) {
        self.id = id
        self.name = name
        self.chain = chain
    }
}

enum EditorEffectPresetStore {
    static let defaultsKey = "editor.effect.presets"

    static func load(userDefaults: UserDefaults = .standard) -> [EditorEffectPreset] {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let presets = try? JSONDecoder().decode([EditorEffectPreset].self, from: data) else {
            return []
        }
        return presets.sorted { $0.name < $1.name }
    }

    static func upsert(
        preset: EditorEffectPreset,
        existing: [EditorEffectPreset],
        userDefaults: UserDefaults = .standard
    ) -> [EditorEffectPreset] {
        var next = existing.filter { $0.name != preset.name }
        next.append(preset)
        persist(next, userDefaults: userDefaults)
        return next.sorted { $0.name < $1.name }
    }

    static func delete(
        id: UUID,
        existing: [EditorEffectPreset],
        userDefaults: UserDefaults = .standard
    ) -> [EditorEffectPreset] {
        let next = existing.filter { $0.id != id }
        persist(next, userDefaults: userDefaults)
        return next.sorted { $0.name < $1.name }
    }

    private static func persist(_ presets: [EditorEffectPreset], userDefaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(presets) {
            userDefaults.set(data, forKey: defaultsKey)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    EditorView()
        .environment(ConnectionManager())
}
