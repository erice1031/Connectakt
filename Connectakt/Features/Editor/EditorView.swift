import SwiftUI

struct EditorView: View {
    @Environment(ConnectionManager.self) private var connection
    @State private var hasLoadedSample = false

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(
                title: "EDITOR",
                status: hasLoadedSample
                    ? .connected(deviceName: "SAMPLE LOADED")
                    : .disconnected
            )

            if hasLoadedSample {
                EditorWorkspaceView(onClose: { hasLoadedSample = false })
            } else {
                EditorEmptyView(onLoad: { hasLoadedSample = true })
            }
        }
        .ckScreen()
    }
}

// MARK: - Empty State

private struct EditorEmptyView: View {
    let onLoad: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(ConnektaktTheme.textMuted)

                VStack(spacing: 6) {
                    Text("NO SAMPLE LOADED")
                        .font(ConnektaktTheme.largeFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                        .tracking(2)

                    Text("OPEN A SAMPLE FROM THE BROWSER")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(1)
                }

                HStack(spacing: ConnektaktTheme.paddingSM) {
                    CKButton("OPEN FROM BROWSER", icon: "folder", variant: .secondary, action: onLoad)
                    CKButton("IMPORT FILE", icon: "doc.badge.plus", variant: .ghost, action: onLoad)
                }
            }

            Spacer()

            // Phase roadmap teaser
            VStack(spacing: 8) {
                Rectangle()
                    .fill(ConnektaktTheme.primary.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal)

                VStack(spacing: 4) {
                    Text("SAMPLE EDITOR — PHASE 4")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(2)

                    HStack(spacing: ConnektaktTheme.paddingMD) {
                        featureTag("TRIM")
                        featureTag("NORMALIZE")
                        featureTag("PITCH")
                        featureTag("STRETCH")
                        featureTag("AUV3")
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

// MARK: - Editor Workspace (Phase 4 Scaffold)

private struct EditorWorkspaceView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Sample info bar
            HStack {
                Text("KICK_01.WAV")
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                Text("·")
                    .foregroundStyle(ConnektaktTheme.textMuted)
                Text("16-BIT / 44.1KHZ / MONO / 2.3 MB")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                Spacer()
                CKButton("CLOSE", variant: .ghost, action: onClose)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .background(ConnektaktTheme.surface)

            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.15))
                .frame(height: 1)

            // Waveform display area
            ZStack {
                ConnektaktTheme.surface

                VStack(spacing: ConnektaktTheme.paddingSM) {
                    CKWaveformView(isActive: false)
                        .frame(height: 100)
                        .padding(.horizontal)

                    Text("FULL WAVEFORM EDITOR COMING IN PHASE 4")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)

            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.15))
                .frame(height: 1)

            // Tool bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ConnektaktTheme.paddingSM) {
                    CKButton("TRIM", icon: "crop", variant: .secondary) {}
                    CKButton("NORMALIZE", icon: "waveform.path", variant: .secondary) {}
                    CKButton("REVERSE", icon: "arrow.left.arrow.right", variant: .secondary) {}
                    CKButton("FADE IN", icon: "arrow.up.right", variant: .secondary) {}
                    CKButton("FADE OUT", icon: "arrow.down.right", variant: .secondary) {}
                    CKButton("PITCH", icon: "music.quarternote.3", variant: .secondary) {}
                    CKButton("AUV3", icon: "puzzlepiece", variant: .secondary) {}
                }
                .padding(.horizontal, ConnektaktTheme.paddingMD)
                .padding(.vertical, ConnektaktTheme.paddingSM)
            }
            .background(ConnektaktTheme.surface)

            Spacer()

            // Export bar
            HStack {
                Spacer()
                CKButton("SAVE TO BROWSER", icon: "tray.and.arrow.down", variant: .secondary) {}
                CKButton("OPTIMIZE + UPLOAD", icon: "arrow.up.circle.fill", variant: .primary) {}
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .background(ConnektaktTheme.surface)
        }
    }
}

#Preview {
    EditorView()
        .environment(ConnectionManager())
}
