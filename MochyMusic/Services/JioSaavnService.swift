import Foundation
import CommonCrypto

enum JioSaavnError: LocalizedError {
    case offlineMode
    case notFound
    case decryptionFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .offlineMode:
            return "Offline mode is enabled."
        case .notFound:
            return "Track not found on JioSaavn."
        case .decryptionFailed:
            return "Failed to decrypt JioSaavn media URL."
        case .networkError(let reason):
            return reason
        }
    }
}

/// JioSaavn AAC stream resolver with CommonCrypto DES/ECB/PKCS7 decryption.
@MainActor
final class JioSaavnService: ObservableObject {
    static let shared = JioSaavnService()

    private let apiBase = "https://www.jiosaavn.com/api.php"
    private let desKey = "38346591"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    private let session: URLSession

    private struct SaavnCandidate {
        let id: String
        let title: String
        let artist: String
        let album: String?
        let durationSeconds: Int?
        let encryptedMediaURL: String
        let has320kbps: Bool
    }

    private var matchCache: [String: SaavnCandidate] = [:]
    private var missCache: [String: Date] = [:]
    private let missTTL: TimeInterval = 30 * 60

    private static let renditionRegex = try? NSRegularExpression(
        pattern: #"_(12|48|96|160|320)\.(mp4|m4a|aac|mp3)(?=[?#]|$)"#,
        options: [.caseInsensitive]
    )

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func testConnection() async -> String {
        do {
            _ = try await searchSongs(query: "test", count: 1)
            return "Connected · JioSaavn API reachable"
        } catch {
            return "Unavailable: \(error.localizedDescription)"
        }
    }

    func resolveStream(
        for track: Track,
        quality: String = AppSettings.shared.jiosaavnQuality
    ) async throws -> ResolvedStream {
        if AppSettings.shared.offlineMode {
            throw JioSaavnError.offlineMode
        }

        let cacheKey = "\(track.title.lowercased())|\(track.artistsText.lowercased())"
        if let missedAt = missCache[cacheKey], Date().timeIntervalSince(missedAt) < missTTL {
            throw JioSaavnError.notFound
        }

        let candidate: SaavnCandidate
        if let cached = matchCache[cacheKey] {
            candidate = cached
        } else {
            let leadArtist = track.artists.first?.name ?? ""
            let coreTitle = LrcLibService.cleanTitle(track.title)
            let query = [coreTitle, leadArtist].filter { !$0.isEmpty }.joined(separator: " ")
            let results = try await searchSongs(query: query, count: 10)
            guard let best = selectBestCandidate(for: track, from: results) else {
                missCache[cacheKey] = Date()
                throw JioSaavnError.notFound
            }
            matchCache[cacheKey] = best
            candidate = best
        }

        guard let decryptedString = decryptMediaURL(candidate.encryptedMediaURL) else {
            throw JioSaavnError.decryptionFailed
        }

        let requestedKbps = Int(quality) ?? 320
        let targetKbps = (requestedKbps == 320 && !candidate.has320kbps) ? 160 : requestedKbps
        let (finalURL, resolvedKbps) = await resolveRenditionURL(given: decryptedString, targetKbps: targetKbps)

        let ext = finalURL.pathExtension.lowercased()
        let mime = ext == "mp3" ? "audio/mpeg" : "audio/mp4"
        let codecs = ext == "mp3" ? "mp3" : "mp4a.40.2"
        let displayKbps = resolvedKbps ?? targetKbps

        return ResolvedStream(
            url: finalURL,
            userAgent: userAgent,
            isAudioOnly: true,
            itag: 0,
            mimeType: mime,
            codecs: codecs,
            bitrate: displayKbps * 1000,
            sampleRate: 44100,
            contentLength: 0,
            loudnessDb: nil,
            sourceLabel: "JioSaavn",
            qualityBadgeText: "AAC · \(displayKbps) kbps"
        )
    }

    // MARK: - Search

