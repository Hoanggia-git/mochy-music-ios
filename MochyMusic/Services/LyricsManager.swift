import Foundation

/// Orchestrates all lyrics providers in configurable priority order with in-memory NSCache caching.
@MainActor
final class LyricsManager: ObservableObject {
    static let shared = LyricsManager()

    @Published var currentLyrics: LyricsResult?
    @Published var currentTrackId: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private final class CachedLyricsBox: NSObject {
        let result: LyricsResult
        init(result: LyricsResult) {
            self.result = result
        }
    }

    private let cache: NSCache<NSString, CachedLyricsBox> = {
        let c = NSCache<NSString, CachedLyricsBox>()
        c.countLimit = 100
        return c
    }()

    private var fetchTask: Task<Void, Never>?

    private init() {}

    func fetchLyrics(for track: Track, forceRefresh: Bool = false) async -> LyricsResult? {
        let key = NSString(string: track.id)
        currentTrackId = track.id
        errorMessage = nil

        if !forceRefresh, let cached = cache.object(forKey: key) {
            currentLyrics = cached.result
            return cached.result
        }

        if forceRefresh {
            cache.removeObject(forKey: key)
        }

        if AppSettings.shared.offlineMode {
            errorMessage = "Offline mode is enabled."
            currentLyrics = nil
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        let settings = AppSettings.shared
        let orderedProviders = settings.lyricsProviderOrder
        let artistName = track.artistsText == "Unknown Artist" ? "" : track.artistsText
        let albumName = track.album?.name

        for provider in orderedProviders {
            guard isProviderEnabled(provider, settings: settings) else { continue }

            do {
                if let result = try await query(
                    provider: provider,
                    track: track,
                    artist: artistName,
                    album: albumName
                ) {
                    cache.setObject(CachedLyricsBox(result: result), forKey: key)
                    if currentTrackId == track.id {
                        currentLyrics = result
                    }
                    return result
                }
            } catch {
                continue
            }
        }

        // Final fallback: YouTube Music description lyrics or timed captions
        if let ytPlain = try? await InnerTubeService.shared.fetchYouTubeLyrics(videoId: track.id),
           !ytPlain.isEmpty {
            let result = LyricsResult(syncedLines: nil, plainText: ytPlain, source: "YouTube Music")
            cache.setObject(CachedLyricsBox(result: result), forKey: key)
            if currentTrackId == track.id {
                currentLyrics = result
            }
            return result
        }

        if currentTrackId == track.id {
            currentLyrics = nil
            errorMessage = "No lyrics found for this track."
        }
        return nil
    }

    func loadLyricsInBackground(for track: Track) {
        fetchTask?.cancel()
        fetchTask = Task {
            _ = await fetchLyrics(for: track)
        }
    }

    func activeLineIndex(at currentTime: TimeInterval) -> Int? {
        guard let lines = currentLyrics?.syncedLines, !lines.isEmpty else { return nil }
        var activeIndex: Int?
        for (index, line) in lines.enumerated() {
            if line.time <= currentTime + 0.15 {
                activeIndex = index
            } else {
                break
            }
        }
        return activeIndex
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Provider Dispatch

    private func isProviderEnabled(_ provider: LyricsProvider, settings: AppSettings) -> Bool {
        switch provider {
        case .lrclib: return settings.enableLrcLib
        case .betterLyrics: return settings.enableBetterLyrics
        case .genius: return settings.enableGenius
        case .musixmatch: return settings.enableMusixmatch
        case .kugou: return settings.enableKugou
        case .simpMusic: return settings.enableSimpMusic
        case .youLyPlus: return settings.enableYouLyPlus
        case .paxsenix: return settings.enablePaxsenix
        case .netEase: return settings.enableNetEase
        case .qqMusic: return settings.enableQQMusic
        case .deezer: return settings.enableDeezer
        case .lrcRed: return settings.enableLrcRed
        case .unison: return settings.enableUnison
        }
    }

    private func query(
        provider: LyricsProvider,
        track: Track,
        artist: String,
        album: String?
    ) async throws -> LyricsResult? {
        switch provider {
        case .lrclib:
            return try await LrcLibService.shared.fetchLyrics(
                title: track.title,
                artist: artist,
                album: album,
                durationSeconds: track.durationSeconds
            )
        case .betterLyrics:
            return try await BetterLyricsService.shared.fetchLyrics(
                videoId: track.id,
                title: track.title,
                artist: artist,
                album: album,
                durationSeconds: track.durationSeconds
            )
        case .musixmatch:
            return try await MusixmatchService.shared.fetchLyrics(
                title: track.title,
                artist: artist,
                durationSeconds: track.durationSeconds
            )
        case .genius:
            return try await GeniusLyricsService.shared.fetchLyrics(
                title: track.title,
                artist: artist
            )
        case .youLyPlus:
            return try await fetchYouLyPlus(track: track, artist: artist, album: album)
        case .simpMusic:
            return try await fetchSimpMusic(videoId: track.id)
        case .kugou, .paxsenix, .netEase, .qqMusic, .deezer, .lrcRed, .unison:
            return nil
        }
    }

    private func fetchYouLyPlus(track: Track, artist: String, album: String?) async throws -> LyricsResult? {
        guard var components = URLComponents(string: "https://lyricsplus.binimum.org/v2/lyrics/get") else {
            return nil
        }
        var items = [
            URLQueryItem(name: "title", value: LrcLibService.cleanTitle(track.title)),
            URLQueryItem(name: "artist", value: LrcLibService.cleanArtist(artist)),
            URLQueryItem(name: "source", value: "apple,lyricsplus,musixmatch,spotify")
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album", value: album))
        }
        if let duration = track.durationSeconds, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(duration)))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLyrics = json["lyrics"] as? [[String: Any]] else {
            return nil
        }

        let lines: [LyricLine] = rawLyrics.compactMap { entry in
            guard let text = entry["text"] as? String, !text.isEmpty else { return nil }
            let timeMs = entry["time"] as? Double ?? 0
            return LyricLine(time: timeMs / 1000.0, text: text)
        }
        guard !lines.isEmpty else { return nil }
        return LyricsResult(
            syncedLines: lines,
            plainText: lines.map(\.text).joined(separator: "\n"),
            source: LyricsProvider.youLyPlus.displayName
        )
    }

    private func fetchSimpMusic(videoId: String) async throws -> LyricsResult? {
        guard let url = URL(string: "https://api-lyrics.simpmusic.org/v1/\(videoId)") else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]],
              let first = entries.first else {
            return nil
        }
        if let synced = first["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = LrcLibService.parseLRC(synced)
            if !lines.isEmpty {
                return LyricsResult(
                    syncedLines: lines,
                    plainText: (first["plainLyric"] as? String) ?? lines.map(\.text).joined(separator: "\n"),
                    source: LyricsProvider.simpMusic.displayName
                )
            }
        }
        if let plain = first["plainLyric"] as? String, !plain.isEmpty {
            return LyricsResult(syncedLines: nil, plainText: plain, source: LyricsProvider.simpMusic.displayName)
        }
        return nil
    }
}
