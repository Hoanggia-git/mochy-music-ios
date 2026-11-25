import Foundation

/// Core audio/video track model matching Mochy Music's SongEntity & InnerTube track metadata.
struct Track: Identifiable, Codable, Hashable {
    let id: String // YouTube videoId or local track identifier
    var title: String
    var artists: [Artist]
    var album: Album?
    var durationSeconds: Int?
    var thumbnailURL: String?
    var explicit: Bool
    var isLocal: Bool
    var localFileURL: String?
    var isVideo: Bool
    var isDownloaded: Bool
    var liked: Bool
    var likedDate: Date?
    var inLibrary: Date?
    var totalPlayTime: TimeInterval
    var genre: String?
    var year: Int?

    /// Duration formatted as `m:ss` or `h:mm:ss`.
    var formattedDuration: String {
        guard let duration = durationSeconds, duration >= 0 else { return "--:--" }
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Resolved `URL` for artwork thumbnail if valid.
    var artworkURL: URL? {
        guard let urlString = thumbnailURL, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    /// Comma-separated list of artist names, falling back to `"Unknown Artist"`.
    var artistsText: String {
        let names = artists.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "Unknown Artist" : names.joined(separator: ", ")
    }

    /// Resolved local file `URL` if `localFileURL` is set.
    var resolvedLocalURL: URL? {
        guard let localFileURL, !localFileURL.isEmpty else { return nil }
        if localFileURL.hasPrefix("file://") {
            return URL(string: localFileURL)
        }
        return URL(fileURLWithPath: localFileURL)
    }

    init(
        id: String,
        title: String,
        artists: [Artist] = [],
        album: Album? = nil,
        durationSeconds: Int? = nil,
        thumbnailURL: String? = nil,
        explicit: Bool = false,
        isLocal: Bool = false,
        localFileURL: String? = nil,
        isVideo: Bool = false,
        isDownloaded: Bool = false,
        liked: Bool = false,
        likedDate: Date? = nil,
        inLibrary: Date? = nil,
        totalPlayTime: TimeInterval = 0,
        genre: String? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.explicit = explicit
        self.isLocal = isLocal
        self.localFileURL = localFileURL
        self.isVideo = isVideo
        self.isDownloaded = isDownloaded
        self.liked = liked
        self.likedDate = likedDate
        self.inLibrary = inLibrary
        self.totalPlayTime = totalPlayTime
        self.genre = genre
        self.year = year
    }
}
