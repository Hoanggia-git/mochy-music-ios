import Foundation

/// Paxsenix lyrics provider (`https://lyrics.paxsenix.org/apple-music/search` & `/apple-music/lyrics`).
final class PaxsenixLyricsService {
    static let shared = PaxsenixLyricsService()

    private let baseURL = "https://lyrics.paxsenix.org"
    private let session: URLSession

    private struct SearchResultDTO: Decodable {
        let id: String
        let name: String?
        let songName: String?
        let artistName: String?
        let duration: Int?
    }

    private struct LyricsResponseDTO: Decodable {
        let type: String?
        let ttmlContent: String?
        let elrcMultiPerson: String?
        let elrc: String?
        let content: [LyricLineDTO]?
    }

    private struct LyricLineDTO: Decodable {
        let timestamp: Int64?
        let text: [LyricPieceDTO]?
    }

    private struct LyricPieceDTO: Decodable {
        let text: String?
        let part: Bool?
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        self.session = URLSession(configuration: config)
    }

    func fetchLyrics(
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int? = nil
    ) async throws -> LyricsResult? {
        let cleanedTitle = LrcLibService.cleanTitle(title)
        let cleanedArtist = LrcLibService.cleanArtist(artist)

        var queries = [
            "\(cleanedTitle) \(cleanedArtist)".trimmingCharacters(in: .whitespaces),
            cleanedTitle
        ]
        if let album, !album.isEmpty {
            queries.append("\(cleanedTitle) \(cleanedArtist) \(album)")
        }

        var scoredCandidates: [SearchResultDTO] = []
        for query in queries where !query.isEmpty {
            let results = await search(query: query)
            if !results.isEmpty {
                scoredCandidates = rankResults(results, title: title, artist: artist, durationSeconds: durationSeconds)
                if !scoredCandidates.isEmpty { break }
            }
        }

        for candidate in scoredCandidates.prefix(3) {
            if let result = await fetchLyricsForTrack(id: candidate.id) {
                return result
            }
        }

        return nil
    }

    // MARK: - Search & Fetch

    private func search(query: String) async -> [SearchResultDTO] {
        guard var components = URLComponents(string: "\(baseURL)/apple-music/search") else { return [] }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mochy/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            return (try? JSONDecoder().decode([SearchResultDTO].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    private func fetchLyricsForTrack(id: String) async -> LyricsResult? {
        guard var components = URLComponents(string: "\(baseURL)/apple-music/lyrics") else { return nil }
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mochy/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let dto = try? JSONDecoder().decode(LyricsResponseDTO.self, from: data) else {
                return nil
            }

            if let ttml = dto.ttmlContent, !ttml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lines = PaxsenixTTMLParser.parse(ttml)
                if !lines.isEmpty {
                    return LyricsResult(
                        syncedLines: lines,
                        plainText: lines.map(\.text).joined(separator: "\n"),
                        source: LyricsProvider.paxsenix.displayName
                    )
                }
            }

            if let elrc = (dto.elrcMultiPerson ?? dto.elrc)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !elrc.isEmpty {
                let lines = LrcLibService.parseLRC(elrc)
                if !lines.isEmpty {
                    return LyricsResult(
                        syncedLines: lines,
                        plainText: lines.map(\.text).joined(separator: "\n"),
                        source: LyricsProvider.paxsenix.displayName
                    )
                }
            }

            if let content = dto.content, !content.isEmpty {
                let isPlainOnly = dto.type?.caseInsensitiveCompare("Lyrics") == .orderedSame
                var syncedLines: [LyricLine] = []
                var plainLines: [String] = []

                for entry in content {
                    let lineText = joinPieces(entry.text ?? [])
                    guard !lineText.isEmpty else { continue }
                    plainLines.append(lineText)
                    if !isPlainOnly, let ts = entry.timestamp {
                        syncedLines.append(LyricLine(time: Double(ts) / 1000.0, text: lineText))
                    }
                }

                if !syncedLines.isEmpty {
                    return LyricsResult(
                        syncedLines: syncedLines,
                        plainText: plainLines.joined(separator: "\n"),
                        source: LyricsProvider.paxsenix.displayName
                    )
                }
                if !plainLines.isEmpty {
                    return LyricsResult(
                        syncedLines: nil,
                        plainText: plainLines.joined(separator: "\n"),
                        source: LyricsProvider.paxsenix.displayName
                    )
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func rankResults(
        _ results: [SearchResultDTO],
        title: String,
        artist: String,
        durationSeconds: Int?
    ) -> [SearchResultDTO] {
        let cleanedTitle = LrcLibService.cleanTitle(title).lowercased()
        let cleanedArtist = LrcLibService.cleanArtist(artist).lowercased()
        let durationMs = durationSeconds.map { $0 * 1000 }

        return results.map { item -> (SearchResultDTO, Double) in
            var score = 0.0
            let displayTitle = (item.songName ?? item.name ?? "").lowercased()
            let displayArtist = (item.artistName ?? "").lowercased()

            if displayTitle == cleanedTitle { score += 80 }
            else if displayTitle.contains(cleanedTitle) || cleanedTitle.contains(displayTitle) { score += 40 }

            if !cleanedArtist.isEmpty && displayArtist.contains(cleanedArtist) { score += 50 }

            if let durationMs, durationMs > 0, let itemDur = item.duration {
                let diff = abs(itemDur - durationMs)
                if diff <= 2000 { score += 100 }
                else if diff <= 5000 { score += 50 }
                else if diff <= 10000 { score += 10 }
                else { score -= 50 }
            }
            return (item, score)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    private func joinPieces(_ pieces: [LyricPieceDTO]) -> String {
        guard !pieces.isEmpty else { return "" }
        let spacedByAPI = pieces.dropLast().contains { ($0.text?.last?.isWhitespace) == true }
        var out = ""
        for (idx, piece) in pieces.enumerated() {
            let chunk = piece.text ?? ""
            out += chunk
            let isLast = idx == pieces.count - 1
            if !spacedByAPI && !isLast && piece.part != true && chunk.last?.isWhitespace != true {
                out += " "
            }
        }
        return out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class PaxsenixTTMLParser: NSObject, XMLParserDelegate {
    private var lines: [LyricLine] = []
    private var inParagraph = false
    private var currentBegin: TimeInterval?
    private var currentText = ""
    private var skipNestedRole = false

    static func parse(_ ttml: String) -> [LyricLine] {
        guard let data = ttml.data(using: .utf8) else { return [] }
        let delegate = PaxsenixTTMLParser()
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
