import Foundation

/// LrcLib lyrics provider (https://lrclib.net/api/search).
final class LrcLibService {
    static let shared = LrcLibService()

    private let baseURL = "https://lrclib.net/api/search"
    private let userAgent = "Mochy (+https://github.com/realidkroo/Mochy-Music)"
    private let session: URLSession

    private struct LrcLibTrackDTO: Decodable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static let titleCleanupPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\s*\(.*?(official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit).*?\)"#,
            #"\s*\[.*?(official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit).*?\]"#,
            #"\s*【.*?】"#,
            #"\s*\|.*$"#,
            #"\s*-\s*(official|video|audio|lyrics|lyric|visualizer).*$"#,
            #"\s*\(feat\..*?\)"#,
            #"\s*\(ft\..*?\)"#,
            #"\s*feat\..*$"#,
            #"\s*ft\..*$"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    private static let artistSeparators = [
        " & ", " and ", ", ", " x ", " X ", " feat. ", " feat ", " ft. ", " ft ", " featuring ", " with "
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func fetchLyrics(
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int? = nil
    ) async throws -> LyricsResult? {
        let cleanedTitle = Self.cleanTitle(title)
        let cleanedArtist = Self.cleanArtist(artist)
        let candidates = await queryMultiStrategy(
            rawTitle: title,
            rawArtist: artist,
            cleanedTitle: cleanedTitle,
            cleanedArtist: cleanedArtist,
            album: album
        )

        guard !candidates.isEmpty else { return nil }

        let best = selectBestMatch(
            from: candidates,
            targetTitle: cleanedTitle,
            targetArtist: cleanedArtist,
            durationSeconds: durationSeconds
        )

        guard let best else { return nil }
        let synced = best.syncedLyrics.map { Self.parseLRC($0) }
        let plain = best.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)

        if (synced?.isEmpty ?? true) && (plain?.isEmpty ?? true) {
            return nil
        }

