import SwiftUI
import UIKit

/// Root view hosting the 4-tab navigation architecture, floating mini player, glass tab bar, and full-screen overlays.
struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var showOnboarding: Bool = false

    private let mainTabs: [AppTab] = [.home, .search, .library, .settings]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.mochyEffectiveBackground
                .ignoresSafeArea()

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                if player.currentTrack != nil {
                    MiniPlayerBar {
                        router.present(.nowPlaying)
                    }
                    .padding(.horizontal, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                customTabBar
                    .padding(.horizontal, settings.slimNavBar ? 20 : 12)
                    .padding(.bottom, 6)
            }
            .animation(MochyTheme.springAnimation, value: player.currentTrack != nil)

            TopToastBanner(message: player.errorMessage)
        }
        .fullScreenCover(isPresented: $router.isNowPlayingPresented) {
            NowPlayingView()
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(router)
                .preferredColorScheme(settings.colorScheme ?? .dark)
        }
        .sheet(item: $router.presentedSheet) { route in
            NavigationStack {
                destinationView(for: route)
            }
            .environmentObject(player)
            .environmentObject(library)
            .environmentObject(settings)
            .environmentObject(router)
            .preferredColorScheme(settings.colorScheme ?? .dark)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            SetupWizardScreen {
                settings.setupCompleted = true
                showOnboarding = false
            }
            .environmentObject(player)
            .environmentObject(library)
            .environmentObject(settings)
            .environmentObject(router)
            .preferredColorScheme(.dark)
        }
        .onAppear {
            if !settings.setupCompleted {
                showOnboarding = true
            }
            if !mainTabs.contains(router.selectedTab) && router.selectedTab != .explore {
                router.selectedTab = .home
            }
        }
    }

    // MARK: - Tab Stacks

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            NavigationStack(path: $router.homePath) {
                HomeScreen()
                    .navigationDestination(for: AppRoute.self) { destinationView(for: $0) }
            }
            .opacity(router.selectedTab == .home ? 1 : 0)
            .allowsHitTesting(router.selectedTab == .home)

            NavigationStack(path: $router.explorePath) {
                ExploreScreen()
                    .navigationDestination(for: AppRoute.self) { destinationView(for: $0) }
            }
            .opacity(router.selectedTab == .explore ? 1 : 0)
            .allowsHitTesting(router.selectedTab == .explore)

            NavigationStack(path: $router.searchPath) {
                SearchScreen()
                    .navigationDestination(for: AppRoute.self) { destinationView(for: $0) }
            }
            .opacity(router.selectedTab == .search ? 1 : 0)
            .allowsHitTesting(router.selectedTab == .search)

            NavigationStack(path: $router.libraryPath) {
                LibraryScreen()
                    .navigationDestination(for: AppRoute.self) { destinationView(for: $0) }
            }
            .opacity(router.selectedTab == .library ? 1 : 0)
            .allowsHitTesting(router.selectedTab == .library)

            NavigationStack(path: $router.settingsPath) {
                MochySettingsScreen()
                    .navigationDestination(for: AppRoute.self) { destinationView(for: $0) }
            }
            .opacity(router.selectedTab == .settings ? 1 : 0)
            .allowsHitTesting(router.selectedTab == .settings)
        }
    }

    // MARK: - Custom Floating Glass Tab Bar

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(mainTabs) { tab in
                let isSelected = router.selectedTab == tab || (tab == .home && router.selectedTab == .explore)
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    router.switchTab(to: tab)
                } label: {
                    VStack(spacing: settings.slimNavBar ? 2 : 4) {
                        Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                            .font(.system(size: settings.slimNavBar ? 18 : 20, weight: isSelected ? .semibold : .regular))
                            .scaleEffect(isSelected ? 1.08 : 1.0)

                        if !settings.slimNavBar {
                            Text(tabTitle(for: tab))
                                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(isSelected ? settings.accentColor : .mochySecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, settings.slimNavBar ? 10 : 8)
                    .background(
                        Group {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(settings.accentColor.opacity(0.14))
                                    .padding(.horizontal, 6)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassBackground(
            intensity: settings.blurEnabled ? 0.9 : 0.0,
            tint: settings.pureBlack ? .mochySurface : .mochySurface0,
            cornerRadius: 24,
            borderOpacity: 0.14
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
    }

    private func tabTitle(for tab: AppTab) -> String {
        switch tab {
        case .home: return "Home"
        case .explore: return "Explore"
        case .search: return "Search"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    // MARK: - Route Destination Mapping

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .home:
            HomeScreen()
        case .explore:
            ExploreScreen()
        case .search:
            SearchScreen()
        case .browse(let browseId, let title, let params):
            BrowseScreen(browseId: browseId, title: title, params: params)
        case .library:
            LibraryScreen()
        case .favorites:
            FavoritesScreen()
        case .downloads:
            DownloadsScreen()
        case .history:
            HistoryScreen()
        case .localFiles:
            LocalFilesScreen()
        case .album(let id):
            AlbumScreen(browseId: id)
        case .artist(let id):
            ArtistScreen(browseId: id)
        case .playlist(let id, let isLocal):
            PlaylistDetailScreen(playlistId: id, isLocal: isLocal)
        case .localPlaylist(let id):
            PlaylistDetailScreen(localPlaylistId: id)
        case .sectionDetail(let title, let browseId, let params):
            SectionDetailScreen(title: title, browseId: browseId, params: params)
        case .settings:
            MochySettingsScreen()
        case .equalizer:
            EqualizerScreen()
        case .importMusic:
            ImportSyncScreen()
        case .profile:
            ProfileScreen()
        case .recap:
            RecapScreen()
        case .nowPlaying:
            NowPlayingView()
        case .youtubeLogin:
            YouTubeLoginScreen()
        case .discordSettings:
            DiscordScreen()
        case .modulesSettings:
            ModulesScreen()
        }
    }
}
