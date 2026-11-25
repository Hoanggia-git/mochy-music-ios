import Foundation

// MARK: - Persistence Record Models

struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var track: Track
    var playedAt: Date

    init(id: UUID = UUID(), track: Track, playedAt: Date = Date()) {
        self.id = id
        self.track = track
        self.playedAt = playedAt
    }
}

struct DownloadedTrackRecord: Identifiable, Codable, Hashable {
    var id: String { track.id }
    var track: Track
    var localFileName: String
    var fileSizeBytes: Int64
    var downloadedAt: Date
}

struct ListeningStats: Codable {
    var totalListeningSeconds: TimeInterval = 0
    var trackPlayCounts: [String: Int] = [:]
    var artistPlayCounts: [String: Int] = [:]
    var trackMetadata: [String: Track] = [:]
    var artistMetadata: [String: Artist] = [:]
    var dailyListeningSeconds: [String: TimeInterval] = [:] // yyyy-MM-dd
    var monthlyTrackPlays: [String: [String: Int]] = [:]    // yyyy-MM -> [trackId: count]

    var topTracks: [(track: Track, count: Int)] {
        trackPlayCounts
            .sorted { $0.value > $1.value }
            .compactMap { key, count in
                guard let track = trackMetadata[key] else { return nil }
                return (track, count)
            }
    }

    var topArtists: [(artist: Artist, count: Int)] {
        artistPlayCounts
            .sorted { $0.value > $1.value }
            .compactMap { key, count in
                guard let artist = artistMetadata[key] else { return nil }
                return (artist, count)
            }
    }
}

struct MochyFullBackup: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var favorites: [Track]
    var playlists: [UserPlaylist]
    var recentlyPlayed: [HistoryEntry]
    var downloadedTracks: [DownloadedTrackRecord]
    var searchHistory: [String]
    var listeningStats: ListeningStats
    var importSessions: [ImportSession]
    var settingsBackup: [String: String]
}

// MARK: - PersistenceManager

/// JSON file-based persistence manager stored under `Documents/MochyMusicData/`.
final class PersistenceManager {
    static let shared = PersistenceManager()
    static let currentSchemaVersion = 1

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let ioQueue = DispatchQueue(label: "com.mochyy.mochymusic.persistence", qos: .utility)

    private enum FileName {
        static let schemaVersion = "schema_version.json"
        static let favorites = "favorites.json"
        static let playlists = "playlists.json"
        static let recentlyPlayed = "recently_played.json"
        static let downloads = "downloaded_tracks.json"
        static let searchHistory = "search_history.json"
        static let listeningStats = "listening_stats.json"
        static let importSessions = "import_sessions.json"
        static let settingsBackup = "settings_backup.json"
    }

    private struct SchemaVersionBox: Codable {
        var version: Int
    }

