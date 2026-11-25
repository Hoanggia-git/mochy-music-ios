import Foundation

/// Genius lyrics provider using Genius's public web API (`genius.com/api`) and HTML lyrics extraction.
final class GeniusLyricsService {
    static let shared = GeniusLyricsService()

    private let apiBase = "https://genius.com/api"
    private let userAgent = "Mochy (https://github.com/realidkroo/Mochy-Music)"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    func fetchLyrics(title: String, artist: String) async throws -> LyricsResult? {
        let cleanedTitle = LrcLibService.cleanTitle(title)
        let leadArtist = LrcLibService.cleanArtist(artist)
        let query = [leadArtist, cleanedTitle].filter { !$0.isEmpty }.joined(separator: " ")

        guard var components = URLComponents(string: "\(apiBase)/search/multi") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "5"),
            URLQueryItem(name: "q", value: query)
        ]
        guard let searchURL = components.url,
              let searchJSON = await getJSON(url: searchURL),
              let sections = (searchJSON["response"] as? [String: Any])?["sections"] as? [[String: Any]] else {
            return nil
        }

        let hits = sections
            .filter { ($0["type"] as? String) == "song" }
            .flatMap { $0["hits"] as? [[String: Any]] ?? [] }
            .compactMap { $0["result"] as? [String: Any] }

        let best = hits
            .map { ($0, score(result: $0, wantedTitle: cleanedTitle, wantedArtist: leadArtist)) }
            .filter { $0.1 >= 60 }
            .max(by: { $0.1 < $1.1 })?
            .0

        guard let best else { return nil }
        let pageURLString = best["url"] as? String

        var extractedLyrics: String?
        if let pageURLString, let pageURL = URL(string: pageURLString) {
            extractedLyrics = await fetchAndParseLyricsPage(url: pageURL)
        }

        // Fallback to Genius song metadata description if scraping was blocked
        if extractedLyrics == nil, let songId = best["id"] as? Int,
           let detailURL = URL(string: "\(apiBase)/songs/\(songId)?text_format=plain"),
           let detailJSON = await getJSON(url: detailURL),
           let songDict = (detailJSON["response"] as? [String: Any])?["song"] as? [String: Any],
           let songURLString = songDict["url"] as? String,
           let songURL = URL(string: songURLString),
           songURLString != pageURLString {
            extractedLyrics = await fetchAndParseLyricsPage(url: songURL)
        }

        guard let lyrics = extractedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lyrics.isEmpty else {
            return nil
        }

        return LyricsResult(
            syncedLines: nil,
            plainText: lyrics,
            source: LyricsProvider.genius.displayName
        )
    }

    // MARK: - Scoring

    private func score(result: [String: Any], wantedTitle: String, wantedArtist: String) -> Int {
        let primaryArtist = (result["primary_artist"] as? [String: Any])?["name"] as? String ?? ""
        if primaryArtist.hasPrefix("Genius ") { return 0 }

        let wanted = normalize(wantedTitle)
        let shown = result["title"] as? String ?? ""
        let parentPart = shown.components(separatedBy: "(").first ?? shown
        let insideParen: String = {
            guard let open = shown.firstIndex(of: "("),
                  let close = shown.lastIndex(of: ")"),
                  open < close else { return "" }
            return String(shown[shown.index(after: open)..<close])
        }()

        let titleVariants = [shown, parentPart, insideParen].map(normalize).filter { !$0.isEmpty }
        var totalScore = 0
        if titleVariants.contains(wanted) {
            totalScore += 80
        } else if titleVariants.contains(where: { $0.contains(wanted) || wanted.contains($0) }) {
            totalScore += 40
        }

        let artistCandidates = [
            primaryArtist,
            primaryArtist.components(separatedBy: "(").first ?? "",
            result["artist_names"] as? String ?? ""
        ].map(normalize)
        let normWantedArtist = normalize(wantedArtist)
        if !normWantedArtist.isEmpty,
           artistCandidates.contains(where: { !$0.isEmpty && ($0 == normWantedArtist || $0.contains(normWantedArtist)) }) {
            totalScore += 40
        }

        return totalScore
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Networking & HTML Parsing

    private func getJSON(url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func fetchAndParseLyricsPage(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            return extractLyricsFromHTML(html)
        } catch {
            return nil
        }
    }

    private func extractLyricsFromHTML(_ html: String) -> String? {
        // Genius renders lyrics in one or more `<div data-lyrics-container="true" ...>...</div>` blocks
        let pattern = #"<div[^>]*data-lyrics-container="true"[^>]*>([\s\S]*?)</div>(?=\s*<div|\s*</div|\s*<script)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)

        var blocks: [String] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: html) {
                let rawBlock = String(html[range])
                let cleaned = htmlToPlainText(rawBlock)
                if !cleaned.isEmpty {
                    blocks.append(cleaned)
                }
            }
        }

        if blocks.isEmpty {
            // Fallback for older Genius markup
            let legacyPattern = #"<div class="lyrics">([\s\S]*?)</div>"#
            if let legacyRegex = try? NSRegularExpression(pattern: legacyPattern, options: [.caseInsensitive]),
               let match = legacyRegex.firstMatch(in: html, options: [], range: nsRange),
               let range = Range(match.range(at: 1), in: html) {
                let cleaned = htmlToPlainText(String(html[range]))
                return cleaned.isEmpty ? nil : cleaned
            }
            return nil
        }

        return blocks.joined(separator: "\n")
    }

    private func htmlToPlainText(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<div[^>]*data-exclude-from-selection="true"[^>]*>[\s\S]*?</div>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        let entities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&#x27;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
