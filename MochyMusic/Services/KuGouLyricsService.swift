import Foundation

/// KuGou lyrics provider (`mobileservice.kugou.com` + `lyrics.kugou.com` search & Base64 download).
final class KuGouLyricsService {
    static let shared = KuGouLyricsService()

    private let session: URLSession

    private struct SongSearchResponseDTO: Decodable {
        let data: SongSearchDataDTO?
    }

    private struct SongSearchDataDTO: Decodable {
        let info: [SongInfoDTO]?
    }

    private struct SongInfoDTO: Decodable {
        let hash: String?
        let duration: Int?
    }

    private struct LyricsSearchResponseDTO: Decodable {
        let candidates: [LyricsCandidateDTO]?
    }

    private struct LyricsCandidateDTO: Decodable {
        let id: Int64?
        let accesskey: String?
    }

    private struct DownloadLyricsResponseDTO: Decodable {
        let content: String?
    }

    private static let acceptedLineRegex = try? NSRegularExpression(pattern: #"^\[\d{2}:\d{2}\.\d{2,3}\].*$"#)
    private static let bannedMetadataRegex = try? NSRegularExpression(pattern: #"^.+\].+[:：].+$"#)

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    func fetchLyrics(
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int? = nil
    ) async throws -> LyricsResult? {
        let cleanedTitle = normalizeTitle(LrcLibService.cleanTitle(title))
        let cleanedArtist = normalizeArtist(LrcLibService.cleanArtist(artist))
        let keyword = [cleanedTitle, cleanedArtist, album ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !keyword.isEmpty else { return nil }

        // 1. Search songs by keyword and match hash within 8 seconds tolerance
        let songs = await searchSongs(keyword: "\(cleanedTitle) - \(cleanedArtist)")
        if !songs.isEmpty {
            for song in songs {
                if let durationSeconds, durationSeconds > 0, let songDur = song.duration,
                   abs(songDur - durationSeconds) > 8 {
                    continue
                }
                if let hash = song.hash,
                   let candidate = await searchLyricsByHash(hash).first,
                   let result = await downloadAndParse(candidate: candidate) {
                    return result
                }
            }
        }

        // 2. Fallback: search lyrics directly by keyword + duration
        let directCandidates = await searchLyricsByKeyword("\(cleanedTitle) - \(cleanedArtist)", durationSeconds: durationSeconds)
        if let first = directCandidates.first,
           let result = await downloadAndParse(candidate: first) {
            return result
        }

        return nil
    }

    // MARK: - API Calls

    private func searchSongs(keyword: String) async -> [SongInfoDTO] {
        guard var components = URLComponents(string: "https://mobileservice.kugou.com/api/v3/search/song") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "version", value: "9108"),
            URLQueryItem(name: "plat", value: "0"),
            URLQueryItem(name: "pagesize", value: "8"),
            URLQueryItem(name: "showtype", value: "0"),
            URLQueryItem(name: "keyword", value: keyword)
        ]
        guard let url = components.url,
              let data = await fetchData(url: url),
              let decoded = try? JSONDecoder().decode(SongSearchResponseDTO.self, from: data) else {
            return []
        }
        return decoded.data?.info ?? []
    }

    private func searchLyricsByHash(_ hash: String) async -> [LyricsCandidateDTO] {
        guard var components = URLComponents(string: "https://lyrics.kugou.com/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "hash", value: hash)
        ]
        guard let url = components.url,
              let data = await fetchData(url: url),
              let decoded = try? JSONDecoder().decode(LyricsSearchResponseDTO.self, from: data) else {
            return []
        }
        return decoded.candidates ?? []
    }

    private func searchLyricsByKeyword(_ keyword: String, durationSeconds: Int?) async -> [LyricsCandidateDTO] {
        guard var components = URLComponents(string: "https://lyrics.kugou.com/search") else { return [] }
        var items = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "keyword", value: keyword)
        ]
        if let durationSeconds, durationSeconds > 0 {
            items.append(URLQueryItem(name: "duration", value: String(durationSeconds * 1000)))
        }
        components.queryItems = items

        guard let url = components.url,
              let data = await fetchData(url: url),
              let decoded = try? JSONDecoder().decode(LyricsSearchResponseDTO.self, from: data) else {
            return []
        }
        return decoded.candidates ?? []
    }

    private func downloadAndParse(candidate: LyricsCandidateDTO) async -> LyricsResult? {
        guard let id = candidate.id,
              let accessKey = candidate.accesskey,
              var components = URLComponents(string: "https://lyrics.kugou.com/download") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "fmt", value: "lrc"),
            URLQueryItem(name: "charset", value: "utf8"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "accesskey", value: accessKey)
        ]

        guard let url = components.url,
              let data = await fetchData(url: url),
              let decoded = try? JSONDecoder().decode(DownloadLyricsResponseDTO.self, from: data),
              let base64 = decoded.content,
              let rawLRCData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let rawLRC = String(data: rawLRCData, encoding: .utf8) else {
            return nil
        }

        let cleanedLRC = cleanKuGouLRC(rawLRC)
        let lines = LrcLibService.parseLRC(cleanedLRC)
        guard !lines.isEmpty else { return nil }

        return LyricsResult(
            syncedLines: lines,
            plainText: lines.map(\.text).joined(separator: "\n"),
            source: LyricsProvider.kugou.displayName
        )
    }

    private func fetchData(url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Normalization

    private func cleanKuGouLRC(_ raw: String) -> String {
        let validLines = raw.components(separatedBy: .newlines).filter { line in
            guard let regex = Self.acceptedLineRegex else { return false }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return regex.firstMatch(in: line, range: range) != nil
        }
        guard !validLines.isEmpty else { return raw }

        let headLimit = min(30, validLines.count - 1)
        var headCut = 0
        if headLimit >= 0 {
            for i in stride(from: headLimit, through: 0, by: -1) {
                if matchesBanned(validLines[i]) {
                    headCut = i + 1
                    break
                }
            }
        }
        let afterHead = Array(validLines.dropFirst(headCut))
        guard !afterHead.isEmpty else { return "" }

        let tailLimit = min(max(0, afterHead.count - 30), afterHead.count - 1)
        var tailCut = 0
        if tailLimit >= 0 {
            for i in stride(from: tailLimit, through: 0, by: -1) {
                if matchesBanned(afterHead[afterHead.count - 1 - i]) {
                    tailCut = i + 1
                    break
                }
            }
        }
        return afterHead.dropLast(tailCut).joined(separator: "\n")
    }

    private func matchesBanned(_ line: String) -> Bool {
        guard let regex = Self.bannedMetadataRegex else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }

    private func normalizeTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\(.*?\)|（.*?）|「.*?」|『.*?』|<.*?>|《.*?》"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeArtist(_ artist: String) -> String {
        artist.replacingOccurrences(of: ", ", with: "、")
            .replacingOccurrences(of: " & ", with: "、")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
