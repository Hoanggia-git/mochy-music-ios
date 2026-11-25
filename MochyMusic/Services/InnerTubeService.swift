import Foundation

struct ResolvedStream {
    let url: URL
    let userAgent: String
    let isAudioOnlyM4A: Bool
}

enum InnerTubeError: LocalizedError {
    case invalidURL
    case badResponse(Int)
    case unplayable(String)
    case noCompatibleStream

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid YouTube endpoint URL."
        case .badResponse(let code):
            return "YouTube returned HTTP \(code)."
        case .unplayable(let reason):
            return reason
        case .noCompatibleStream:
            return "No iOS-compatible audio stream (M4A/HLS) found."
        }
    }
}

final class InnerTubeService {
    static let shared = InnerTubeService()

    private let session: URLSession
    private var visitorIds: [String: String] = [:]

    private struct ClientProfile {
        let name: String
        let version: String
        let id: String
        let userAgent: String
        let apiOrigin: String
        let osName: String?
        let osVersion: String?
        let deviceMake: String?
        let deviceModel: String?
        let androidSdkVersion: String?
        let clientScreen: String?
        let platform: String?
        let apiFormatVersion: String
        let isNativeApp: Bool
    }

    private let webRemix = ClientProfile(
        name: "WEB_REMIX",
        version: "1.20260707.12.00",
        id: "67",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
        apiOrigin: "https://music.youtube.com",
        osName: nil,
        osVersion: nil,
        deviceMake: nil,
        deviceModel: nil,
        androidSdkVersion: nil,
        clientScreen: nil,
        platform: nil,
        apiFormatVersion: "1",
        isNativeApp: false
    )

