import Foundation

/// External playlist / library import source.
enum ImportSource: String, Codable, CaseIterable, Identifiable {
    case spotify
    case appleMusic
    case tidal
    case csv
    case youtube
    case device

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .tidal: return "TIDAL"
        case .csv: return "CSV"
        case .youtube: return "YouTube Music"
        case .device: return "Thiết bị"
        }
    }

    var iconName: String {
        switch self {
        case .spotify: return "music.note"
        case .appleMusic: return "music.note.list"
        case .tidal: return "waveform"
        case .csv: return "doc.text"
        case .youtube: return "play.rectangle"
        case .device: return "iphone"
        }
    }
}

/// Live progress snapshot emitted during a playlist import job.
struct ImportProgress: Identifiable, Hashable {
    let id: UUID
    var source: ImportSource
    var totalItems: Int
    var processedItems: Int
    var matchedItems: Int
    var failedItems: Int
    var currentItemName: String?
    var status: ImportStatus
    var errorMessage: String?
    var startedAt: Date

    var progress: Double {
        guard totalItems > 0 else { return 0 }
        return min(1.0, max(0.0, Double(processedItems) / Double(totalItems)))
    }

    enum ImportStatus: String, Codable, Hashable {
        case preparing
        case inProgress
        case matching
        case completed
        case failed
        case cancelled
    }

    init(
        id: UUID = UUID(),
        source: ImportSource,
        totalItems: Int = 0,
        processedItems: Int = 0,
        matchedItems: Int = 0,
        failedItems: Int = 0,
        currentItemName: String? = nil,
        status: ImportStatus = .preparing,
        errorMessage: String? = nil,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.totalItems = totalItems
        self.processedItems = processedItems
        self.matchedItems = matchedItems
        self.failedItems = failedItems
        self.currentItemName = currentItemName
        self.status = status
        self.errorMessage = errorMessage
        self.startedAt = startedAt
    }
}

/// Normalized playlist & track payload parsed from an external import source before matching.
struct ImportedPlaylist: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var source: ImportSource
    var authorName: String?
    var thumbnailURL: String?
    var remoteURL: String?
    var rawTracks: [ImportedRawTrack]
    var matchedTracks: [Track]
    var importedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        source: ImportSource,
        authorName: String? = nil,
        thumbnailURL: String? = nil,
        remoteURL: String? = nil,
        rawTracks: [ImportedRawTrack] = [],
        matchedTracks: [Track] = [],
        importedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.authorName = authorName
        self.thumbnailURL = thumbnailURL
        self.remoteURL = remoteURL
        self.rawTracks = rawTracks
        self.matchedTracks = matchedTracks
        self.importedAt = importedAt
    }
}

/// Unmatched track metadata parsed from Spotify / Apple Music / TIDAL / CSV.
struct ImportedRawTrack: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    var album: String?
    var durationSeconds: Int?
    var isrc: String?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int? = nil,
        isrc: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.isrc = isrc
    }
}

/// Persistent import history session record supporting undo & re-sync.
struct ImportSession: Identifiable, Codable, Hashable {
    let id: UUID
    var source: String
    var startedAt: Date
    var importedPlaylistIds: [String]

    init(
        id: UUID = UUID(),
        source: String,
        startedAt: Date = Date(),
        importedPlaylistIds: [String] = []
    ) {
        self.id = id
        self.source = source
        self.startedAt = startedAt
        self.importedPlaylistIds = importedPlaylistIds
    }
}
