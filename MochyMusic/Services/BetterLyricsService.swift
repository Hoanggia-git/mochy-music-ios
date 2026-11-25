import Foundation

/// Better Lyrics API provider (https://lyrics-api.boidu.dev/getLyrics) with TTML parsing and YouTube videoId caption fallback.
final class BetterLyricsService {
    static let shared = BetterLyricsService()

    private let baseURL = "https://lyrics-api.boidu.dev/getLyrics"
    private let userAgent = "Mochy (+https://github.com/realidkroo/Mochy-Music)"
    private let session: URLSession

    private struct TTMLResponseDTO: Decodable {
        let ttml: String?
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func fetchLyrics(
        videoId: String? = nil,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int? = nil
    ) async throws -> LyricsResult? {
        let cleanedTitle = LrcLibService.cleanTitle(title)
        let cleanedArtist = LrcLibService.cleanArtist(artist)

        if let ttml = await fetchTTML(title: cleanedTitle, artist: cleanedArtist, album: album, durationSeconds: durationSeconds) {
            let lines = TTMLXMLParser.parse(ttml)
            if !lines.isEmpty {
                let plain = lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
                return LyricsResult(
                    syncedLines: lines,
                    plainText: plain.isEmpty ? nil : plain,
                    source: LyricsProvider.betterLyrics.displayName
                )
            }
        }

        // Fallback: videoId-scoped YouTube timed captions / transcript when available
        if let videoId, !videoId.isEmpty {
            if let captionsLRC = try? await InnerTubeService.shared.fetchYouTubeCaptionsLRC(videoId: videoId) {
                let parsed = LrcLibService.parseLRC(captionsLRC)
                if !parsed.isEmpty {
                    return LyricsResult(
                        syncedLines: parsed,
                        plainText: parsed.map(\.text).joined(separator: "\n"),
                        source: LyricsProvider.betterLyrics.displayName
                    )
                }
            }
        }

        return nil
    }

    func fetchLyrics(videoId: String) async throws -> LyricsResult? {
        if let captionsLRC = try? await InnerTubeService.shared.fetchYouTubeCaptionsLRC(videoId: videoId) {
            let parsed = LrcLibService.parseLRC(captionsLRC)
            if !parsed.isEmpty {
                return LyricsResult(
                    syncedLines: parsed,
                    plainText: parsed.map(\.text).joined(separator: "\n"),
                    source: LyricsProvider.betterLyrics.displayName
                )
            }
        }
        return nil
    }

    private func fetchTTML(
        title: String,
        artist: String,
        album: String?,
        durationSeconds: Int?
    ) async -> String? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        var queryItems = [
            URLQueryItem(name: "s", value: title),
            URLQueryItem(name: "a", value: artist)
        ]
        if let durationSeconds, durationSeconds > 0 {
            queryItems.append(URLQueryItem(name: "d", value: String(durationSeconds)))
        }
        if let album, !album.isEmpty {
            queryItems.append(URLQueryItem(name: "al", value: album))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(TTMLResponseDTO.self, from: data)
            return decoded.ttml
        } catch {
            return nil
        }
    }
}

// MARK: - TTML XML Parser

private final class TTMLXMLParser: NSObject, XMLParserDelegate {
    private var lines: [LyricLine] = []
    private var inParagraph = false
    private var currentBegin: TimeInterval?
    private var currentText = ""
    private var skipNestedRole = false

    static func parse(_ ttml: String) -> [LyricLine] {
        guard let data = ttml.data(using: .utf8) else { return [] }
        let parserDelegate = TTMLXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parserDelegate
        xmlParser.shouldProcessNamespaces = false
        xmlParser.parse()
        return parserDelegate.lines.sorted { $0.time < $1.time }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        if localName == "p" {
            if let begin = attributeDict["begin"], !begin.isEmpty {
                inParagraph = true
                currentBegin = Self.parseTTMLTime(begin)
                currentText = ""
                skipNestedRole = false
            }
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

    private static func parseTTMLTime(_ str: String) -> TimeInterval {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("ms"), let val = Double(trimmed.dropLast(2)) {
            return val / 1000.0
        }
        if trimmed.hasSuffix("s"), let val = Double(trimmed.dropLast(1)) {
            return val
        }
        let parts = trimmed.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 2:
            return parts[0] * 60.0 + parts[1]
        case 3:
            return parts[0] * 3600.0 + parts[1] * 60.0 + parts[2]
        default:
            return Double(trimmed) ?? 0
        }
    }
}
