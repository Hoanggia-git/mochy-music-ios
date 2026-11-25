import Foundation

/// Artist metadata matching Mochy Music's ArtistEntity & YouTube Music artist renderers.
struct Artist: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var thumbnailURL: String?
    var subscriberCount: String?
    var browseId: String?
    var channelId: String?
    var isLocal: Bool
    var bookmarkedAt: Date?

    var artworkURL: URL? {
        guard let urlString = thumbnailURL, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var isYouTubeArtist: Bool {
        id.hasPrefix("UC") || id.hasPrefix("FEmusic_library_privately_owned_artist")
    }

    var isPrivatelyOwnedArtist: Bool {
        id.hasPrefix("FEmusic_library_privately_owned_artist")
    }

    init(
        id: String? = nil,
        name: String,
        thumbnailURL: String? = nil,
        subscriberCount: String? = nil,
        browseId: String? = nil,
        channelId: String? = nil,
        isLocal: Bool = false,
        bookmarkedAt: Date? = nil
    ) {
        self.id = id ?? browseId ?? "LA_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))"
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.subscriberCount = subscriberCount
        self.browseId = browseId ?? id
        self.channelId = channelId
        self.isLocal = isLocal
        self.bookmarkedAt = bookmarkedAt
    }
}
