import SwiftUI

@main
struct MochyMusicApp: App {
    @StateObject private var player = AudioPlayerManager.shared
    @StateObject private var library = LibraryStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
