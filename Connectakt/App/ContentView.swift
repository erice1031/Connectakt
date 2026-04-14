import SwiftUI

struct ContentView: View {
    @Environment(ConnectionManager.self) private var connection
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowserView()
                .tabItem { Label("SAMPLES", systemImage: "waveform") }
                .tag(0)
            RecorderView()
                .tabItem { Label("RECORD", systemImage: "record.circle") }
                .tag(1)
            EditorView()
                .tabItem { Label("EDITOR", systemImage: "slider.horizontal.3") }
                .tag(2)
            SettingsView()
                .tabItem { Label("SETTINGS", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(ConnektaktTheme.primary)
        .preferredColorScheme(.dark)
        .background(ConnektaktTheme.background)
        .onChange(of: connection.pendingEditorURL) { _, url in
            if url != nil { selectedTab = 2 }
        }
    }
}

#Preview {
    ContentView()
        .environment(ConnectionManager())
}
