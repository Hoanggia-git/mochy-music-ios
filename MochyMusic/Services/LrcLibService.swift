import Foundation

final class LrcLibService {
    static let shared = LrcLibService()

    private let session: URLSession
    private let userAgent = "MochyMusic-iOS (+https://github.com/realidkroo/Mochy-Music)"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    private struct LrcLibTrackDTO: Decodable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    func fetchLyrics(for track: Track) async -> LyricsResult? {
        let cleanedTitle = cleanTitle(track.title)
        let cleanedArtist = cleanArtist(track.artist)

        let candidates: [[String: String]] = [
            ["track_name": cleanedTitle, "artist_name": cleanedArtist],
            ["track_name": cleanedTitle],
            ["q": "\(cleanedArtist) \(cleanedTitle)"],
            ["q": cleanedTitle]
        ]

        for params in candidates {
            let results = await querySearch(params: params)
            if let best = selectBest(from: results, targetDuration: track.durationSeconds) {
                let parsed = best.syncedLyrics.map { parseLRC($0) } ?? []
                if !parsed.isEmpty || (best.plainLyrics?.isEmpty == false) {
                    return LyricsResult(syncedLines: parsed, plainText: best.plainLyrics)
                }
            }
        }
        return nil
    }

    private func querySearch(params: [String: String]) async -> [LrcLibTrackDTO] {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = params.compactMap { key, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : URLQueryItem(name: key, value: trimmed)
        }
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode([LrcLibTrackDTO].self, from: data)
            return decoded.filter {
                ($0.syncedLyrics?.isEmpty == false) || ($0.plainLyrics?.isEmpty == false)
            }
        } catch {
            return []
        }
    }

    private func selectBest(from items: [LrcLibTrackDTO], targetDuration: Int?) -> LrcLibTrackDTO? {
        guard !items.isEmpty else { return nil }
        let synced = items.filter { $0.syncedLyrics?.isEmpty == false }
        let pool = synced.isEmpty ? items : synced

        if let targetDuration, targetDuration > 0 {
            return pool.min { lhs, rhs in
                let dl = abs((lhs.duration ?? Double(targetDuration)) - Double(targetDuration))
                let dr = abs((rhs.duration ?? Double(targetDuration)) - Double(targetDuration))
                return dl < dr
            }
        }
        return pool.first
    }

    private func cleanTitle(_ title: String) -> String {
        let patterns = [
            #"\s*\(.*?(official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit).*?\)"#,
            #"\s*\[.*?(official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit).*?\]"#,
            #"\s*\(feat\..*?\)"#,
            #"\s*\(ft\..*?\)"#,
            #"\s*feat\..*$"#,
            #"\s*ft\..*$"#
        ]
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanArtist(_ artist: String) -> String {
        let separators = [" & ", " and ", ", ", " x ", " X ", " feat. ", " feat ", " ft. ", " ft ", " featuring ", " with "]
        var result = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in separators {
            if let range = result.range(of: sep, options: .caseInsensitive) {
                result = String(result[..<range.lowerBound])
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parseLRC(_ lrc: String) -> [LyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lines: [LyricLine] = []
        var index = 0

        for rawLine in lrc.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let match = regex.firstMatch(in: rawLine, options: [], range: range) else { continue }

            let minStr = nsLine.substring(with: match.range(at: 1))
            let secStr = nsLine.substring(with: match.range(at: 2))
            let fracRange = match.range(at: 3)
            let textStr = nsLine.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)

            let minutes = Double(minStr) ?? 0
            let seconds = Double(secStr) ?? 0
            var fraction = 0.0
            if fracRange.location != NSNotFound {
                let fracStr = nsLine.substring(with: fracRange)
                let divisor = pow(10.0, Double(fracStr.count))
                fraction = (Double(fracStr) ?? 0) / divisor
            }

            let time = minutes * 60.0 + seconds + fraction
            if !textStr.isEmpty {
                lines.append(LyricLine(id: index, time: time, text: textStr))
                index += 1
            }
        }

        return lines.sorted { $0.time < $1.time }
    }
}
