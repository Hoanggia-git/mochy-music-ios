import Foundation

/// LRC Red lyrics provider (`https://lrc.red/search.json` + `https://lrc.red/s/{isrc}.ttml`).
final class LrcRedLyricsService {
    static let shared = LrcRedLyricsService()

    private let baseURL = "https://lrc.red"
    private let userAgent = "Mochy (+https://github.com/realidkroo/Mochy-Music)"
    private let session: URLSession

    private struct SearchResponseDTO: Decodable {
        let hits: [HitDTO]?
    }

    private struct HitDTO: Decodable {
        let isrc: String?
        let title: String?
        let artist: String?
        let duration: Double?
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    func fetchLyrics(
        title: String,
        artist: String,
        durationSeconds: Int? = nil
    ) async throws -> LyricsResult? {
        let cleanedTitle = LrcLibService.cleanTitle(title)
        let cleanedArtist = LrcLibService.cleanArtist(artist)

        var matchedISRC = await findBestISRC(
            query: "\(cleanedTitle) \(cleanedArtist)".trimmingCharacters(in: .whitespaces),
            wantedTitle: cleanedTitle,
            wantedArtist: cleanedArtist,
            durationSeconds: durationSeconds
        )

        if matchedISRC == nil {
            matchedISRC = await findBestISRC(
                query: cleanedTitle,
                wantedTitle: cleanedTitle,
                wantedArtist: cleanedArtist,
                durationSeconds: durationSeconds
            )
        }

        guard let isrc = matchedISRC,
              let ttmlURL = URL(string: "\(baseURL)/s/\(isrc).ttml") else {
            return nil
        }

        var request = URLRequest(url: ttmlURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let ttml = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = LrcRedTTMLParser.parse(ttml)
        guard !lines.isEmpty else { return nil }

        return LyricsResult(
            syncedLines: lines,
            plainText: lines.map(\.text).joined(separator: "\n"),
            source: LyricsProvider.lrcRed.displayName
        )
    }

    private func findBestISRC(
        query: String,
        wantedTitle: String,
        wantedArtist: String,
        durationSeconds: Int?
    ) async -> String? {
        guard !query.isEmpty,
              var components = URLComponents(string: "\(baseURL)/search.json") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SearchResponseDTO.self, from: data),
              let hits = decoded.hits, !hits.isEmpty else {
            return nil
        }

        let normTitle = normalize(wantedTitle)
        let normArtist = normalize(wantedArtist)

        let scored = hits.compactMap { hit -> (String, Int)? in
            guard let isrc = hit.isrc, !isrc.isEmpty else { return nil }
            var score = 0
            let hTitle = normalize(hit.title ?? "")
            let hArtist = normalize(hit.artist ?? "")

            if hTitle == normTitle { score += 60 }
            else if hTitle.contains(normTitle) || normTitle.contains(hTitle) { score += 30 }
            else { return nil }

            if !normArtist.isEmpty && (hArtist == normArtist || hArtist.contains(normArtist) || normArtist.contains(hArtist)) {
                score += 40
            }

            if let durationSeconds, durationSeconds > 0, let hitDur = hit.duration {
                let diff = abs(Int(hitDur.rounded()) - durationSeconds)
                if diff <= 3 { score += 25 }
                else if diff <= 8 { score += 10 }
                else if diff > 20 { score -= 30 }
            }

            return score >= 50 ? (isrc, score) : nil
        }

        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class LrcRedTTMLParser: NSObject, XMLParserDelegate {
    private var lines: [LyricLine] = []
    private var inParagraph = false
    private var currentBegin: TimeInterval?
    private var currentText = ""
    private var skipNestedRole = false

    static func parse(_ ttml: String) -> [LyricLine] {
        guard let data = ttml.data(using: .utf8) else { return [] }
        let delegate = LrcRedTTMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.lines.sorted { $0.time < $1.time }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        if localName == "p", let begin = attributeDict["begin"], !begin.isEmpty {
            inParagraph = true
            currentBegin = Self.parseTime(begin)
            currentText = ""
            skipNestedRole = false
        } else if inParagraph && localName == "span" {
            let role = attributeDict["ttm:role"] ?? attributeDict["role"] ?? ""
            if role == "x-translation" || role == "x-roman" {
                skipNestedRole = true
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inParagraph, !skipNestedRole else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        if localName == "span" {
            skipNestedRole = false
        } else if localName == "p", inParagraph {
            let cleaned = currentText
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let time = currentBegin, !cleaned.isEmpty {
                lines.append(LyricLine(time: time, text: cleaned))
            }
            inParagraph = false
            currentBegin = nil
            currentText = ""
        }
    }

    private static func parseTime(_ str: String) -> TimeInterval {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("ms"), let val = Double(trimmed.dropLast(2)) { return val / 1000.0 }
        if trimmed.hasSuffix("s"), let val = Double(trimmed.dropLast(1)) { return val }
        let parts = trimmed.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 2: return parts[0] * 60.0 + parts[1]
        case 3: return parts[0] * 3600.0 + parts[1] * 60.0 + parts[2]
        default: return Double(trimmed) ?? 0
        }
    }
}
