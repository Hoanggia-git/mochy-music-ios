import Foundation

/// SimpMusic lyrics provider with primary (`api-lyrics.simpmusic.org`) and fallback (`musicfy-yt-music-server.onrender.com`) endpoints.
final class SimpMusicLyricsService {
    static let shared = SimpMusicLyricsService()

    private let primaryBase = "https://api-lyrics.simpmusic.org/v1/"
    private let fallbackBase = "https://musicfy-yt-music-server.onrender.com/v1/"
    private let session: URLSession

    private struct SimpMusicResponseDTO: Decodable {
        let success: Bool?
        let data: [SimpMusicTrackDTO]?
    }

    private struct SimpMusicTrackDTO: Decodable {
        let duration: Int?
        let syncedLyrics: String?
        let richSyncLyrics: String?
        let plainLyrics: String?
        let plainLyric: String?
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    func fetchLyrics(videoId: String, durationSeconds: Int? = nil) async throws -> LyricsResult? {
        guard !videoId.isEmpty else { return nil }

        var tracks = await queryEndpoint(base: primaryBase, videoId: videoId)
        if tracks.isEmpty {
            tracks = await queryEndpoint(base: fallbackBase, videoId: videoId)
        }
        guard !tracks.isEmpty else { return nil }

        let validTracks: [SimpMusicTrackDTO]
        if let durationSeconds, durationSeconds > 0 {
            let filtered = tracks.filter { abs(($0.duration ?? 0) - durationSeconds) <= 10 }
            validTracks = filtered.isEmpty ? tracks : filtered
        } else {
            validTracks = tracks
        }

        let bestMatch: SimpMusicTrackDTO?
        if let durationSeconds, durationSeconds > 0, validTracks.count > 1 {
            bestMatch = validTracks.min { abs(($0.duration ?? 0) - durationSeconds) < abs(($1.duration ?? 0) - durationSeconds) }
        } else {
            bestMatch = validTracks.first
        }

        guard let bestMatch else { return nil }
        let syncedRaw = bestMatch.richSyncLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? bestMatch.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let plainRaw = bestMatch.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? bestMatch.plainLyric?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty

        if let syncedRaw {
            let lines = LrcLibService.parseLRC(syncedRaw)
            if !lines.isEmpty {
                return LyricsResult(
                    syncedLines: lines,
                    plainText: plainRaw ?? lines.map(\.text).joined(separator: "\n"),
                    source: LyricsProvider.simpMusic.displayName
                )
            }
        }

        if let plainRaw {
            return LyricsResult(
                syncedLines: nil,
                plainText: plainRaw,
                source: LyricsProvider.simpMusic.displayName
            )
        }

        return nil
    }

    private func queryEndpoint(base: String, videoId: String) async -> [SimpMusicTrackDTO] {
        guard let url = URL(string: base + videoId) else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SimpMusicLyrics/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(SimpMusicResponseDTO.self, from: data)
            if decoded.success == false { return [] }
            return decoded.data ?? []
        } catch {
            return []
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
