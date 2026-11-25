import Foundation

struct Track: Identifiable, Codable, Hashable {
    let id: String // YouTube videoId
    var title: String
    var artist: String
    var album: String?
    var durationSeconds: Int?
    var thumbnailURL: String?

    var formattedDuration: String {
        guard let durationSeconds, durationSeconds > 0 else { return "" }
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var artworkURL: URL? {
        guard let thumbnailURL else { return nil }
        return URL(string: thumbnailURL)
    }
}

struct UserPlaylist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var tracks: [Track]

    init(id: UUID = UUID(), name: String, tracks: [Track] = []) {
        self.id = id
        self.name = name
        self.tracks = tracks
    }
}

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: TimeInterval
    let text: String
}

struct LyricsResult: Hashable {
    let syncedLines: [LyricLine]
    let plainText: String?

    var hasSynced: Bool { !syncedLines.isEmpty }
}

enum RepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one
}
