import SwiftUI

struct ContentView: View {
    @Environment(ConnectionManager.self) private var connection
    @Environment(StoreManager.self)     private var store
    @State private var selectedTab  = 0
    @State private var showPaywall  = false

    // Tabs that require Pro (1 = Record, 2 = Editor)
    private let proTabs: Set<Int> = [1, 2]

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowserView()
                .tabItem { Label("SAMPLES", systemImage: "waveform") }
                .tag(0)

            proTabContent(
                tab: 1,
                label: "RECORD",
                icon: "record.circle"
            ) {
                RecorderView()
            }

            proTabContent(
                tab: 2,
                label: "EDITOR",
                icon: "slider.horizontal.3"
            ) {
                EditorView()
            }

            SettingsView()
                .tabItem { Label("SETTINGS", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(ConnektaktTheme.primary)
        .preferredColorScheme(.dark)
        .background(ConnektaktTheme.background)
        .onChange(of: connection.pendingEditorURL) { _, url in
            if url != nil {
                if store.isPro {
                    selectedTab = 2
                } else {
                    showPaywall = true
                }
            }
        }
        .onChange(of: selectedTab) { old, new in
            if proTabs.contains(new) && !store.isPro {
                selectedTab = old
                showPaywall = true
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(store)
        }
    }

    @ViewBuilder
    private func proTabContent<Content: View>(
        tab: Int,
        label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if store.isPro {
            content()
                .tabItem { Label(label, systemImage: icon) }
                .tag(tab)
        } else {
            // Show a locked placeholder tab (tapping triggers onChange → paywall)
            LockedTabView(label: label, icon: icon) { showPaywall = true }
                .tabItem { Label(label, systemImage: icon) }
                .tag(tab)
        }
    }
}

// MARK: - Locked Tab Placeholder

private struct LockedTabView: View {
    let label: String
    let icon: String
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: ConnektaktTheme.paddingLG) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(ConnektaktTheme.textMuted)

            Text("\(label) — PRO FEATURE")
                .font(ConnektaktTheme.titleFont)
                .foregroundStyle(ConnektaktTheme.textPrimary)
                .tracking(2)

            Text("UPGRADE TO CONNECTAKT PRO TO UNLOCK")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(2)

            CKButton("UNLOCK PRO", icon: "lock.open.fill", variant: .primary, action: onUnlock)
                .padding(.top, ConnektaktTheme.paddingSM)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ConnektaktTheme.background)
    }
}

#Preview {
    ContentView()
        .environment(ConnectionManager())
        .environment(StoreManager())
}