    private init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        ensureDirectoryExists()
        migrateIfNeeded()
    }

    var dataDirectoryURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return docs.appendingPathComponent("MochyMusicData", isDirectory: true)
    }

    var downloadsDirectoryURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return docs.appendingPathComponent("Downloads", isDirectory: true)
    }

    private func ensureDirectoryExists() {
        for dir in [dataDirectoryURL, downloadsDirectoryURL] {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Migration

    func migrateIfNeeded() {
        let saved = load(SchemaVersionBox.self, from: FileName.schemaVersion)?.version ?? 0
        if saved < Self.currentSchemaVersion {
            // Future schema migrations hook here.
            save(SchemaVersionBox(version: Self.currentSchemaVersion), to: FileName.schemaVersion)
        }
    }

    // MARK: - Favorites

    func loadFavorites() -> [Track] {
        load([Track].self, from: FileName.favorites) ?? []
    }

    func saveFavorites(_ favorites: [Track]) {
        save(favorites, to: FileName.favorites)
    }

    // MARK: - Playlists

    func loadPlaylists() -> [UserPlaylist] {
        load([UserPlaylist].self, from: FileName.playlists) ?? []
    }

    func savePlaylists(_ playlists: [UserPlaylist]) {
        save(playlists, to: FileName.playlists)
    }

    // MARK: - Recently Played

    func loadRecentlyPlayed() -> [HistoryEntry] {
        load([HistoryEntry].self, from: FileName.recentlyPlayed) ?? []
    }

    func saveRecentlyPlayed(_ entries: [HistoryEntry]) {
        save(entries, to: FileName.recentlyPlayed)
    }

    // MARK: - Downloaded Tracks

    func loadDownloadedTracks() -> [DownloadedTrackRecord] {
        load([DownloadedTrackRecord].self, from: FileName.downloads) ?? []
    }

    func saveDownloadedTracks(_ records: [DownloadedTrackRecord]) {
        save(records, to: FileName.downloads)
    }

    // MARK: - Search History

    func loadSearchHistory() -> [String] {
        load([String].self, from: FileName.searchHistory) ?? []
    }

    func saveSearchHistory(_ history: [String]) {
        save(history, to: FileName.searchHistory)
    }

    // MARK: - Listening Stats

    func loadListeningStats() -> ListeningStats {
        load(ListeningStats.self, from: FileName.listeningStats) ?? ListeningStats()
    }

    func saveListeningStats(_ stats: ListeningStats) {
        save(stats, to: FileName.listeningStats)
    }

    // MARK: - Import Sessions

    func loadImportSessions() -> [ImportSession] {
        load([ImportSession].self, from: FileName.importSessions) ?? []
    }

    func saveImportSessions(_ sessions: [ImportSession]) {
        save(sessions, to: FileName.importSessions)
    }

    // MARK: - Settings Backup

    func snapshotUserDefaultsSettings() -> [String: String] {
        let dict = UserDefaults.standard.dictionaryRepresentation()
        var stringified: [String: String] = [:]
        for (key, value) in dict {
            if value is String || value is Bool || value is Int || value is Double || value is Float {
                stringified[key] = "\(value)"
            }
        }
        save(stringified, to: FileName.settingsBackup)
        return stringified
    }

    func loadSettingsBackup() -> [String: String] {
        load([String: String].self, from: FileName.settingsBackup) ?? [:]
    }

    // MARK: - Full Backup Export & Restore

    func createFullBackup() -> MochyFullBackup {
        MochyFullBackup(
            schemaVersion: Self.currentSchemaVersion,
            exportedAt: Date(),
            favorites: loadFavorites(),
            playlists: loadPlaylists(),
            recentlyPlayed: loadRecentlyPlayed(),
            downloadedTracks: loadDownloadedTracks(),
            searchHistory: loadSearchHistory(),
            listeningStats: loadListeningStats(),
            importSessions: loadImportSessions(),
            settingsBackup: snapshotUserDefaultsSettings()
        )
    }

    func exportBackupData() throws -> Data {
        try encoder.encode(createFullBackup())
    }

    func restoreBackup(from data: Data) throws -> MochyFullBackup {
        let backup = try decoder.decode(MochyFullBackup.self, from: data)
        saveFavorites(backup.favorites)
        savePlaylists(backup.playlists)
        saveRecentlyPlayed(backup.recentlyPlayed)
        saveDownloadedTracks(backup.downloadedTracks)
        saveSearchHistory(backup.searchHistory)
        saveListeningStats(backup.listeningStats)
        saveImportSessions(backup.importSessions)
        save(backup.settingsBackup, to: FileName.settingsBackup)
        return backup
    }

    // MARK: - Generic Atomic File IO

    func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        ioQueue.sync {
            let url = dataDirectoryURL.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? decoder.decode(type, from: data)
        }
    }

    func save<T: Encodable>(_ value: T, to fileName: String) {
        ioQueue.sync {
            ensureDirectoryExists()
            let url = dataDirectoryURL.appendingPathComponent(fileName)
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }
}
