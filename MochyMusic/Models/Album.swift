import Foundation

/// Album metadata matching Mochy Music's AlbumEntity & YouTube Music album pages.
struct Album: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var artists: [Artist]
    var year: Int?
    var thumbnailURL: String?
    var tracks: [Track]
    var browseId: String?
    var playlistId: String?
    var songCount: Int
    var duration: Int
    var explicit: Bool
    var description: String?
    var isLocal: Bool
    var bookmarkedAt: Date?
    var inLibrary: Date?

    var artworkURL: URL? {
        guard let urlString = thumbnailURL, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var artistsText: String {
        let names = artists.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "Unknown Artist" : names.joined(separator: ", ")
    }

    init(
        id: String,
        name: String,
        artists: [Artist] = [],
        year: Int? = nil,
        thumbnailURL: String? = nil,
        tracks: [Track] = [],
        browseId: String? = nil,
        playlistId: String? = nil,
        songCount: Int = 0,
        duration: Int = 0,
        explicit: Bool = false,
        description: String? = nil,
        isLocal: Bool = false,
        bookmarkedAt: Date? = nil,
        inLibrary: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.artists = artists
        self.year = year
        self.thumbnailURL = thumbnailURL
        self.tracks = tracks
        self.browseId = browseId ?? id
        self.playlistId = playlistId
        self.songCount = songCount > 0 ? songCount : tracks.count
        self.duration = duration
        self.explicit = explicit
        self.description = description
        self.isLocal = isLocal
        self.bookmarkedAt = bookmarkedAt
        self.inLibrary = inLibrary
    }
}
