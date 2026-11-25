import Foundation
import AVFoundation

/// Centralized local library store managing favorites, playlists, history, downloads, search history, stats, and local audio files.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published var favorites: [Track] = []
    @Published var playlists: [UserPlaylist] = []
    @Published var recentlyPlayed: [HistoryEntry] = []
    @Published var downloadedTracks: [DownloadedTrackRecord] = []
    @Published var searchHistory: [String] = []
    @Published var listeningStats: ListeningStats = ListeningStats()
    @Published var localTracks: [Track] = []
    @Published var isScanningLocal: Bool = false

    private let persistence = PersistenceManager.shared
    private let maxRecentlyPlayed = 100
    private let maxSearchHistory = 20

    private static let supportedAudioExtensions: Set<String> = [
        "mp3", "m4a", "flac", "wav", "aac", "alac", "aiff", "caf"
    ]

    private init() {
        reloadFromPersistence()
    }

    func reloadFromPersistence() {
        favorites = persistence.loadFavorites()
        playlists = persistence.loadPlaylists()
        recentlyPlayed = persistence.loadRecentlyPlayed()
        downloadedTracks = persistence.loadDownloadedTracks()
        searchHistory = persistence.loadSearchHistory()
        listeningStats = persistence.loadListeningStats()
    }

    // MARK: - Favorites

    func isFavorite(_ track: Track) -> Bool {
        isFavorite(trackId: track.id)
    }

    func isFavorite(trackId: String) -> Bool {
        favorites.contains { $0.id == trackId }
    }

    func toggleFavorite(_ track: Track) {
        if isFavorite(track) {
            removeFavorite(track)
        } else {
            addFavorite(track)
        }
    }

    func addFavorite(_ track: Track) {
        guard !isFavorite(track) else { return }
        var updated = track
        updated.liked = true
        updated.likedDate = Date()
        updated.inLibrary = updated.inLibrary ?? Date()
        favorites.insert(updated, at: 0)
        persistence.saveFavorites(favorites)

        if AppSettings.shared.autoDownloadOnLike && !isDownloaded(track.id) && !track.isLocal {
            DownloadManager.shared.download(track: updated)
        }
        if AppSettings.shared.lastFmEnabled && AppSettings.shared.lastFmSendLikes {
            Task {
                await ScrobbleService.shared.love(track: updated, loved: true)
            }
        }
    }

    func removeFavorite(_ track: Track) {
        favorites.removeAll { $0.id == track.id }
        persistence.saveFavorites(favorites)

        if AppSettings.shared.lastFmEnabled && AppSettings.shared.lastFmSendLikes {
            Task {
                await ScrobbleService.shared.love(track: track, loved: false)
            }
        }
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(
        name: String,
        description: String? = nil,
        tracks: [Track] = [],
        thumbnailURL: String? = nil
    ) -> UserPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = UserPlaylist(
            name: trimmed.isEmpty ? "New Playlist" : trimmed,
            tracks: tracks,
            thumbnailURL: thumbnailURL ?? tracks.first?.thumbnailURL,
            description: description
        )
        playlists.insert(playlist, at: 0)
        persistence.savePlaylists(playlists)
        return playlist
    }

    func deletePlaylist(_ playlist: UserPlaylist) {
        deletePlaylist(id: playlist.id)
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        persistence.savePlaylists(playlists)
    }

    func renamePlaylist(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = trimmed
        playlists[index].lastUpdatedDate = Date()
        persistence.savePlaylists(playlists)
    }

    func addTrack(_ track: Track, toPlaylist playlistId: UUID) {
        addTracks([track], toPlaylist: playlistId)
    }

    func addTracks(_ tracks: [Track], toPlaylist playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        for track in tracks {
            if !playlists[index].tracks.contains(where: { $0.id == track.id }) {
                playlists[index].tracks.append(track)
            }
        }
        if playlists[index].thumbnailURL == nil {
            playlists[index].thumbnailURL = playlists[index].tracks.first?.thumbnailURL
        }
        playlists[index].lastUpdatedDate = Date()
        persistence.savePlaylists(playlists)
    }

    func removeTrack(at trackIndex: Int, fromPlaylist playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }),
              playlists[index].tracks.indices.contains(trackIndex) else { return }
        playlists[index].tracks.remove(at: trackIndex)
        playlists[index].lastUpdatedDate = Date()
        persistence.savePlaylists(playlists)
    }

    func removeTrack(trackId: String, fromPlaylist playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].tracks.removeAll { $0.id == trackId }
        playlists[index].lastUpdatedDate = Date()
        persistence.savePlaylists(playlists)
    }

    func reorderTracks(inPlaylist playlistId: UUID, from source: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].tracks.move(fromOffsets: source, toOffset: destination)
        playlists[index].lastUpdatedDate = Date()
        persistence.savePlaylists(playlists)
    }

    // MARK: - Recently Played & Listening Stats

    func recordPlay(track: Track) {
        guard !AppSettings.shared.pauseListenHistory else { return }

        recentlyPlayed.removeAll { $0.track.id == track.id }
        recentlyPlayed.insert(HistoryEntry(track: track, playedAt: Date()), at: 0)
        if recentlyPlayed.count > maxRecentlyPlayed {
            recentlyPlayed = Array(recentlyPlayed.prefix(maxRecentlyPlayed))
        }
        persistence.saveRecentlyPlayed(recentlyPlayed)

        // Update track/artist play counts
        listeningStats.trackPlayCounts[track.id, default: 0] += 1
        listeningStats.trackMetadata[track.id] = track

        let monthKey = Self.monthFormatter.string(from: Date())
        var monthMap = listeningStats.monthlyTrackPlays[monthKey] ?? [:]
        monthMap[track.id, default: 0] += 1
        listeningStats.monthlyTrackPlays[monthKey] = monthMap

        for artist in track.artists {
            listeningStats.artistPlayCounts[artist.id, default: 0] += 1
            listeningStats.artistMetadata[artist.id] = artist
        }

        persistence.saveListeningStats(listeningStats)
    }

    func recordListeningTime(_ seconds: TimeInterval, for track: Track) {
        guard seconds > 0, !AppSettings.shared.pauseListenHistory else { return }
        listeningStats.totalListeningSeconds += seconds
        let dayKey = Self.dayFormatter.string(from: Date())
        listeningStats.dailyListeningSeconds[dayKey, default: 0] += seconds
        listeningStats.trackMetadata[track.id] = track
        persistence.saveListeningStats(listeningStats)
    }

    func clearRecentlyPlayed() {
        recentlyPlayed.removeAll()
        persistence.saveRecentlyPlayed([])
    }

    func listeningSecondsForLastDays(_ days: Int) -> [(date: String, seconds: TimeInterval)] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<days).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let key = Self.dayFormatter.string(from: date)
            return (key, listeningStats.dailyListeningSeconds[key] ?? 0)
        }
    }

    // MARK: - Downloads Tracking

    func isDownloaded(_ trackId: String) -> Bool {
        localFileURL(forTrackId: trackId) != nil
    }

    func localFileURL(forTrackId trackId: String) -> URL? {
        if let record = downloadedTracks.first(where: { $0.track.id == trackId }) {
            let fileURL = persistence.downloadsDirectoryURL.appendingPathComponent(record.localFileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        let fallbackURL = persistence.downloadsDirectoryURL.appendingPathComponent("\(trackId).m4a")
        return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }

    func markDownloaded(track: Track, fileName: String, fileSizeBytes: Int64) {
        var updatedTrack = track
        updatedTrack.isDownloaded = true
        updatedTrack.localFileURL = persistence.downloadsDirectoryURL.appendingPathComponent(fileName).path

        let record = DownloadedTrackRecord(
            track: updatedTrack,
            localFileName: fileName,
            fileSizeBytes: fileSizeBytes,
            downloadedAt: Date()
        )
        downloadedTracks.removeAll { $0.track.id == track.id }
        downloadedTracks.insert(record, at: 0)
        persistence.saveDownloadedTracks(downloadedTracks)
    }

    func removeDownload(trackId: String) {
        if let record = downloadedTracks.first(where: { $0.track.id == trackId }) {
            let url = persistence.downloadsDirectoryURL.appendingPathComponent(record.localFileName)
            try? FileManager.default.removeItem(at: url)
        }
        let fallback = persistence.downloadsDirectoryURL.appendingPathComponent("\(trackId).m4a")
        try? FileManager.default.removeItem(at: fallback)

        downloadedTracks.removeAll { $0.track.id == trackId }
        persistence.saveDownloadedTracks(downloadedTracks)
    }

    var totalDownloadSizeBytes: Int64 {
        downloadedTracks.reduce(0) { $0 + $1.fileSizeBytes }
    }

    // MARK: - Search History

    func addSearchQuery(_ query: String) {
        guard !AppSettings.shared.pauseSearchHistory else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchHistory.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searchHistory.insert(trimmed, at: 0)
        if searchHistory.count > maxSearchHistory {
            searchHistory = Array(searchHistory.prefix(maxSearchHistory))
        }
        persistence.saveSearchHistory(searchHistory)
    }

    func removeSearchQuery(_ query: String) {
        searchHistory.removeAll { $0 == query }
        persistence.saveSearchHistory(searchHistory)
    }

    func clearSearchHistory() {
        searchHistory.removeAll()
        persistence.saveSearchHistory([])
    }

    // MARK: - Local Music Scanner

    func scanLocalMusic() async {
        guard !isScanningLocal else { return }
        isScanningLocal = true
        defer { isScanningLocal = false }

        let fileManager = FileManager.default
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let downloadsURL = persistence.downloadsDirectoryURL

        let foundTracks = await Task.detached(priority: .utility) { () -> [Track] in
            guard let docsURL else { return [] }
            var results: [Track] = []
            let enumerator = fileManager.enumerator(
                at: docsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            var audioURLs: [URL] = []
            while let fileURL = enumerator?.nextObject() as? URL {
                // Skip app-managed MochyMusicData JSON folder & managed Downloads cache
                if fileURL.path.contains("/MochyMusicData/") || fileURL.deletingLastPathComponent() == downloadsURL {
                    continue
                }
                let ext = fileURL.pathExtension.lowercased()
                if Self.supportedAudioExtensions.contains(ext) {
                    audioURLs.append(fileURL)
                }
            }

            for url in audioURLs {
                let asset = AVURLAsset(url: url)
                let fallbackTitle = url.deletingPathExtension().lastPathComponent
                var title = fallbackTitle
                var artistName = "Unknown Artist"
                var albumName: String?
                var durationSeconds: Int?

                if let duration = try? await asset.load(.duration) {
                    let secs = CMTimeGetSeconds(duration)
                    if secs.isFinite && secs > 0 {
                        durationSeconds = Int(secs.rounded())
                    }
                }

                if let metadata = try? await asset.load(.commonMetadata) {
                    for item in metadata {
                        guard let commonKey = item.commonKey else { continue }
                        if commonKey == .commonKeyTitle, let value = try? await item.load(.stringValue), !value.isEmpty {
                            title = value
                        } else if commonKey == .commonKeyArtist, let value = try? await item.load(.stringValue), !value.isEmpty {
                            artistName = value
                        } else if commonKey == .commonKeyAlbumName, let value = try? await item.load(.stringValue), !value.isEmpty {
                            albumName = value
                        }
                    }
                }

                let artist = Artist(name: artistName, isLocal: true)
                let album = albumName.map {
                    Album(id: "local_album_\($0)", name: $0, artists: [artist], isLocal: true)
                }
                let track = Track(
                    id: "local_\(url.lastPathComponent)_\(abs(url.path.hashValue))",
                    title: title,
                    artists: [artist],
                    album: album,
                    durationSeconds: durationSeconds,
                    isLocal: true,
                    localFileURL: url.path
                )
                results.append(track)
            }
            return results.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }.value

        localTracks = foundTracks
    }

    // MARK: - Formatters

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private static let monthFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
}
