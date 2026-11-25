import SwiftUI

/// Centralized navigation router managing tab selection, per-tab NavigationStacks, and modal presentations.
@MainActor
final class NavigationRouter: ObservableObject {
    static let shared = NavigationRouter()

    @Published var selectedTab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var explorePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var settingsPath = NavigationPath()

    @Published var presentedSheet: AppRoute?
    @Published var isNowPlayingPresented: Bool = false

    private init() {
        if let savedTab = AppTab(rawValue: AppSettings.shared.defaultOpenTab) {
            selectedTab = savedTab
        }
    }

    /// Push a route onto the active tab's `NavigationPath` (or switch/present when appropriate).
    func push(_ route: AppRoute) {
        switch route {
        case .nowPlaying:
            withAnimation(MochyTheme.springAnimation) {
                isNowPlayingPresented = true
            }
        case .home:
            selectedTab = .home
        case .explore:
            selectedTab = .explore
        case .search:
            selectedTab = .search
        case .library:
            selectedTab = .library
        default:
            appendToCurrentPath(route)
        }
    }

    /// Pop the top route from the active tab's `NavigationPath`.
    func pop() {
        switch selectedTab {
        case .home:
            if !homePath.isEmpty { homePath.removeLast() }
        case .explore:
            if !explorePath.isEmpty { explorePath.removeLast() }
        case .search:
            if !searchPath.isEmpty { searchPath.removeLast() }
        case .library:
            if !libraryPath.isEmpty { libraryPath.removeLast() }
        case .settings:
            if !settingsPath.isEmpty { settingsPath.removeLast() }
        }
    }

    /// Clear the navigation stack for the specified tab (or current tab if `nil`).
    func popToRoot(tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        switch target {
        case .home:
            homePath = NavigationPath()
        case .explore:
            explorePath = NavigationPath()
        case .search:
            searchPath = NavigationPath()
        case .library:
            libraryPath = NavigationPath()
        case .settings:
            settingsPath = NavigationPath()
        }
    }

    /// Present a destination modally (sheet or Now Playing).
    func present(_ route: AppRoute) {
        if route == .nowPlaying {
            withAnimation(MochyTheme.springAnimation) {
                isNowPlayingPresented = true
            }
        } else {
            presentedSheet = route
        }
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    func dismissNowPlaying() {
        withAnimation(MochyTheme.springAnimation) {
            isNowPlayingPresented = false
        }
    }

    func switchTab(to tab: AppTab) {
        if selectedTab == tab {
            popToRoot(tab: tab)
        } else {
            withAnimation(MochyTheme.snappySpring) {
                selectedTab = tab
            }
        }
    }

    private func appendToCurrentPath(_ route: AppRoute) {
        switch selectedTab {
        case .home:
            homePath.append(route)
        case .explore:
            explorePath.append(route)
        case .search:
            searchPath.append(route)
        case .library:
            libraryPath.append(route)
        case .settings:
            settingsPath.append(route)
        }
    }
}