        return LyricsResult(
            syncedLines: synced?.isEmpty == false ? synced : nil,
            plainText: plain?.isEmpty == false ? plain : synced?.map(\.text).joined(separator: "\n"),
            source: LyricsProvider.lrclib.displayName
        )
    }

    // MARK: - Title & Artist Cleaning

    static func cleanTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for regex in titleCleanupPatterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    static func cleanArtist(_ artist: String) -> String {
        var cleaned = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in artistSeparators {
            if let range = cleaned.range(of: separator, options: .caseInsensitive) {
                cleaned = String(cleaned[..<range.lowerBound])
                break
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Multi-strategy Search

    private func queryMultiStrategy(
        rawTitle: String,
        rawArtist: String,
        cleanedTitle: String,
        cleanedArtist: String,
        album: String?
    ) async -> [LrcLibTrackDTO] {
        // 1. Track + Artist + Album
        var results = await searchAPI(trackName: cleanedTitle, artistName: cleanedArtist, albumName: album)
        if !results.isEmpty { return results }

        // 2. Track only
        results = await searchAPI(trackName: cleanedTitle)
        if !results.isEmpty { return results }

        // 3. Free-text Artist + Title
        results = await searchAPI(query: "\(cleanedArtist) \(cleanedTitle)")
        if !results.isEmpty { return results }

        // 4. Free-text Title only
        results = await searchAPI(query: cleanedTitle)
        if !results.isEmpty { return results }

        // 5. Raw title + artist if cleaning altered title
        if cleanedTitle != rawTitle.trimmingCharacters(in: .whitespacesAndNewlines) {
            results = await searchAPI(
                trackName: rawTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                artistName: rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return results
    }

    private func searchAPI(
        trackName: String? = nil,
        artistName: String? = nil,
        albumName: String? = nil,
        query: String? = nil
    ) async -> [LrcLibTrackDTO] {
        guard var components = URLComponents(string: baseURL) else { return [] }
        var items: [URLQueryItem] = []
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let trackName, !trackName.isEmpty { items.append(URLQueryItem(name: "track_name", value: trackName)) }
        if let artistName, !artistName.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artistName)) }
        if let albumName, !albumName.isEmpty { items.append(URLQueryItem(name: "album_name", value: albumName)) }
        components.queryItems = items

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode([LrcLibTrackDTO].self, from: data)
            return decoded.filter {
                !($0.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || !($0.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
        } catch {
            return []
        }
    }

    // MARK: - Best Match Selection

    private func selectBestMatch(
        from candidates: [LrcLibTrackDTO],
        targetTitle: String,
        targetArtist: String,
        durationSeconds: Int?
    ) -> LrcLibTrackDTO? {
        let scored: [(track: LrcLibTrackDTO, score: Double)] = candidates.map { candidate in
            var score = 0.0
            if candidate.syncedLyrics != nil { score += 5.0 }

            let titleSim = stringSimilarity(targetTitle, candidate.trackName ?? "")
            let artistSim = stringSimilarity(targetArtist, candidate.artistName ?? "")
            score += titleSim * 4.0 + artistSim * 3.0

            if let targetDuration = durationSeconds, targetDuration > 0, let candDuration = candidate.duration {
                let diff = abs(Int(candDuration.rounded()) - targetDuration)
                if diff <= 2 {
                    score += 6.0
                } else if diff <= 5 {
                    score += 3.0
                } else if diff > 15 {
                    score -= 4.0
                }
            }
            return (candidate, score)
        }
        return scored.max(by: { $0.score < $1.score })?.track
    }

    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        let s1 = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let s2 = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }
        if s1.contains(s2) || s2.contains(s1) { return 0.8 }

        let aChars = Array(s1)
        let bChars = Array(s2)
        var matrix = Array(repeating: Array(repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
        for i in 0...aChars.count { matrix[i][0] = i }
        for j in 0...bChars.count { matrix[0][j] = j }
        for i in 1...aChars.count {
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        let maxLen = max(aChars.count, bChars.count)
        return 1.0 - Double(matrix[aChars.count][bChars.count]) / Double(maxLen)
    }

    // MARK: - LRC Parsing

    static func parseLRC(_ lrc: String) -> [LyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lines: [LyricLine] = []
        let rawLines = lrc.components(separatedBy: .newlines)

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            // Skip word-level metadata tags emitted by TTML->LRC converters (<word:start:end|...>)
            if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") { continue }

            let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            let matches = regex.matches(in: trimmed, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }

            guard let lastMatch = matches.last,
                  let textStart = Range(lastMatch.range, in: trimmed)?.upperBound else { continue }
            var text = String(trimmed[textStart...]).trimmingCharacters(in: .whitespaces)
            // Strip optional BetterLyrics agent/background prefixes
            if text.hasPrefix("{agent:") || text.hasPrefix("{bg}") {
                if let endBrace = text.firstIndex(of: "}") {
                    text = String(text[text.index(after: endBrace)...]).trimmingCharacters(in: .whitespaces)
                }
            }

            for match in matches {
                guard let minRange = Range(match.range(at: 1), in: trimmed),
                      let secRange = Range(match.range(at: 2), in: trimmed),
                      let minutes = Double(trimmed[minRange]),
                      let seconds = Double(trimmed[secRange]) else { continue }

                var fraction: Double = 0
                if match.range(at: 3).location != NSNotFound,
                   let fracRange = Range(match.range(at: 3), in: trimmed) {
                    let fracStr = String(trimmed[fracRange])
                    if let val = Double(fracStr) {
                        switch fracStr.count {
                        case 1: fraction = val / 10.0
                        case 2: fraction = val / 100.0
                        default: fraction = val / 1000.0
                        }
                    }
                }

                let time = minutes * 60.0 + seconds + fraction
                lines.append(LyricLine(time: time, text: text))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }
}
