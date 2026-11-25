import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var favorites: [Track] = []
    @Published private(set) var recentlyPlayed: [Track] = []
    @Published private(set) var playlists: [UserPlaylist] = []
    @Published private(set) var downloadedTracks: [Track] = []
    @Published private(set) var downloadingIDs: Set<String> = []

    private let fileManager = FileManager.default

    private struct PersistedState: Codable {
        var favorites: [Track]
        var recentlyPlayed: [Track]
        var playlists: [UserPlaylist]
        var downloadedTracks: [Track]
    }

    private var stateFileURL: URL {
        documentsDirectory.appendingPathComponent("mochy_library.json")
    }

    private var downloadsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        load()
    }

    // MARK: - Favorites

    func isFavorite(_ track: Track) -> Bool {
        favorites.contains(where: { $0.id == track.id })
    }

    func toggleFavorite(_ track: Track) {
        if let idx = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: idx)
        } else {
            favorites.insert(track, at: 0)
        }
        save()
    }

    // MARK: - Recently Played

    func recordPlay(_ track: Track) {
        recentlyPlayed.removeAll(where: { $0.id == track.id })
        recentlyPlayed.insert(track, at: 0)
        if recentlyPlayed.count > 50 {
            recentlyPlayed = Array(recentlyPlayed.prefix(50))
        }
        save()
    }

    // MARK: - Playlists

    func createPlaylist(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists.append(UserPlaylist(name: trimmed))
        save()
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll(where: { $0.id == id })
        save()
    }

    func addTrack(_ track: Track, toPlaylist playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if !playlists[idx].tracks.contains(where: { $0.id == track.id }) {
            playlists[idx].tracks.append(track)
            save()
        }
    }

    func removeTrack(_ track: Track, fromPlaylist playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].tracks.removeAll(where: { $0.id == track.id })
        save()
    }

    // MARK: - Offline Downloads

    func localAudioURL(for trackID: String) -> URL? {
        let url = downloadsDirectory.appendingPathComponent("\(trackID).m4a")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(_ track: Track) -> Bool {
        localAudioURL(for: track.id) != nil
    }

    func downloadTrack(_ track: Track) async {
        guard !isDownloaded(track), !downloadingIDs.contains(track.id) else { return }
        downloadingIDs.insert(track.id)
        defer { downloadingIDs.remove(track.id) }

        do {
            let stream = try await InnerTubeService.shared.resolveStream(videoId: track.id)
            var request = URLRequest(url: stream.url)
            request.setValue(stream.userAgent, forHTTPHeaderField: "User-Agent")

            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return
            }
            let destination = downloadsDirectory.appendingPathComponent("\(track.id).m4a")
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: tempURL, to: destination)

            downloadedTracks.removeAll(where: { $0.id == track.id })
            downloadedTracks.insert(track, at: 0)
            save()
        } catch {
            // Silently ignore failed download in MVP; UI resets spinner
        }
    }

    func removeDownload(_ track: Track) {
        let url = downloadsDirectory.appendingPathComponent("\(track.id).m4a")
        try? fileManager.removeItem(at: url)
        downloadedTracks.removeAll(where: { $0.id == track.id })
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        favorites = state.favorites
        recentlyPlayed = state.recentlyPlayed
        playlists = state.playlists
        downloadedTracks = state.downloadedTracks.filter { isDownloaded($0) }
    }

    private func save() {
        let state = PersistedState(
            favorites: favorites,
            recentlyPlayed: recentlyPlayed,
            playlists: playlists,
            downloadedTracks: downloadedTracks
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }
}
