import SwiftUI

@main
struct MochyMusicApp: App {
    @StateObject private var player = AudioPlayerManager.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var router = NavigationRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(router)
                .preferredColorScheme(settings.colorScheme ?? .dark)
                .tint(settings.accentColor)
        }
    }
}
