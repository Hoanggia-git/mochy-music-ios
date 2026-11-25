import Foundation

/// YouLyPlus lyrics provider querying `lyricsplus.prjktla.my.id` and `lyricsplus.binimum.org`.
final class YouLyPlusLyricsService {
    static let shared = YouLyPlusLyricsService()

    private let servers = [
        "https://lyricsplus.prjktla.my.id",
        "https://lyricsplus.binimum.org"
    ]
    private let userAgent = "Mochy (+https://github.com/realidkroo/Mochy-Music)"
    private let session: URLSession

    private struct ResponseDTO: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let lyrics: [LyricsItemDTO]?
    }

    private struct LyricsItemDTO: Decodable {
        let time: Int64?
        let text: String?
        let syllabus: [SyllabusItemDTO]?
    }

    private struct SyllabusItemDTO: Decodable {
        let text: String?
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
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

        for server in servers {
            if let dto = await fetchFromServer(
                baseURL: server,
                videoId: videoId,
                title: cleanedTitle,
                artist: cleanedArtist,
                album: album,
                durationSeconds: durationSeconds
            ) {
                if let result = convertToLyricsResult(dto) {
                    return result
                }
            }
        }
        return nil
    }

    private func fetchFromServer(
        baseURL: String,
        videoId: String?,
        title: String,
        artist: String,
        album: String?,
        durationSeconds: Int?
    ) async -> ResponseDTO? {
        guard var components = URLComponents(string: "\(baseURL)/v2/lyrics/get") else { return nil }
        var items = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "source", value: "apple,lyricsplus,musixmatch,spotify")
        ]
        if let durationSeconds, durationSeconds > 0 {
            items.append(URLQueryItem(name: "duration", value: String(durationSeconds)))
        }
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album", value: album))
        }
        if let videoId, !videoId.isEmpty {
            items.append(URLQueryItem(name: "id", value: videoId))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(ResponseDTO.self, from: data)
        } catch {
            return nil
        }
    }

    private func convertToLyricsResult(_ dto: ResponseDTO) -> LyricsResult? {
        if let syncedLRC = dto.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !syncedLRC.isEmpty {
            let parsed = LrcLibService.parseLRC(syncedLRC)
            if !parsed.isEmpty {
                return LyricsResult(
                    syncedLines: parsed,
                    plainText: dto.plainLyrics ?? parsed.map(\.text).joined(separator: "\n"),
                    source: LyricsProvider.youLyPlus.displayName
                )
            }
        }

        if let items = dto.lyrics, !items.isEmpty {
            var lines: [LyricLine] = []
            for item in items {
                let timeSec = Double(item.time ?? 0) / 1000.0
                let text: String
                if let syllabus = item.syllabus, !syllabus.isEmpty {
                    let spacedByAPI = syllabus.dropLast().contains { ($0.text?.last?.isWhitespace) == true }
                    if spacedByAPI {
                        text = syllabus.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        text = syllabus.compactMap(\.text)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                    }
                } else {
                    text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !text.isEmpty {
                    lines.append(LyricLine(time: timeSec, text: text))
                }
            }
            if !lines.isEmpty {
                return LyricsResult(
                    syncedLines: lines,
                    plainText: dto.plainLyrics ?? lines.map(\.text).joined(separator: "\n"),
                    source: LyricsProvider.youLyPlus.displayName
                )
            }
        }

        if let plain = dto.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return LyricsResult(
                syncedLines: nil,
                plainText: plain,
                source: LyricsProvider.youLyPlus.displayName
            )
        }

        return nil
    }
}