    private let playerClients: [ClientProfile] = [
        ClientProfile(
            name: "IOS",
            version: "21.03.3",
            id: "5",
            userAgent: "com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 like Mac OS X; en-US)",
            apiOrigin: "https://www.youtube.com",
            osName: "iPadOS",
            osVersion: "17.7.10.21H450",
            deviceMake: "Apple",
            deviceModel: "iPad7,6",
            androidSdkVersion: nil,
            clientScreen: nil,
            platform: nil,
            apiFormatVersion: "1",
            isNativeApp: true
        ),
        ClientProfile(
            name: "ANDROID_VR",
            version: "1.61.48",
            id: "28",
            userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Oculus Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
            apiOrigin: "https://www.youtube.com",
            osName: "Android",
            osVersion: "12",
            deviceMake: "Oculus",
            deviceModel: "Quest 3",
            androidSdkVersion: "32",
            clientScreen: nil,
            platform: nil,
            apiFormatVersion: "1",
            isNativeApp: true
        ),
        ClientProfile(
            name: "VISIONOS",
            version: "1.04",
            id: "101",
            userAgent: "com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)",
            apiOrigin: "https://www.youtube.com",
            osName: "visionOS",
            osVersion: "26.6.0.23O770",
            deviceMake: "Apple",
            deviceModel: "RealityDevice17,1",
            androidSdkVersion: nil,
            clientScreen: "WATCH",
            platform: "MOBILE",
            apiFormatVersion: "2",
            isNativeApp: true
        )
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func searchSongs(query: String) async throws -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // FILTER_SONG params from Mochy-Music YouTube.kt
        let body: [String: Any] = [
            "context": makeContext(client: webRemix, visitorData: visitorIds[webRemix.name]),
            "query": trimmed,
            "params": "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        ]

        let json = try await postJSON(
            urlString: "\(webRemix.apiOrigin)/youtubei/v1/search?prettyPrint=false",
            client: webRemix,
            body: body
        )

        var tracks = extractTracksFromSearchJSON(json)
        if tracks.isEmpty {
            // Fallback unfiltered search in case YouTube Music rejects params for a query
            let fallbackBody: [String: Any] = [
                "context": makeContext(client: webRemix, visitorData: visitorIds[webRemix.name]),
                "query": trimmed
            ]
            let fallbackJSON = try await postJSON(
                urlString: "\(webRemix.apiOrigin)/youtubei/v1/search?prettyPrint=false",
                client: webRemix,
                body: fallbackBody
            )
            tracks = extractTracksFromSearchJSON(fallbackJSON)
        }
        return deduplicate(tracks)
    }

    func fetchHomeTracks() async throws -> [Track] {
        let body: [String: Any] = [
            "context": makeContext(client: webRemix, visitorData: visitorIds[webRemix.name]),
            "browseId": "FEmusic_explore"
        ]
        let json = try await postJSON(
            urlString: "\(webRemix.apiOrigin)/youtubei/v1/browse?prettyPrint=false",
            client: webRemix,
            body: body
        )
        let tracks = extractTracksRecursively(from: json)
        return deduplicate(tracks)
    }

    func fetchUpNext(videoId: String) async throws -> [Track] {
        let body: [String: Any] = [
            "context": makeContext(client: webRemix, visitorData: visitorIds[webRemix.name]),
            "videoId": videoId,
            "playlistId": "RDAMVM\(videoId)"
        ]
        let json = try await postJSON(
            urlString: "\(webRemix.apiOrigin)/youtubei/v1/next?prettyPrint=false",
            client: webRemix,
            body: body
        )
        let tracks = extractTracksFromNextJSON(json)
        return deduplicate(tracks.filter { $0.id != videoId })
    }

    func resolveStream(videoId: String) async throws -> ResolvedStream {
        var lastError: Error = InnerTubeError.noCompatibleStream

        for client in playerClients {
            do {
                let visitor = try await ensureVisitorId(for: client)
                let body: [String: Any] = [
                    "context": makeContext(client: client, visitorData: visitor),
                    "videoId": videoId,
                    "contentCheckOk": true,
                    "racyCheckOk": true
                ]
                let json = try await postJSON(
                    urlString: "\(client.apiOrigin)/youtubei/v1/player?prettyPrint=false",
                    client: client,
                    body: body,
                    visitorData: visitor
                )

                if let playability = json["playabilityStatus"] as? [String: Any],
                   let status = playability["status"] as? String,
                   status != "OK" {
                    let reason = playability["reason"] as? String ?? "Playback status: \(status)"
                    lastError = InnerTubeError.unplayable(reason)
                    continue
                }

                if let stream = extractBestIOSStream(from: json, client: client) {
                    return stream
                }
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    // MARK: - Networking

    private func ensureVisitorId(for client: ClientProfile) async throws -> String? {
        if let cached = visitorIds[client.name] {
            return cached
        }
        let body: [String: Any] = [
            "context": makeContext(client: client, visitorData: nil)
        ]
        guard let json = try? await postJSON(
            urlString: "\(client.apiOrigin)/youtubei/v1/visitor_id?prettyPrint=false",
            client: client,
            body: body
        ),
        let respCtx = json["responseContext"] as? [String: Any],
        let visitor = respCtx["visitorData"] as? String,
        !visitor.isEmpty else {
            return nil
        }
        visitorIds[client.name] = visitor
        return visitor
    }

    private func makeContext(client: ClientProfile, visitorData: String?) -> [String: Any] {
        var clientDict: [String: Any] = [
            "clientName": client.name,
            "clientVersion": client.version,
            "gl": Locale.current.region?.identifier ?? "US",
            "hl": Locale.current.language.languageCode?.identifier ?? "en"
        ]
        if let osName = client.osName { clientDict["osName"] = osName }
        if let osVersion = client.osVersion { clientDict["osVersion"] = osVersion }
        if let deviceMake = client.deviceMake { clientDict["deviceMake"] = deviceMake }
        if let deviceModel = client.deviceModel { clientDict["deviceModel"] = deviceModel }
        if let sdk = client.androidSdkVersion { clientDict["androidSdkVersion"] = sdk }
        if let screen = client.clientScreen {
            clientDict["clientScreen"] = screen
            clientDict["utcOffsetMinutes"] = 0
        }
        if let platform = client.platform { clientDict["platform"] = platform }
        if let visitorData { clientDict["visitorData"] = visitorData }

        return [
            "client": clientDict,
            "user": [String: Any]()
        ]
    }

    private func postJSON(
        urlString: String,
        client: ClientProfile,
        body: [String: Any],
        visitorData: String? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw InnerTubeError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(client.apiFormatVersion, forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue(client.id, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        if !client.isNativeApp {
            request.setValue(client.apiOrigin, forHTTPHeaderField: "X-Origin")
            request.setValue("\(client.apiOrigin)/", forHTTPHeaderField: "Referer")
        }
        if let visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InnerTubeError.badResponse(http.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.noCompatibleStream
        }
        return object
    }

    // MARK: - Stream Selection (iOS AVPlayer-compatible)

    private func extractBestIOSStream(from json: [String: Any], client: ClientProfile) -> ResolvedStream? {
        guard let streamingData = json["streamingData"] as? [String: Any] else { return nil }

        // 1. Prefer direct M4A/AAC adaptive audio streams (AVPlayer cannot play WebM/Opus)
        if let adaptive = streamingData["adaptiveFormats"] as? [[String: Any]] {
            let m4aCandidates = adaptive.compactMap { format -> (url: URL, bitrate: Int)? in
                guard let urlString = format["url"] as? String,
                      let url = URL(string: urlString),
                      let mimeType = format["mimeType"] as? String,
                      mimeType.lowercased().contains("audio/mp4"),
                      format["width"] == nil else {
                    return nil
                }
                let bitrate = format["bitrate"] as? Int ?? 0
                return (url, bitrate)
            }
            if let best = m4aCandidates.max(by: { $0.bitrate < $1.bitrate }) {
                return ResolvedStream(url: best.url, userAgent: client.userAgent, isAudioOnlyM4A: true)
            }
        }

        // 2. Fallback to progressive MP4 formats if available
        if let formats = streamingData["formats"] as? [[String: Any]] {
            let mp4Candidates = formats.compactMap { format -> (url: URL, bitrate: Int)? in
                guard let urlString = format["url"] as? String,
                      let url = URL(string: urlString),
                      let mimeType = format["mimeType"] as? String,
                      mimeType.lowercased().contains("mp4") else {
                    return nil
                }
                let bitrate = format["bitrate"] as? Int ?? 0
                return (url, bitrate)
            }
            if let best = mp4Candidates.max(by: { $0.bitrate < $1.bitrate }) {
                return ResolvedStream(url: best.url, userAgent: client.userAgent, isAudioOnlyM4A: false)
            }
        }

        // 3. Fallback to HLS manifest (common with IOS client)
        if let hlsString = streamingData["hlsManifestUrl"] as? String,
           let hlsURL = URL(string: hlsString) {
            return ResolvedStream(url: hlsURL, userAgent: client.userAgent, isAudioOnlyM4A: false)
        }

        return nil
    }

    // MARK: - Search & Browse Parsers

    private func extractTracksFromSearchJSON(_ json: [String: Any]) -> [Track] {
        return extractTracksRecursively(from: json)
    }

    private func extractTracksFromNextJSON(_ json: [String: Any]) -> [Track] {
        var results: [Track] = []
        collectPlaylistPanelRenderers(from: json, into: &results)
        return results
    }

    private func collectPlaylistPanelRenderers(from node: Any, into results: inout [Track]) {
        if let dict = node as? [String: Any] {
            if let panelVideo = dict["playlistPanelVideoRenderer"] as? [String: Any],
               let track = parsePlaylistPanelVideoRenderer(panelVideo) {
                results.append(track)
                return
            }
            for value in dict.values {
                collectPlaylistPanelRenderers(from: value, into: &results)
            }
        } else if let array = node as? [Any] {
            for item in array {
                collectPlaylistPanelRenderers(from: item, into: &results)
            }
        }
    }

    private func extractTracksRecursively(from node: Any) -> [Track] {
        var results: [Track] = []
        if let dict = node as? [String: Any] {
            if let listItem = dict["musicResponsiveListItemRenderer"] as? [String: Any],
               let track = parseMusicResponsiveListItemRenderer(listItem) {
                results.append(track)
            } else if let twoRow = dict["musicTwoRowItemRenderer"] as? [String: Any],
                      let track = parseMusicTwoRowItemRenderer(twoRow) {
                results.append(track)
            } else {
                for value in dict.values {
                    results.append(contentsOf: extractTracksRecursively(from: value))
                }
            }
        } else if let array = node as? [Any] {
            for item in array {
                results.append(contentsOf: extractTracksRecursively(from: item))
            }
        }
        return results
    }

    private func parseMusicResponsiveListItemRenderer(_ dict: [String: Any]) -> Track? {
        let videoId = (dict["playlistItemData"] as? [String: Any])?["videoId"] as? String
            ?? (((((dict["overlay"] as? [String: Any])?["musicItemThumbnailOverlayRenderer"] as? [String: Any])?["content"] as? [String: Any])?["musicPlayButtonRenderer"] as? [String: Any])?["playNavigationEndpoint"] as? [String: Any])?["watchEndpoint"].flatMap { ($0 as? [String: Any])?["videoId"] as? String }

        guard let videoId, !videoId.isEmpty else { return nil }

        guard let flexColumns = dict["flexColumns"] as? [[String: Any]], !flexColumns.isEmpty else {
            return nil
        }

        let titleRuns = ((flexColumns[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any])?["runs"] as? [[String: Any]]
        guard let title = titleRuns?.first?["text"] as? String, !title.isEmpty else { return nil }

        var artistName = "Unknown Artist"
        var albumName: String?
        var durationSeconds: Int?

        if flexColumns.count > 1 {
            let secondaryRuns = ((flexColumns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
            let segments = splitRunsByBullet(secondaryRuns)
            if let firstSeg = segments.first, !firstSeg.isEmpty {
                let joined = firstSeg.map { $0.text }.joined(separator: ", ")
                if !joined.isEmpty {
                    artistName = joined
                }
            }
            if segments.count > 1 {
                for seg in segments.dropFirst() {
                    if let first = seg.first {
                        if let parsed = parseDuration(first.text) {
                            durationSeconds = parsed
                        } else if first.hasBrowseEndpoint {
                            albumName = first.text
                        }
                    }
                }
            }
        }

        let thumb = extractBestThumbnail(from: dict["thumbnail"])
        return Track(
            id: videoId,
            title: title,
            artist: artistName,
            album: albumName,
            durationSeconds: durationSeconds,
            thumbnailURL: thumb
        )
    }

    private func parseMusicTwoRowItemRenderer(_ dict: [String: Any]) -> Track? {
        guard let nav = dict["navigationEndpoint"] as? [String: Any],
              let watch = nav["watchEndpoint"] as? [String: Any],
              let videoId = watch["videoId"] as? String,
              !videoId.isEmpty else {
            return nil
        }
        let titleRuns = (dict["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        guard let title = titleRuns?.first?["text"] as? String, !title.isEmpty else { return nil }

        let subtitleRuns = (dict["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
        let segments = splitRunsByBullet(subtitleRuns)
        let artist = segments.first?.map { $0.text }.joined(separator: ", ") ?? "YouTube Music"
        let thumb = extractBestThumbnail(from: dict["thumbnailRenderer"])

        return Track(
            id: videoId,
            title: title,
            artist: artist.isEmpty ? "YouTube Music" : artist,
            album: nil,
            durationSeconds: nil,
            thumbnailURL: thumb
        )
    }

    private func parsePlaylistPanelVideoRenderer(_ dict: [String: Any]) -> Track? {
        guard let videoId = dict["videoId"] as? String, !videoId.isEmpty else { return nil }
        let titleRuns = (dict["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        guard let title = titleRuns?.first?["text"] as? String, !title.isEmpty else { return nil }

        let longByline = (dict["longBylineText"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
        let segments = splitRunsByBullet(longByline)
        let artist = segments.first?.map { $0.text }.joined(separator: ", ") ?? "Unknown Artist"
        let durationText = ((dict["lengthText"] as? [String: Any])?["runs"] as? [[String: Any]])?.first?["text"] as? String
        let thumb = extractBestThumbnail(from: dict["thumbnail"])

        return Track(
            id: videoId,
            title: title,
            artist: artist.isEmpty ? "Unknown Artist" : artist,
            album: nil,
            durationSeconds: durationText.flatMap { parseDuration($0) },
            thumbnailURL: thumb
        )
    }

    private struct RunToken {
        let text: String
        let hasBrowseEndpoint: Bool
    }

    private func splitRunsByBullet(_ runs: [[String: Any]]) -> [[RunToken]] {
        var groups: [[RunToken]] = [[]]
        for run in runs {
            guard let text = run["text"] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed == "•" || trimmed == "\u{2022}" {
                groups.append([])
                continue
            }
            if trimmed == "&" || trimmed == "," || trimmed.isEmpty {
                continue
            }
            let nav = run["navigationEndpoint"] as? [String: Any]
            let hasBrowse = nav?["browseEndpoint"] != nil
            groups[groups.count - 1].append(RunToken(text: text, hasBrowseEndpoint: hasBrowse))
        }
        return groups.filter { !$0.isEmpty }
    }

    private func extractBestThumbnail(from node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        let thumbs: [[String: Any]]? =
            ((dict["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            ?? (dict["thumbnails"] as? [[String: Any]])
        guard var url = thumbs?.last?["url"] as? String else { return nil }
        if url.contains("lh3.googleusercontent.com"), let eqRange = url.range(of: "=w") {
            url = String(url[..<eqRange.lowerBound]) + "=w544-h544-l90-rj"
        }
        return url
    }

    private func parseDuration(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2:
            return parts[0] * 60 + parts[1]
        case 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }

    private func deduplicate(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }
}
