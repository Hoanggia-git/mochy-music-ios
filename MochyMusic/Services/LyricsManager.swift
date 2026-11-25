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
        case .simpMusic:
            return try await SimpMusicLyricsService.shared.fetchLyrics(
                videoId: track.id,
                durationSeconds: track.durationSeconds
            )
        case .youLyPlus:
            return try await YouLyPlusLyricsService.shared.fetchLyrics(
                videoId: track.id,
                title: track.title,
                artist: artist,
                album: album,
                durationSeconds: track.durationSeconds
            )
        case .paxsenix:
            return try await PaxsenixLyricsService.shared.fetchLyrics(
                title: track.title,
                artist: artist,
                album: album,
                durationSeconds: track.durationSeconds
            )
        case .kugou:
            return try await KuGouLyricsService.shared.fetchLyrics(
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
        case .lrcRed:
            return try await LrcRedLyricsService.shared.fetchLyrics(
                title: track.title,
                artist: artist,
                durationSeconds: track.durationSeconds
            )
        case .netEase, .qqMusic, .deezer, .unison:
            return nil
        }
    }
}