    private func searchSongs(query: String, count: Int) async throws -> [SaavnCandidate] {
        guard var components = URLComponents(string: apiBase) else {
            throw JioSaavnError.networkError("Invalid JioSaavn URL")
        }
        components.queryItems = [
            URLQueryItem(name: "__call", value: "search.getResults"),
            URLQueryItem(name: "_format", value: "json"),
            URLQueryItem(name: "_marker", value: "0"),
            URLQueryItem(name: "api_version", value: "4"),
            URLQueryItem(name: "ctx", value: "android"),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "n", value: String(count)),
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = components.url else {
            throw JioSaavnError.networkError("Invalid search query")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("explicit_content=1", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw JioSaavnError.networkError("JioSaavn answered HTTP \(code)")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { song in
            guard let id = song["id"] as? String,
                  let rawTitle = song["title"] as? String,
                  let moreInfo = song["more_info"] as? [String: Any],
                  let encrypted = moreInfo["encrypted_media_url"] as? String,
                  !encrypted.isEmpty else {
                return nil
            }

            let primaryArtists = ((moreInfo["artistMap"] as? [String: Any])?["primary_artists"] as? [[String: Any]] ?? [])
                .compactMap { ($0["name"] as? String).map(unescapeHTML) }

            let durationStr = moreInfo["duration"] as? String
            let durationSec = durationStr.flatMap(Int.init) ?? (moreInfo["duration"] as? Int)
            let has320 = (moreInfo["320kbps"] as? String)?.caseInsensitiveCompare("true") == .orderedSame
                || (moreInfo["320kbps"] as? Bool) == true

            return SaavnCandidate(
                id: id,
                title: unescapeHTML(rawTitle),
                artist: primaryArtists.joined(separator: ", "),
                album: (moreInfo["album"] as? String).map(unescapeHTML),
                durationSeconds: durationSec,
                encryptedMediaURL: encrypted,
                has320kbps: has320
            )
        }
    }

    // MARK: - DES Decryption (CommonCrypto)

    private func decryptMediaURL(_ encryptedBase64: String) -> String? {
        let trimmed = encryptedBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encryptedData = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              let keyData = desKey.data(using: .utf8),
              keyData.count == kCCKeySizeDES else {
            return nil
        }

        let bufferSize = encryptedData.count + kCCBlockSizeDES
        var decryptedBytes = [UInt8](repeating: 0, count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let status = encryptedData.withUnsafeBytes { dataPtr in
            keyData.withUnsafeBytes { keyPtr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmDES),
                    CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                    keyPtr.baseAddress,
                    kCCKeySizeDES,
                    nil,
                    dataPtr.baseAddress,
                    encryptedData.count,
                    &decryptedBytes,
                    bufferSize,
                    &numBytesDecrypted
                )
            }
        }

        guard status == kCCSuccess else { return nil }
        let outData = Data(decryptedBytes.prefix(numBytesDecrypted))
        guard let decrypted = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              decrypted.hasPrefix("http") else {
            return nil
        }
        return decrypted
    }

    private func resolveRenditionURL(given: String, targetKbps: Int) async -> (URL, Int?) {
        guard let givenURL = URL(string: given) else {
            return (URL(string: "https://www.jiosaavn.com")!, nil)
        }
        guard let regex = Self.renditionRegex else {
            return (givenURL, nil)
        }

        let nsRange = NSRange(given.startIndex..<given.endIndex, in: given)
        guard let match = regex.firstMatch(in: given, range: nsRange),
              let fullRange = Range(match.range, in: given),
              let kbpsRange = Range(match.range(at: 1), in: given),
              let extRange = Range(match.range(at: 2), in: given) else {
            return (givenURL, nil)
        }

        let offeredKbps = Int(given[kbpsRange])
        if offeredKbps == targetKbps {
            return (givenURL, offeredKbps)
        }

        let ext = String(given[extRange])
        var candidateStr = given
        candidateStr.replaceSubrange(fullRange, with: "_\(targetKbps).\(ext)")

        if let candidateURL = URL(string: candidateStr), await probeRangeByte(url: candidateURL) {
            return (candidateURL, targetKbps)
        }
        return (givenURL, offeredKbps)
    }

    private func probeRangeByte(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    // MARK: - Track Matching & Helpers

    private func selectBestCandidate(for track: Track, from candidates: [SaavnCandidate]) -> SaavnCandidate? {
        let wantedTitle = normalize(LrcLibService.cleanTitle(track.title))
        let wantedArtist = normalize(track.artists.first?.name ?? track.artistsText)

        var best: (candidate: SaavnCandidate, score: Int)?
        for item in candidates {
            var score = 0
            let candTitle = normalize(LrcLibService.cleanTitle(item.title))
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
                }
            }

            if let targetSec = track.durationSeconds, targetSec > 0, let candSec = item.durationSeconds {
                let diff = abs(candSec - targetSec)
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

    private func unescapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
