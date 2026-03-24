import SwiftUI

@main
struct ConnektaktApp: App {
    @State private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectionManager)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 680)
        .windowResizability(.contentMinSize)
        #endif
    }
}
