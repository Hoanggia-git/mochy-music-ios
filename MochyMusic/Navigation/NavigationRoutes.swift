import Foundation

/// Top-level navigation tabs in Mochy Music.
enum AppTab: String, Codable, CaseIterable, Identifiable {
    case home
    case explore
    case search
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Trang chủ"
        case .explore: return "Khám phá"
        case .search: return "Tìm kiếm"
        case .library: return "Thư viện"
        case .settings: return "Cài đặt"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .explore: return "sparkles"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        case .settings: return "gearshape"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "sparkles"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Every navigable destination across the entire Mochy Music iOS app.
enum AppRoute: Hashable, Identifiable {
    case home
    case explore
    case search
    case browse(browseId: String, title: String, params: String? = nil)
    case library
    case favorites
    case downloads
    case history
    case localFiles
    case album(id: String)
    case artist(id: String)
    case playlist(id: String, isLocal: Bool = false)
    case localPlaylist(id: UUID)
    case sectionDetail(title: String, browseId: String? = nil, params: String? = nil)
    case settings
    case equalizer
    case importMusic
    case profile
    case recap
    case nowPlaying

    var id: String {
        switch self {
        case .home: return "home"
        case .explore: return "explore"
        case .search: return "search"
        case .browse(let browseId, let title, _): return "browse_\(browseId)_\(title)"
        case .library: return "library"
        case .favorites: return "favorites"
        case .downloads: return "downloads"
        case .history: return "history"
        case .localFiles: return "localFiles"
        case .album(let id): return "album_\(id)"
        case .artist(let id): return "artist_\(id)"
        case .playlist(let id, let isLocal): return "playlist_\(id)_\(isLocal)"
        case .localPlaylist(let id): return "localPlaylist_\(id.uuidString)"
        case .sectionDetail(let title, let browseId, _): return "section_\(title)_\(browseId ?? "")"
        case .settings: return "settings"
        case .equalizer: return "equalizer"
        case .importMusic: return "importMusic"
        case .profile: return "profile"
        case .recap: return "recap"
        case .nowPlaying: return "nowPlaying"
        }
    }
}
