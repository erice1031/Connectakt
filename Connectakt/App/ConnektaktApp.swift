import SwiftUI

@main
struct ConnektaktApp: App {
    @State private var connectionManager = ConnectionManager()
    @State private var audioRecorder = AudioRecorder()
    @State private var recordingHistory = RecordingHistoryManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectionManager)
                .environment(audioRecorder)
                .environment(recordingHistory)
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
