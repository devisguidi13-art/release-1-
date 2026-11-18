import SwiftUI

@main
struct DVSMusicApp: App {
    @StateObject private var player = PlaybackController()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}
