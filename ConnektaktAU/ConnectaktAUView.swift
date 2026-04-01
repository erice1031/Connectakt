import SwiftUI

struct ConnectaktAUView: View {
    @State private var model = ConnectaktAULibraryModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.05),
                        Color(red: 0.1, green: 0.1, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 0) {
                    header
                    if geometry.size.width > 720 {
                        wideLayout
                    } else {
                        compactLayout
                    }
                }
            }
            .onAppear {
                model.ensureSelection()
            }
            .onChange(of: model.searchText) { _, _ in
                model.ensureSelection()
            }
            .onChange(of: model.selectedCategory) { _, _ in
                model.ensureSelection()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONNECTAKT AU")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.02))

                    Text("PLUGIN BROWSER SLICE")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 0.22))

                    Text("PASS-THROUGH EFFECT + SAMPLE LIBRARY SURFACE")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                }
                Spacer()
                HStack(spacing: 10) {
                    statusPill("AUv3", tone: Color(red: 0.96, green: 0.77, blue: 0.02))
                    statusPill("Browser", tone: Color(red: 0.22, green: 1.0, blue: 0.08))
                    statusPill("Pass Through", tone: Color(red: 1.0, green: 0.45, blue: 0.0))
                }
            }

            Text("This slice makes the plugin useful inside a DAW by adding a searchable sample-browser shell. Browsing and selection are now in-plugin; hardware transfer stays for the next slice.")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var wideLayout: some View {
        HStack(spacing: 16) {
            browserPanel
                .frame(maxWidth: 360)
            detailPanel
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var compactLayout: some View {
        VStack(spacing: 16) {
            browserPanel
            detailPanel
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var browserPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar
            categoryStrip
            HStack {
                Text(model.librarySummary)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 0.22))
                Spacer()
                Text("\(model.favoriteIDs.count) FAVORITES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.0))
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.filteredSamples) { sample in
                        sampleRow(sample)
                    }
                }
            }
        }
        .padding(16)
        .background(panelBackground)
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sample = model.selectedSample {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sample.name)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .lineLimit(2)

                        Text(sample.category.rawValue)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.02))
                    }
                    Spacer()
                    Button {
                        model.toggleFavorite(for: sample)
                    } label: {
                        Image(systemName: model.isFavorite(sample) ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(model.isFavorite(sample) ? Color(red: 1.0, green: 0.45, blue: 0.0) : Color.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }

                waveformCard

                HStack(spacing: 10) {
                    metricCard("BPM", value: sample.bpm.map(String.init) ?? "—")
                    metricCard("KEY", value: sample.key ?? "—")
                    metricCard("LEN", value: sample.duration)
                    metricCard("SIZE", value: sample.sizeLabel)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TAGS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 0.22))
                    WrapTagLayout(tags: sample.tags)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NEXT ACTION")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 0.22))
                    Text("Plugin browsing is live. The next slice will connect this selection to either in-plugin transfer or a shared handoff back to the main app.")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.78))
                }

                HStack(spacing: 12) {
                    actionButton("QUEUE FOR TRANSFER", tone: Color(red: 0.96, green: 0.77, blue: 0.02), filled: true)
                    actionButton("PREVIEW LATER", tone: Color(red: 0.22, green: 1.0, blue: 0.08), filled: false)
                }
            } else {
                Text("NO SAMPLE SELECTED")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(panelBackground)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 0.22))
            TextField("SEARCH SAMPLE NAME OR TAG", text: $model.searchText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.96, green: 0.77, blue: 0.02).opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ConnectaktAUSampleCategory.allCases) { category in
                    Button {
                        model.selectedCategory = category
                    } label: {
                        Text(category.rawValue)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(model.selectedCategory == category ? Color.black : Color(red: 0.96, green: 0.77, blue: 0.02))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(model.selectedCategory == category ? Color(red: 0.96, green: 0.77, blue: 0.02) : Color(red: 0.96, green: 0.77, blue: 0.02).opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.96, green: 0.77, blue: 0.02).opacity(0.28), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sampleRow(_ sample: ConnectaktAUSample) -> some View {
        Button {
            model.select(sample)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(model.isFavorite(sample) ? Color(red: 1.0, green: 0.45, blue: 0.0) : Color(red: 0.22, green: 1.0, blue: 0.08))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sample.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        if model.isFavorite(sample) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.0))
                        }
                    }

                    Text("\(sample.duration) • \(sample.sizeLabel) • \(sample.category.rawValue)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 0.22))

                    Text(sample.tags.joined(separator: " • "))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(model.selectedSample?.id == sample.id ? Color(red: 0.96, green: 0.77, blue: 0.02).opacity(0.12) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(model.selectedSample?.id == sample.id ? Color(red: 0.96, green: 0.77, blue: 0.02).opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var waveformCard: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<36, id: \.self) { index in
                        Capsule()
                            .fill(index.isMultiple(of: 5) ? Color(red: 0.96, green: 0.77, blue: 0.02) : Color(red: 0.22, green: 1.0, blue: 0.08).opacity(0.85))
                            .frame(width: max(3, geometry.size.width / 54), height: CGFloat(18 + ((index * 13) % 48)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .frame(height: 108)
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 0.22))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func actionButton(_ title: String, tone: Color, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(filled ? Color.black : tone)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(filled ? tone : tone.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tone.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 0.96, green: 0.77, blue: 0.02).opacity(0.12), lineWidth: 1)
            )
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

private struct WrapTagLayout: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.22, green: 1.0, blue: 0.08))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.22, green: 1.0, blue: 0.08).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let content: Content

    init(spacing: CGFloat, lineSpacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content()
    }

    var body: some View {
        _FlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
            content
        }
    }
}

private struct _FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    ConnectaktAUView()
}
