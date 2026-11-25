import Foundation

/// Local user-created or imported playlist stored on device.
struct UserPlaylist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var tracks: [Track]
    var createdDate: Date
    var lastUpdatedDate: Date
    var thumbnailURL: String?
    var description: String?
    var isEditable: Bool
    var isAutoSync: Bool
    var mixItEnabled: Bool

    var artworkURL: URL? {
        guard let urlString = thumbnailURL ?? tracks.first?.thumbnailURL, !urlString.isEmpty else {
            return nil
        }
        return URL(string: urlString)
    }

    var totalDurationSeconds: Int {
        tracks.compactMap(\.durationSeconds).reduce(0, +)
    }

    init(
        id: UUID = UUID(),
        name: String,
        tracks: [Track] = [],
        createdDate: Date = Date(),
        lastUpdatedDate: Date = Date(),
        thumbnailURL: String? = nil,
        description: String? = nil,
        isEditable: Bool = true,
        isAutoSync: Bool = false,
        mixItEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.createdDate = createdDate
        self.lastUpdatedDate = lastUpdatedDate
        self.thumbnailURL = thumbnailURL
        self.description = description
        self.isEditable = isEditable
        self.isAutoSync = isAutoSync
        self.mixItEnabled = mixItEnabled
    }
}

/// Remote YouTube Music playlist returned from InnerTube search or browse endpoints.
struct YouTubePlaylist: Identifiable, Codable, Hashable {
    let id: String // browseId / playlistId
    var name: String
    var tracks: [Track]
    var thumbnailURL: String?
    var author: String?
    var songCount: Int?
    var description: String?
    var playEndpointParams: String?
    var shuffleEndpointParams: String?
    var radioEndpointParams: String?

    var artworkURL: URL? {
        guard let urlString = thumbnailURL ?? tracks.first?.thumbnailURL, !urlString.isEmpty else {
            return nil
        }
        return URL(string: urlString)
    }

    var shareURL: URL? {
        let cleanId = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        return URL(string: "https://music.youtube.com/playlist?list=\(cleanId)")
    }

    init(
        id: String,
        name: String,
        tracks: [Track] = [],
        thumbnailURL: String? = nil,
        author: String? = nil,
        songCount: Int? = nil,
        description: String? = nil,
        playEndpointParams: String? = nil,
        shuffleEndpointParams: String? = nil,
        radioEndpointParams: String? = nil
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.songCount = songCount
        self.description = description
        self.playEndpointParams = playEndpointParams
        self.shuffleEndpointParams = shuffleEndpointParams
        self.radioEndpointParams = radioEndpointParams
    }
}
