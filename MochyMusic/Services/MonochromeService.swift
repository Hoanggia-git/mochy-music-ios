import Foundation

struct MonochromeServer: Identifiable, Codable, Hashable {
    let id: String
    let url: String
    let kind: String // "Streamer" or "Relay"
    let name: String
    let builtIn: Bool
}

enum MonochromeError: LocalizedError {
    case offlineMode
    case notFound
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .offlineMode:
            return "Offline mode is enabled."
        case .notFound:
            return "Track not found on Monochrome."
        case .unavailable(let reason):
            return reason
        }
    }
}

/// Lossless FLAC resolver using Monochrome streamer and relay servers.
@MainActor
final class MonochromeService: ObservableObject {
    static let shared = MonochromeService()

    static let builtInServer = MonochromeServer(
        id: "https://tracks.monochrome.st",
        url: "https://tracks.monochrome.st",
        kind: "Streamer",
        name: "tracks.monochrome.st",
        builtIn: true
    )

    @Published private(set) var servers: [MonochromeServer] = []

    private struct CatalogCandidate {
        let id: String
        let title: String
        let artist: String
        let album: String?
        let durationMs: Int64?
        let isrc: String?
    }

    private struct FlacStreamInfo {
        let bitsPerSample: Int
        let sampleRate: Int

        var isHiRes: Bool {
            bitsPerSample > 16 || sampleRate > 48_000
        }

        var shortLabel: String {
            isHiRes ? "Hi-Res FLAC" : "FLAC"
        }

