import SwiftUI

@main
struct ConnektaktApp: App {
    @State private var connectionManager = ConnectionManager()
    @State private var audioRecorder = AudioRecorder()
    @State private var recordingHistory = RecordingHistoryManager()
    @State private var store = StoreManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectionManager)
                .environment(audioRecorder)
                .environment(recordingHistory)
                .environment(store)
                .onAppear {
                    connectionManager.startUSBMonitoring()
                }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 680)
        .windowResizability(.contentMinSize)
        #endif
    }
}
