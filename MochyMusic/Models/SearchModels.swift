import Foundation

/// Filter categories for YouTube Music InnerTube search.
enum SearchFilter: String, Codable, CaseIterable, Identifiable {
    case songs
    case videos
    case albums
    case artists
    case playlists
    case communityPlaylists

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .songs: return "Bài hát"
        case .videos: return "Video"
        case .albums: return "Album"
        case .artists: return "Nghệ sĩ"
        case .playlists: return "Playlist"
        case .communityPlaylists: return "Playlist cộng đồng"
        }
    }

    /// InnerTube search `params` value corresponding to this filter.
    var innertubeParams: String {
        switch self {
        case .songs: return "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        case .videos: return "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
        case .albums: return "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
        case .artists: return "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
        case .playlists: return "EgWKAQIoAWoKEAkQChAFEAMQBA%3D%3D"
        case .communityPlaylists: return "EgeKAQQoAEABagwQDhAKEAMQBRAJEAQ%3D"
        }
    }
}

/// Unified search result item across tracks, albums, artists, and playlists.
enum SearchResultItem: Identifiable, Hashable {
    case track(Track)
    case album(Album)
    case artist(Artist)
    case playlist(YouTubePlaylist)

    var id: String {
        switch self {
        case .track(let track): return "track_\(track.id)"
        case .album(let album): return "album_\(album.id)"
        case .artist(let artist): return "artist_\(artist.id)"
        case .playlist(let playlist): return "playlist_\(playlist.id)"
        }
    }
}

/// Paginated search response from InnerTube.
struct SearchResult: Identifiable, Hashable {
    let id: UUID
    var items: [SearchResultItem]
    var continuation: String?

    init(id: UUID = UUID(), items: [SearchResultItem] = [], continuation: String? = nil) {
        self.id = id
        self.items = items
        self.continuation = continuation
    }
}

/// Autocomplete or historical search suggestion item.
struct SearchSuggestion: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var isHistory: Bool

    init(id: UUID = UUID(), text: String, isHistory: Bool = false) {
        self.id = id
        self.text = text
        self.isHistory = isHistory
    }
}
