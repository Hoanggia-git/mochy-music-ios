import Foundation

/// Musixmatch API provider (`apic-desktop.musixmatch.com` / `apic.musixmatch.com`).
final class MusixmatchService {
    static let shared = MusixmatchService()

    private let baseURL = "https://apic-desktop.musixmatch.com/ws/1.1/"
    private let appId = "web-desktop-app-v1.0"
    private let tokenDefaultsKey = "mochy_musixmatch_user_token"
    private let session: URLSession
    private var cachedToken: String?
    private let lock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
        self.cachedToken = UserDefaults.standard.string(forKey: tokenDefaultsKey)
    }

    func fetchLyrics(title: String, artist: String, durationSeconds: Int? = nil) async throws -> LyricsResult? {
        let cleanedTitle = LrcLibService.cleanTitle(title)
        let cleanedArtist = LrcLibService.cleanArtist(artist)

        guard let track = await searchBestTrack(
            title: cleanedTitle,
            artist: cleanedArtist,
            durationSeconds: durationSeconds
        ) else {
            return nil
        }

        let trackId = track["track_id"] as? Int
        let commontrackId = track["commontrack_id"] as? Int

        // 1. Try synced subtitles first
        if let syncedLines = await fetchSyncedSubtitles(trackId: trackId, commontrackId: commontrackId),
           !syncedLines.isEmpty {
            let plain = syncedLines.map(\.text).joined(separator: "\n")
            return LyricsResult(
                syncedLines: syncedLines,
                plainText: plain,
                source: LyricsProvider.musixmatch.displayName
            )
        }

        // 2. Fallback to plain lyrics
        if let plain = await fetchPlainLyrics(trackId: trackId, commontrackId: commontrackId),
           !plain.isEmpty {
            return LyricsResult(
                syncedLines: nil,
                plainText: plain,
                source: LyricsProvider.musixmatch.displayName
            )
        }

        return nil
    }

    // MARK: - Token Management

    private func getToken(forceRefresh: Bool = false) async -> String? {
        if !forceRefresh {
            if let token = lock.withLock({ cachedToken }), !token.isEmpty {
                return token
            }
        }

        guard let json = await apiCall(method: "token.get", params: ["user_language": "en"], includeToken: false),
              let token = (json["user_token"] as? String),
              token.contains(where: { $0 != "0" }) else {
            return nil
        }

        lock.withLock {
            cachedToken = token
        }
        UserDefaults.standard.set(token, forKey: tokenDefaultsKey)
        return token
    }

    // MARK: - Search & Fetch

    private func searchBestTrack(title: String, artist: String, durationSeconds: Int?) async -> [String: Any]? {
        var candidates: [[String: Any]] = []
        if let strictBody = await authenticatedCall(
            method: "track.search",
            params: [
                "q_track": title,
                "q_artist": artist,
                "page_size": "10",
                "s_track_rating": "desc",
                "f_has_lyrics": "1"
            ]
        ), let list = strictBody["track_list"] as? [[String: Any]] {
            candidates.append(contentsOf: list.compactMap { $0["track"] as? [String: Any] })
        }

        if candidates.isEmpty,
           let looseBody = await authenticatedCall(
               method: "track.search",
               params: [
                   "q": "\(artist) \(title)",
                   "page_size": "10",
                   "s_track_rating": "desc",
                   "f_has_lyrics": "1"
               ]
           ),
           let list = looseBody["track_list"] as? [[String: Any]] {
            candidates.append(contentsOf: list.compactMap { $0["track"] as? [String: Any] })
        }

        guard !candidates.isEmpty else { return nil }

        let normTitle = normalize(title)
        let normArtist = normalize(artist)

        let scored = candidates.map { track -> (track: [String: Any], score: Int) in
            var score = 0
            let tName = normalize(track["track_name"] as? String ?? "")
            let aName = normalize(track["artist_name"] as? String ?? "")
            if tName == normTitle { score += 50 } else if tName.contains(normTitle) || normTitle.contains(tName) { score += 25 }
            if aName == normArtist { score += 40 } else if aName.contains(normArtist) || normArtist.contains(aName) { score += 20 }
            if (track["has_subtitles"] as? Int) == 1 { score += 15 }
            if let durationSeconds, durationSeconds > 0, let trackLen = track["track_length"] as? Int {
                let diff = abs(trackLen - durationSeconds)
                if diff <= 3 { score += 20 } else if diff > 15 { score -= 15 }
            }
            return (track, score)
        }

        return scored.max(by: { $0.score < $1.score })?.track
    }

    private func fetchSyncedSubtitles(trackId: Int?, commontrackId: Int?) async -> [LyricLine]? {
        var params: [String: String] = ["subtitle_format": "lrc"]
        if let trackId { params["track_id"] = String(trackId) }
        if let commontrackId { params["commontrack_id"] = String(commontrackId) }
        guard !params.isEmpty else { return nil }

        guard let body = await authenticatedCall(method: "track.subtitle.get", params: params),
              let subtitle = body["subtitle"] as? [String: Any],
              let subtitleBody = subtitle["subtitle_body"] as? String,
              !subtitleBody.isEmpty else {
            return nil
        }

        let lines = LrcLibService.parseLRC(subtitleBody)
        return lines.isEmpty ? nil : lines
    }

    private func fetchPlainLyrics(trackId: Int?, commontrackId: Int?) async -> String? {
        var params: [String: String] = [:]
        if let trackId { params["track_id"] = String(trackId) }
        if let commontrackId { params["commontrack_id"] = String(commontrackId) }
        guard !params.isEmpty else { return nil }

        guard let body = await authenticatedCall(method: "track.lyrics.get", params: params),
              let lyricsDict = body["lyrics"] as? [String: Any],
              let lyricsBody = lyricsDict["lyrics_body"] as? String else {
            return nil
        }

        let cleaned = lyricsBody
            .replacingOccurrences(of: "******* This Lyrics is NOT for Commercial use *******", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - HTTP Helpers

    private func authenticatedCall(method: String, params: [String: String]) async -> [String: Any]? {
        for attempt in 0..<2 {
            guard let token = await getToken(forceRefresh: attempt > 0) else { return nil }
            var merged = params
            merged["usertoken"] = token
            if let body = await apiCall(method: method, params: merged, includeToken: false) {
                return body
            }
        }
        return nil
    }

    private func apiCall(method: String, params: [String: String], includeToken: Bool) async -> [String: Any]? {
        guard var components = URLComponents(string: baseURL + method) else { return nil }
        var queryItems = [
            URLQueryItem(name: "app_id", value: appId),
            URLQueryItem(name: "format", value: "json")
        ]
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        if includeToken, let token = lock.withLock({ cachedToken }) {
            queryItems.append(URLQueryItem(name: "usertoken", value: token))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AWSELBCORS=0; x-mxm-user-id=;", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = root["message"] as? [String: Any],
                  let header = message["header"] as? [String: Any],
                  let statusCode = header["status_code"] as? Int else {
                return nil
            }
            guard statusCode == 200 else { return nil }
            return message["body"] as? [String: Any]
        } catch {
            return nil
        }
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
