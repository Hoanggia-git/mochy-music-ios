import Foundation

/// Animated player background / Canvas video resolver (ArtistVideoCanvasProvider, Monochrome Tidal Canvas, and YouTube fallback).
@MainActor
final class CanvasService: ObservableObject {
    static let shared = CanvasService()

    @Published var currentCanvasURL: URL?
    @Published var currentStaticURL: URL?
    @Published var isLoading: Bool = false

    private struct CacheEntry {
        let videoURL: URL?
        let staticURL: URL?
        let expiresAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 60 * 60 * 6

    private let monochromeInstances = [
        "https://eu-central.monochrome.tf/",
        "https://us-west.monochrome.tf/",
        "https://arran.monochrome.tf/",
        "https://api.monochrome.tf/"
    ]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    private init() {}

    func fetchCanvas(for track: Track) async -> URL? {
        let cleanedTitle = LrcLibService.cleanTitle(track.title)
        let cleanedArtist = LrcLibService.cleanArtist(track.artistsText)
        let cacheKey = "\(track.id)|\(cleanedTitle.lowercased())|\(cleanedArtist.lowercased())"

        if let cached = cache[cacheKey], cached.expiresAt > Date() {
            currentCanvasURL = cached.videoURL
            currentStaticURL = cached.staticURL
            return cached.videoURL
        }

        if AppSettings.shared.offlineMode {
            currentCanvasURL = nil
            currentStaticURL = nil
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        // 1. Koiiverse ArtistVideoCanvasProvider (matches Android ArtistVideoCanvasProvider.kt)
        if let artistVideoResult = await fetchArtistVideoCanvas(
            song: cleanedTitle,
            artist: cleanedArtist,
            album: track.album?.name,
            duration: track.durationSeconds
        ) {
            cache[cacheKey] = CacheEntry(
                videoURL: artistVideoResult.videoURL,
                staticURL: artistVideoResult.staticURL,
                expiresAt: Date().addingTimeInterval(cacheTTL)
            )
            currentCanvasURL = artistVideoResult.videoURL
            currentStaticURL = artistVideoResult.staticURL
            if artistVideoResult.videoURL != nil {
                return artistVideoResult.videoURL
            }
        }

        // 2. Monochrome / Tidal video cover canvas (matches Android MonochromeApiCanvas.kt)
        if let tidalCanvasURL = await fetchMonochromeCanvas(
            song: cleanedTitle,
            artist: cleanedArtist,
            album: track.album?.name,
            durationSeconds: track.durationSeconds
        ) {
            cache[cacheKey] = CacheEntry(
                videoURL: tidalCanvasURL,
                staticURL: nil,
                expiresAt: Date().addingTimeInterval(cacheTTL)
            )
            currentCanvasURL = tidalCanvasURL
            return tidalCanvasURL
        }

        cache[cacheKey] = CacheEntry(
            videoURL: nil,
            staticURL: nil,
            expiresAt: Date().addingTimeInterval(60 * 10)
        )
        currentCanvasURL = nil
        return nil
    }

    func fetchYouTubeVideoStream(videoId: String) async -> URL? {
        if let resolved = try? await InnerTubeService.shared.resolveStream(videoId: videoId, quality: .medium),
           !resolved.isAudioOnly {
            return resolved.url
        }
        return nil
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Providers

    private func fetchArtistVideoCanvas(
        song: String,
        artist: String,
        album: String?,
        duration: Int?
    ) async -> (videoURL: URL?, staticURL: URL?)? {
        guard var components = URLComponents(string: "https://artwork-archivetune.koiiverse.cloud/") else {
            return nil
        }
        var items = [
            URLQueryItem(name: "s", value: song),
            URLQueryItem(name: "a", value: artist)
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "al", value: album))
        }
        if let duration, duration > 0 {
            items.append(URLQueryItem(name: "d", value: String(duration)))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let animStr = (json["animated"] as? String) ?? (json["videoUrl"] as? String)
            let staticStr = json["static"] as? String
            let animURL = animStr.flatMap { URL(string: $0) }
            let staticURL = staticStr.flatMap { URL(string: $0) }
            if animURL == nil && staticURL == nil { return nil }
            return (animURL, staticURL)
        } catch {
            return nil
        }
    }

    private func fetchMonochromeCanvas(
        song: String,
        artist: String,
        album: String?,
        durationSeconds: Int?
    ) async -> URL? {
        let query = (album?.isEmpty == false)
            ? "\(artist) - \(song) - \(album!)"
            : "\(artist) - \(song)"

        for base in monochromeInstances {
            guard var components = URLComponents(string: "\(base)search/") else { continue }
            components.queryItems = [URLQueryItem(name: "s", value: query)]
            guard let url = components.url else { continue }

            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = findItemsArray(in: root) else {
                    continue
                }

                for item in items {
                    guard let trackTitle = item["title"] as? String,
                          normalize(trackTitle) == normalize(song) || normalize(trackTitle).contains(normalize(song)) else {
                        continue
                    }

                    let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    guard artists.contains(where: { normalize($0).contains(normalize(artist)) || normalize(artist).contains(normalize($0)) }) else {
                        continue
                    }

                    if let durationSeconds,
                       let trackDur = item["duration"] as? Double,
                       abs(trackDur - Double(durationSeconds)) > 6.0 {
                        continue
                    }

                    if let albumObj = item["album"] as? [String: Any],
                       let videoCover = albumObj["videoCover"] as? String,
                       !videoCover.isEmpty {
                        let parts = videoCover.split(separator: "-")
                        if parts.count == 5 {
                            let urlString = "https://resources.tidal.com/videos/\(parts[0])/\(parts[1])/\(parts[2])/\(parts[3])/\(parts[4])/1280x1280.mp4"
                            if let videoURL = URL(string: urlString) {
                                return videoURL
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func findItemsArray(in object: Any) -> [[String: Any]]? {
        if let dict = object as? [String: Any] {
            if let items = dict["items"] as? [[String: Any]], !items.isEmpty {
                return items
            }
            for value in dict.values {
                if let found = findItemsArray(in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for elem in array {
                if let found = findItemsArray(in: elem) {
                    return found
                }
            }
        }
        return nil
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: "", options: .regularExpression)
    }
}
