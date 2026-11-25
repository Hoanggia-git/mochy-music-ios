import Foundation

/// A titled shelf or carousel returned on Home / Explore / Browse pages.
struct HomeSection: Identifiable, Hashable {
    let id: UUID
    var title: String
    var subtitle: String?
    var items: [HomeSectionItem]
    var browseId: String?
    var params: String?
    var continuation: String?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        items: [HomeSectionItem] = [],
        browseId: String? = nil,
        params: String? = nil,
        continuation: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.browseId = browseId
        self.params = params
        self.continuation = continuation
    }
}

/// An item rendered inside a `HomeSection` or `BrowseResult`.
enum HomeSectionItem: Identifiable, Hashable {
    case track(Track)
    case album(Album)
    case artist(Artist)
    case playlist(YouTubePlaylist)

    var id: String {
        switch self {
        case .track(let track): return "home_track_\(track.id)"
        case .album(let album): return "home_album_\(album.id)"
        case .artist(let artist): return "home_artist_\(artist.id)"
        case .playlist(let playlist): return "home_playlist_\(playlist.id)"
        }
    }
}

/// Full browse page payload (e.g., Home, Explore, Charts, Moods & Genres).
struct BrowseResult: Identifiable, Hashable {
    let id: UUID
    var title: String?
    var sections: [HomeSection]
    var continuation: String?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        sections: [HomeSection] = [],
        continuation: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sections = sections
        self.continuation = continuation
    }
}

/// Mood or genre category tile used on Explore & Browse screens.
struct MoodAndGenreItem: Identifiable, Hashable {
    let id: String
    var title: String
    var browseId: String
    var params: String?
    var stripeColorHex: UInt32?

    init(id: String? = nil, title: String, browseId: String, params: String? = nil, stripeColorHex: UInt32? = nil) {
        self.id = id ?? "\(browseId)_\(params ?? "")"
        self.title = title
        self.browseId = browseId
        self.params = params
        self.stripeColorHex = stripeColorHex
    }
}
