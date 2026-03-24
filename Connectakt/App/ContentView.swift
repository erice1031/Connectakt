import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BrowserView()
                .tabItem {
                    Label("SAMPLES", systemImage: "waveform")
                }
            RecorderView()
                .tabItem {
                    Label("RECORD", systemImage: "record.circle")
                }
            EditorView()
                .tabItem {
                    Label("EDITOR", systemImage: "slider.horizontal.3")
                }
            SettingsView()
                .tabItem {
                    Label("SETTINGS", systemImage: "gearshape")
                }
        }
        .tint(ConnektaktTheme.primary)
        .preferredColorScheme(.dark)
        .background(ConnektaktTheme.background)
    }
}

#Preview {
    ContentView()
        .environment(ConnectionManager())
}