        var badgeText: String {
            let rateText = sampleRate % 1000 == 0
                ? "\(sampleRate / 1000)"
                : String(format: "%.1f", Double(sampleRate) / 1000.0)
            return "\(shortLabel) · \(bitsPerSample)-bit / \(rateText) kHz"
        }
    }

    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    private let session: URLSession
    private var matchCache: [String: CatalogCandidate] = [:]
    private var missCache: [String: Date] = [:]
    private let missTTL: TimeInterval = 30 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: config)
        reloadServers()
    }

    func reloadServers() {
        let custom = loadCustomServers()
        // Custom servers are tried before the built-in default
        servers = custom + [Self.builtInServer]
    }

    // MARK: - Search & Resolve

    func searchTracks(query: String) async throws -> [Track] {
        if AppSettings.shared.offlineMode {
            throw MonochromeError.offlineMode
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        for server in servers {
            if let candidates = try? await searchServer(server, query: trimmed, limit: 10), !candidates.isEmpty {
                return candidates.map { item in
                    let artists = item.artist
                        .split(separator: ",")
                        .map { Artist(name: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .filter { !$0.name.isEmpty }
                    let album = item.album.map { Album(id: "mono_\($0)", name: $0, artists: artists) }
                    return Track(
                        id: "monochrome_\(item.id)",
                        title: item.title,
                        artists: artists,
                        album: album,
                        durationSeconds: item.durationMs.map { Int($0 / 1000) }
                    )
                }
            }
        }
        return []
    }

    func resolveStream(for track: Track) async throws -> ResolvedStream {
        if AppSettings.shared.offlineMode {
            throw MonochromeError.offlineMode
        }

        var lastError: Error = MonochromeError.notFound

        for server in servers {
            let cacheKey = "\(server.url)|\(track.title.lowercased())|\(track.artistsText.lowercased())"
            if let missedAt = missCache[cacheKey], Date().timeIntervalSince(missedAt) < missTTL {
                continue
            }

            do {
                let candidate: CatalogCandidate
                if let cached = matchCache[cacheKey] {
                    candidate = cached
                } else {
                    let leadArtist = track.artists.first?.name ?? ""
                    let coreTitle = cleanCoreTitle(track.title)
                    let query = [leadArtist, coreTitle].filter { !$0.isEmpty }.joined(separator: " ")
                    let results = try await searchServer(server, query: query, limit: 8)
                    guard let best = selectBestCandidate(for: track, from: results) else {
                        missCache[cacheKey] = Date()
                        continue
                    }
                    matchCache[cacheKey] = best
                    candidate = best
                }

                if let opened = await openStreamHead(server: server, trackId: candidate.id),
                   let info = parseFlacInfo(from: opened.head) {
                    let estimatedBitrate = info.sampleRate * info.bitsPerSample * 2 / 2
                    return ResolvedStream(
                        url: opened.url,
                        userAgent: userAgent,
                        isAudioOnly: true,
                        itag: 0,
                        mimeType: "audio/flac",
                        codecs: "flac",
                        bitrate: estimatedBitrate,
                        sampleRate: info.sampleRate,
                        contentLength: 0,
                        loudnessDb: nil,
                        sourceLabel: "Monochrome",
                        qualityBadgeText: info.badgeText
                    )
                }
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    // MARK: - Server Management

    func addServer(urlString: String) async -> String? {
        guard let (base, origin) = normalizeURLParts(urlString) else {
            return "Invalid server URL."
        }

        let candidates = base == origin ? [base] : [base, origin]
        var detected: MonochromeServer?

        for candidate in candidates {
            if let found = await identifyServer(base: candidate) {
                detected = found
                break
            }
        }

        if detected == nil, let siteServer = await discoverServerFromSite(origin: origin) {
            detected = siteServer
        }

        guard let server = detected else {
            return "Could not find a compatible Monochrome streamer or relay at that URL."
        }

        if servers.contains(where: { $0.url.caseInsensitiveCompare(server.url) == .orderedSame }) {
            return "This server is already in your list."
        }

        var custom = loadCustomServers()
        custom.append(server)
        saveCustomServers(custom)
        reloadServers()
        return nil
    }

    func removeServer(url: String) {
        let custom = loadCustomServers().filter { $0.url != url }
        saveCustomServers(custom)
        reloadServers()
        matchCache = matchCache.filter { !$0.key.hasPrefix("\(url)|") }
        missCache = missCache.filter { !$0.key.hasPrefix("\(url)|") }
    }

    func testServers() async -> String {
        var reachableCount = 0
        for server in servers {
            if let results = try? await searchServer(server, query: "test", limit: 1), !results.isEmpty {
                reachableCount += 1
            } else if await pingServer(server) {
                reachableCount += 1
            }
        }
        if reachableCount == 0 {
            return "0 of \(servers.count) Monochrome servers reachable"
        }
        return "\(reachableCount) of \(servers.count) servers reachable"
    }

    // MARK: - Networking & Parsing

    private func pingServer(_ server: MonochromeServer) async -> Bool {
        guard let request = buildSearchRequest(server: server, query: "test", limit: 1) else { return false }
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    private func searchServer(_ server: MonochromeServer, query: String, limit: Int) async throws -> [CatalogCandidate] {
        guard let request = buildSearchRequest(server: server, query: query, limit: limit) else {
            throw MonochromeError.unavailable("Invalid Monochrome search URL")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MonochromeError.unavailable("\(server.name) answered HTTP \(code)")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if server.kind == "Relay" {
            let rows = root["data"] as? [[String: Any]] ?? []
            return rows.compactMap { row in
                guard let id = stringValue(row["id"]),
                      let title = stringValue(row["title"]) else { return nil }
                let artistRaw = stringValue(row["artist"]) ?? ""
                let artist = artistRaw
                    .replacingOccurrences(of: #"(?<! )&(?! )"#, with: ", ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let album = stringValue(row["album"])
                let durationMs = parseDurationMs(row["duration"])
                return CatalogCandidate(
                    id: id,
                    title: title,
                    artist: artist,
                    album: album,
                    durationMs: durationMs,
                    isrc: stringValue(row["isrc"])
                )
            }
        } else {
            let tracks = root["tracks"] as? [[String: Any]] ?? []
            return tracks.compactMap { item in
                if let playable = item["playable"] as? Bool, !playable { return nil }
                guard let id = stringValue(item["trackId"]) ?? stringValue(item["id"]),
                      let title = stringValue(item["title"]) else { return nil }
                let artistNames = item["artistNames"] as? [String] ?? []
                let album = stringValue(item["albumTitle"]) ?? stringValue(item["releaseTitle"])
                let durationMs = parseDurationMs(item["duration"])
                return CatalogCandidate(
                    id: id,
                    title: title,
                    artist: artistNames.joined(separator: ", "),
                    album: album,
                    durationMs: durationMs,
                    isrc: stringValue(item["isrc"])
                )
            }
        }
    }

    private func buildSearchRequest(server: MonochromeServer, query: String, limit: Int) -> URLRequest? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString: String
        if server.kind == "Relay" {
            urlString = "\(server.url)/search?q=\(encoded)&n=\(limit)"
        } else {
            urlString = "\(server.url)/search/tracks?q=\(encoded)&limit=\(limit)"
        }
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if server.kind == "Relay" {
            request.setValue("relay/2", forHTTPHeaderField: "X-Relay-Client")
        }
        return request
    }

    private func openStreamHead(server: MonochromeServer, trackId: String) async -> (url: URL, head: Data)? {
        if server.kind == "Relay" {
            let encodedId = trackId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trackId
            guard let reqURL = URL(string: "\(server.url)/s/\(encodedId)?q=flac") else { return nil }
            var request = URLRequest(url: reqURL)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("relay/2", forHTTPHeaderField: "X-Relay-Client")
            request.setValue("bytes=0-41", forHTTPHeaderField: "Range")

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let relayLink = http.value(forHTTPHeaderField: "X-Relay-Stream"),
                  let finalURL = URL(string: relayLink) else {
                return nil
            }
            return (finalURL, data)
        } else {
            guard let streamURL = URL(string: "\(server.url)/track/\(trackId)") else { return nil }
            var request = URLRequest(url: streamURL)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=0-41", forHTTPHeaderField: "Range")

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return nil
            }
            return (streamURL, data)
        }
    }

    private func parseFlacInfo(from data: Data) -> FlacStreamInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, String(bytes: bytes[0..<4], encoding: .ascii) == "fLaC" else {
            return nil
        }
        guard bytes.count >= 26 else {
            return FlacStreamInfo(bitsPerSample: 16, sampleRate: 44_100)
        }
        let b = Array(bytes[8..<26])
        let sampleRate = (Int(b[10]) << 12) | (Int(b[11]) << 4) | (Int(b[12]) >> 4)
        let bits = (((Int(b[12]) & 0x01) << 4) | (Int(b[13]) >> 4)) + 1
        if (8_000...768_000).contains(sampleRate) && (8...32).contains(bits) {
            return FlacStreamInfo(bitsPerSample: bits, sampleRate: sampleRate)
        }
        return FlacStreamInfo(bitsPerSample: 16, sampleRate: 44_100)
    }

    // MARK: - Track Matching & Server Discovery

    private func selectBestCandidate(for track: Track, from candidates: [CatalogCandidate]) -> CatalogCandidate? {
        guard !candidates.isEmpty else { return nil }
        let wantedTitle = normalize(cleanCoreTitle(track.title))
        let wantedArtist = normalize(track.artists.first?.name ?? track.artistsText)

        var best: (candidate: CatalogCandidate, score: Int)?
        for item in candidates {
            var score = 0
            let candTitle = normalize(cleanCoreTitle(item.title))
            let candArtist = normalize(item.artist)

            if candTitle == wantedTitle {
                score += 60
            } else if candTitle.contains(wantedTitle) || wantedTitle.contains(candTitle) {
                score += 30
            } else {
                continue
            }

            if !wantedArtist.isEmpty {
                if candArtist == wantedArtist || candArtist.contains(wantedArtist) || wantedArtist.contains(candArtist) {
                    score += 40
                } else {
                    score -= 10
                }
            }

            if let targetSec = track.durationSeconds, targetSec > 0, let durMs = item.durationMs {
                let diff = abs(Int(durMs / 1000) - targetSec)
                if diff <= 3 { score += 25 }
                else if diff <= 8 { score += 10 }
                else if diff > 20 { score -= 30 }
            }

            if score >= 50 && (best == nil || score > best!.score) {
                best = (item, score)
            }
        }
        return best?.candidate
    }

    private func identifyServer(base: String) async -> MonochromeServer? {
        let host = URL(string: base)?.host ?? base
        for kind in ["Streamer", "Relay"] {
            let probe = MonochromeServer(id: base, url: base, kind: kind, name: host, builtIn: false)
            guard let request = buildSearchRequest(server: probe, query: "test", limit: 1),
                  let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if (kind == "Streamer" && json["tracks"] is [[String: Any]]) ||
               (kind == "Relay" && json["data"] is [[String: Any]]) {
                return probe
            }
        }
        return nil
    }

    private func discoverServerFromSite(origin: String) async -> MonochromeServer? {
        guard let url = URL(string: origin) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        let scriptRegex = try? NSRegularExpression(pattern: #"<script[^>]+src=["']([^"']+)["']"#, options: [.caseInsensitive])
        let linkRegex = try? NSRegularExpression(pattern: #"https://[a-z0-9-]+(?:\.[a-z0-9-]+)+"#, options: [.caseInsensitive])

        let nsHTML = html as NSString
        let matches = scriptRegex?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []
        for match in matches.prefix(4) {
            let src = nsHTML.substring(with: match.range(at: 1))
            guard let scriptURL = URL(string: src, relativeTo: url)?.absoluteURL,
                  scriptURL.absoluteString.hasPrefix(origin) else { continue }

            var sReq = URLRequest(url: scriptURL)
            sReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            guard let (sData, _) = try? await session.data(for: sReq),
                  let scriptText = String(data: sData, encoding: .utf8) else { continue }

            let nsScript = scriptText as NSString
            let linkMatches = linkRegex?.matches(in: scriptText, range: NSRange(location: 0, length: nsScript.length)) ?? []
            for lMatch in linkMatches.prefix(8) {
                let candidate = nsScript.substring(with: lMatch.range)
                let host = URL(string: candidate)?.host ?? ""
                if host.hasPrefix("tracks.") || host.contains("relay") {
                    if let found = await identifyServer(base: candidate) {
                        return MonochromeServer(
                            id: found.url,
                            url: found.url,
                            kind: found.kind,
                            name: URL(string: origin)?.host ?? found.name,
                            builtIn: false
                        )
                    }
                }
            }
        }
        return nil
    }

    private func normalizeURLParts(_ raw: String) -> (base: String, origin: String)? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "%20")
        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme,
              (scheme == "https" || scheme == "http"),
              let host = components.host, !host.isEmpty else {
            return nil
        }
        let portPart = components.port.map { ":\($0)" } ?? ""
        let origin = "\(scheme)://\(host)\(portPart)"
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = path.isEmpty ? origin : "\(origin)/\(path)"
        return (base, origin)
    }

    // MARK: - Persistence & Helpers

    private func loadCustomServers() -> [MonochromeServer] {
        let raw = AppSettings.shared.monochromeCustomServersJSON
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MonochromeServer].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveCustomServers(_ custom: [MonochromeServer]) {
        if let data = try? JSONEncoder().encode(custom),
           let json = String(data: data, encoding: .utf8) {
            AppSettings.shared.monochromeCustomServersJSON = json
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? Int { return String(n) }
        if let n = value as? Int64 { return String(n) }
        return nil
    }

    private func parseDurationMs(_ value: Any?) -> Int64? {
        let raw: Int64?
        if let n = value as? Int64 { raw = n }
        else if let n = value as? Int { raw = Int64(n) }
        else if let s = value as? String { raw = Int64(s) }
        else { raw = nil }
        guard let raw, raw > 0 else { return nil }
        return raw > 10_000 ? raw : raw * 1000
    }

    private func cleanCoreTitle(_ title: String) -> String {
        LrcLibService.cleanTitle(title)
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
