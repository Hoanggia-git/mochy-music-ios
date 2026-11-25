import Foundation
import CryptoKit

// MARK: - InnerTube Models & Errors

enum InnerTubeError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int, String?)
    case decodingError(String)
    case playabilityError(status: String, reason: String?)
    case noPlayableStream
    case offlineMode

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid InnerTube request URL."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .decodingError(let detail):
            return "Failed to parse InnerTube response: \(detail)"
        case .playabilityError(let status, let reason):
            return reason ?? "Playback unavailable (\(status))."
        case .noPlayableStream:
            return "No iOS-compatible audio stream found for this track."
        case .offlineMode:
            return "Offline mode is enabled."
        }
    }
}

struct ArtistDetailResult: Hashable {
    var artist: Artist
    var description: String?
    var monthlyListeners: String?
    var topSongs: [Track]
    var albums: [Album]
    var singles: [Album]
    var videos: [Track]
    var playlists: [YouTubePlaylist]
    var relatedArtists: [Artist]
    var sections: [HomeSection]
}

// MARK: - Client Profiles

struct ClientProfile {
    let clientName: String
    let clientVersion: String
    let clientId: String
    let userAgent: String
    let osName: String?
    let osVersion: String?
    let deviceMake: String?
    let deviceModel: String?
    let apiOrigin: String
    let apiFormatVersion: String
    let clientScreen: String?
    let platform: String?
    let ownVisitorId: Bool
    let loginSupported: Bool

    var isNativeApp: Bool {
        platform != nil || osName == "iOS" || osName == "iPadOS" || osName == "Android" || osName == "visionOS"
    }

    static let originYouTube = "https://www.youtube.com"
    static let originYouTubeMusic = "https://music.youtube.com"
    static let userAgentWeb = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"

    static let webRemix = ClientProfile(
        clientName: "WEB_REMIX",
        clientVersion: "1.20260707.12.00",
        clientId: "67",
        userAgent: userAgentWeb,
        osName: nil,
        osVersion: nil,
        deviceMake: nil,
        deviceModel: nil,
        apiOrigin: originYouTubeMusic,
        apiFormatVersion: "1",
        clientScreen: nil,
        platform: nil,
        ownVisitorId: false,
        loginSupported: true
    )

    static let web = ClientProfile(
        clientName: "WEB",
        clientVersion: "2.20260708.00.00",
        clientId: "1",
        userAgent: userAgentWeb,
        osName: nil,
        osVersion: nil,
        deviceMake: nil,
        deviceModel: nil,
        apiOrigin: originYouTube,
        apiFormatVersion: "1",
        clientScreen: nil,
        platform: nil,
        ownVisitorId: false,
        loginSupported: false
    )

    static let ios = ClientProfile(
        clientName: "IOS",
        clientVersion: "21.03.1",
        clientId: "5",
        userAgent: "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
        osName: "iOS",
        osVersion: "18.2.22C152",
        deviceMake: "Apple",
        deviceModel: "iPhone16,2",
        apiOrigin: originYouTube,
        apiFormatVersion: "1",
        clientScreen: nil,
        platform: "MOBILE",
        ownVisitorId: false,
        loginSupported: false
    )

    static let ipados = ClientProfile(
        clientName: "IOS",
        clientVersion: "21.03.3",
        clientId: "5",
        userAgent: "com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 like Mac OS X; en-US)",
        osName: "iPadOS",
        osVersion: "17.7.10.21H450",
        deviceMake: "Apple",
        deviceModel: "iPad7,6",
        apiOrigin: originYouTube,
        apiFormatVersion: "1",
        clientScreen: nil,
        platform: "MOBILE",
        ownVisitorId: false,
        loginSupported: false
    )

    static let androidVR = ClientProfile(
        clientName: "ANDROID_VR",
        clientVersion: "1.61.48",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Oculus Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        apiOrigin: originYouTube,
        apiFormatVersion: "1",
        clientScreen: nil,
        platform: "MOBILE",
        ownVisitorId: false,
        loginSupported: false
    )

    static let visionOS = ClientProfile(
        clientName: "VISIONOS",
        clientVersion: "1.04",
        clientId: "101",
        userAgent: "com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)",
        osName: "visionOS",
        osVersion: "26.6.0.23O770",
        deviceMake: "Apple",
        deviceModel: "RealityDevice17,1",
        apiOrigin: originYouTube,
        apiFormatVersion: "2",
        clientScreen: "WATCH",
        platform: "MOBILE",
        ownVisitorId: true,
        loginSupported: false
    )

    func contextPayload(gl: String, hl: String, visitorData: String?, dataSyncId: String?) -> [String: Any] {
        var client: [String: Any] = [
            "clientName": clientName,
            "clientVersion": clientVersion,
            "gl": gl,
            "hl": hl
        ]
        if let osName { client["osName"] = osName }
        if let osVersion { client["osVersion"] = osVersion }
        if let deviceMake { client["deviceMake"] = deviceMake }
        if let deviceModel { client["deviceModel"] = deviceModel }
        if let clientScreen {
            client["clientScreen"] = clientScreen
            client["utcOffsetMinutes"] = 0
        }
        if let platform { client["platform"] = platform }
        if let visitorData, !visitorData.isEmpty {
            client["visitorData"] = visitorData
        }

        var user: [String: Any] = [:]
        if loginSupported, let dataSyncId, !dataSyncId.isEmpty {
            user["onBehalfOfUser"] = dataSyncId
        }

        return [
            "client": client,
            "user": user
        ]
    }
}

// MARK: - InnerTubeService

final class InnerTubeService: ObservableObject {
    static let shared = InnerTubeService()

    @Published var visitorData: String?
    @Published var cookie: String?
    @Published var dataSyncId: String?

    private let session: URLSession
    private var ownVisitorIds: [String: String] = [:]
    private let lock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    private var currentGL: String {
        let country = AppSettings.shared.contentCountry
        if !country.isEmpty { return country }
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier ?? "US"
        }
        return "US"
    }

    private var currentHL: String {
        let lang = AppSettings.shared.contentLanguage
        if !lang.isEmpty { return lang }
        return Locale.current.language.languageCode?.identifier ?? "en"
    }

    // MARK: - Visitor ID Minting

    @discardableResult
    func refreshVisitorId(for client: ClientProfile = .webRemix) async throws -> String {
        guard let url = URL(string: "\(client.apiOrigin)/youtubei/v1/visitor_id?prettyPrint=false") else {
            throw InnerTubeError.invalidURL
        }
        let body: [String: Any] = [
            "context": client.contextPayload(gl: currentGL, hl: currentHL, visitorData: nil, dataSyncId: nil)
        ]
        let json = try await postJSON(url: url, client: client, body: body, visitorOverride: nil)
        if let responseContext = json["responseContext"] as? [String: Any],
           let minted = responseContext["visitorData"] as? String, !minted.isEmpty {
            lock.withLock {
                if client.ownVisitorId {
                    ownVisitorIds[client.clientName] = minted
                } else {
                    DispatchQueue.main.async {
                        self.visitorData = minted
                    }
                }
            }
            return minted
        }
        throw InnerTubeError.decodingError("visitorData missing from /visitor_id")
    }

    private func visitorId(for client: ClientProfile) async -> String? {
        if client.ownVisitorId {
            if let cached = lock.withLock({ ownVisitorIds[client.clientName] }) {
                return cached
            }
            return try? await refreshVisitorId(for: client)
        }
        if let existing = visitorData, !existing.isEmpty {
            return existing
        }
        return try? await refreshVisitorId(for: .webRemix)
    }

    // MARK: - Search

    func search(
        query: String,
        filter: SearchFilter,
        continuation: String? = nil
    ) async throws -> SearchResult {
        let params = filter.innertubeParams.removingPercentEncoding ?? filter.innertubeParams
        let json: [String: Any]
        if let continuation, !continuation.isEmpty {
            json = try await performInnerTubeRequest(
                endpoint: "search",
                client: .webRemix,
                queryItems: [
                    URLQueryItem(name: "continuation", value: continuation),
                    URLQueryItem(name: "ctoken", value: continuation)
                ],
                body: [:]
            )
            let contItems = dig(json, path: ["continuationContents", "musicShelfContinuation", "contents"]) as? [[String: Any]] ?? []
            let items = contItems.compactMap { parseSearchItem(from: $0["musicResponsiveListItemRenderer"] as? [String: Any]) }
            let nextCont = items.isEmpty ? nil : extractContinuation(from: dig(json, path: ["continuationContents", "musicShelfContinuation", "continuations"]) as? [[String: Any]])
            return SearchResult(items: items, continuation: nextCont)
        } else {
            json = try await performInnerTubeRequest(
                endpoint: "search",
                client: .webRemix,
                body: [
                    "query": query,
                    "params": params
                ]
            )
            let tabs = dig(json, path: ["contents", "tabbedSearchResultsRenderer", "tabs"]) as? [[String: Any]] ?? []
            let sectionContents = dig(tabs.first, path: ["tabRenderer", "content", "sectionListRenderer", "contents"]) as? [[String: Any]] ?? []
            let shelf = sectionContents.compactMap { $0["musicShelfRenderer"] as? [String: Any] }.first
            let rawItems = shelf?["contents"] as? [[String: Any]] ?? []
            let items = rawItems.compactMap { parseSearchItem(from: $0["musicResponsiveListItemRenderer"] as? [String: Any]) }
            let nextCont = extractContinuation(from: shelf?["continuations"] as? [[String: Any]])
            return SearchResult(items: items, continuation: nextCont)
        }
    }

    func searchSongs(query: String) async throws -> [Track] {
        let result = try await search(query: query, filter: .songs)
        return result.items.compactMap {
            if case .track(let track) = $0 { return track }
            return nil
        }
    }

    func searchVideos(query: String) async throws -> [Track] {
        let result = try await search(query: query, filter: .videos)
        return result.items.compactMap {
            if case .track(let track) = $0 { return track }
            return nil
        }
    }

    func searchAlbums(query: String) async throws -> [Album] {
        let result = try await search(query: query, filter: .albums)
        return result.items.compactMap {
            if case .album(let album) = $0 { return album }
            return nil
        }
    }

    func searchArtists(query: String) async throws -> [Artist] {
        let result = try await search(query: query, filter: .artists)
        return result.items.compactMap {
            if case .artist(let artist) = $0 { return artist }
            return nil
        }
    }

    func searchPlaylists(query: String) async throws -> [YouTubePlaylist] {
        let result = try await search(query: query, filter: .playlists)
        return result.items.compactMap {
            if case .playlist(let playlist) = $0 { return playlist }
            return nil
        }
    }

    func searchAll(query: String) async throws -> [HomeSection] {
        let json = try await performInnerTubeRequest(
            endpoint: "search",
            client: .webRemix,
            body: ["query": query]
        )

        let tabs = dig(json, path: ["contents", "tabbedSearchResultsRenderer", "tabs"]) as? [[String: Any]] ?? []
        let sectionContents = dig(tabs.first, path: ["tabRenderer", "content", "sectionListRenderer", "contents"]) as? [[String: Any]] ?? []

        var sections: [HomeSection] = []

        for content in sectionContents {
            if let cardShelf = content["musicCardShelfRenderer"] as? [String: Any] {
                let headerTitle = firstRunText(in: dig(cardShelf, path: ["header", "musicCardShelfHeaderBasicRenderer", "title"])) ?? "Top Result"
                var items: [HomeSectionItem] = []

                if let topItem = parseCardShelfTopItem(cardShelf) {
                    items.append(topItem)
                }

                let subContents = cardShelf["contents"] as? [[String: Any]] ?? []
                for sub in subContents {
                    if let renderer = sub["musicResponsiveListItemRenderer"] as? [String: Any],
                       let item = parseHomeSectionItem(fromResponsive: renderer) {
                        items.append(item)
                    }
                }

                if !items.isEmpty {
                    sections.append(HomeSection(title: headerTitle, items: items))
                }
            } else if let shelf = content["musicShelfRenderer"] as? [String: Any] {
                let title = firstRunText(in: shelf["title"]) ?? "Results"
                let shelfItems = (shelf["contents"] as? [[String: Any]] ?? []).compactMap {
                    parseHomeSectionItem(fromResponsive: $0["musicResponsiveListItemRenderer"] as? [String: Any])
                }
                if !shelfItems.isEmpty {
                    sections.append(HomeSection(title: title, items: shelfItems))
                }
            }
        }

        return sections
    }

    func searchSuggestions(query: String) async throws -> [SearchSuggestion] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let json = try await performInnerTubeRequest(
            endpoint: "music/get_search_suggestions",
            client: .webRemix,
            body: ["input": query]
        )

        let contents = json["contents"] as? [[String: Any]] ?? []
        var suggestions: [SearchSuggestion] = []

        for section in contents {
            guard let sectionRenderer = section["searchSuggestionsSectionRenderer"] as? [String: Any],
                  let items = sectionRenderer["contents"] as? [[String: Any]] else { continue }
            for item in items {
                if let suggestionRenderer = item["searchSuggestionRenderer"] as? [String: Any],
                   let runs = dig(suggestionRenderer, path: ["suggestion", "runs"]) as? [[String: Any]] {
                    let text = runs.compactMap { $0["text"] as? String }.joined()
                    if !text.isEmpty {
                        suggestions.append(SearchSuggestion(text: text, isHistory: false))
                    }
                } else if let responsive = item["musicResponsiveListItemRenderer"] as? [String: Any],
                          let track = parseTrack(fromResponsive: responsive) {
                    suggestions.append(SearchSuggestion(text: track.title, isHistory: false))
                }
            }
        }

        return suggestions
    }

    // MARK: - Home / Explore / Charts / Moods / New Releases / Browse

    func fetchHomeFeed(continuation: String? = nil, params: String? = nil) async throws -> BrowseResult {
        if let continuation, !continuation.isEmpty {
            let json = try await performInnerTubeRequest(
                endpoint: "browse",
                client: .webRemix,
                queryItems: [
                    URLQueryItem(name: "continuation", value: continuation),
                    URLQueryItem(name: "ctoken", value: continuation)
                ],
                body: ["continuation": continuation]
            )
            let cont = json["continuationContents"] as? [String: Any]
            let sectionListCont = cont?["sectionListContinuation"] as? [String: Any]
            let contents = sectionListCont?["contents"] as? [[String: Any]] ?? []
            let sections = contents.compactMap { parseCarouselSection($0["musicCarouselShelfRenderer"] as? [String: Any]) }
            let nextCont = extractContinuation(from: sectionListCont?["continuations"] as? [[String: Any]])
            return BrowseResult(title: "Home", sections: sections, continuation: nextCont)
        }

        var body: [String: Any] = ["browseId": "FEmusic_home"]
        if let params { body["params"] = params }
        let json = try await performInnerTubeRequest(endpoint: "browse", client: .webRemix, body: body)
        return parseBrowsePage(json: json, defaultTitle: "Home")
    }

    func fetchExploreFeed() async throws -> BrowseResult {
        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: ["browseId": "FEmusic_explore"]
        )
        return parseBrowsePage(json: json, defaultTitle: "Explore")
    }

    func fetchCharts() async throws -> BrowseResult {
        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: [
                "browseId": "FEmusic_charts",
                "params": "ggMGCgQIgAQ="
            ]
        )
        return parseBrowsePage(json: json, defaultTitle: "Charts")
    }

    func fetchMoodsAndGenres() async throws -> [MoodAndGenreItem] {
        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: ["browseId": "FEmusic_moods_and_genres"]
        )

        let sectionContents = extractPrimarySectionContents(from: json)
        var items: [MoodAndGenreItem] = []

        for content in sectionContents {
            if let grid = content["gridRenderer"] as? [String: Any],
               let gridItems = grid["items"] as? [[String: Any]] {
                for gridItem in gridItems {
                    if let navButton = gridItem["musicNavigationButtonRenderer"] as? [String: Any],
                       let parsed = parseMoodAndGenreButton(navButton) {
                        items.append(parsed)
                    }
                }
            } else if let carousel = content["musicCarouselShelfRenderer"] as? [String: Any],
                      let carouselItems = carousel["contents"] as? [[String: Any]] {
                for cItem in carouselItems {
                    if let navButton = cItem["musicNavigationButtonRenderer"] as? [String: Any],
                       let parsed = parseMoodAndGenreButton(navButton) {
                        items.append(parsed)
                    }
                }
            }
        }
        return items
    }

    func fetchNewReleases() async throws -> [Album] {
        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: ["browseId": "FEmusic_new_releases_albums"]
        )

        let sectionContents = extractPrimarySectionContents(from: json)
        var albums: [Album] = []
        for content in sectionContents {
            if let grid = content["gridRenderer"] as? [String: Any],
               let gridItems = grid["items"] as? [[String: Any]] {
                for gridItem in gridItems {
                    if let twoRow = gridItem["musicTwoRowItemRenderer"] as? [String: Any],
                       let album = parseAlbum(fromTwoRow: twoRow) {
                        albums.append(album)
                    }
                }
            }
        }
        return albums
    }

    func fetchBrowse(browseId: String, params: String? = nil, continuation: String? = nil) async throws -> BrowseResult {
        if let continuation, !continuation.isEmpty {
            let json = try await performInnerTubeRequest(
                endpoint: "browse",
                client: .webRemix,
                queryItems: [
                    URLQueryItem(name: "continuation", value: continuation),
                    URLQueryItem(name: "ctoken", value: continuation)
                ],
                body: ["continuation": continuation]
            )
            return parseBrowseContinuation(json: json)
        }

        var body: [String: Any] = ["browseId": browseId]
        if let params, !params.isEmpty {
            body["params"] = params
        }
        let json = try await performInnerTubeRequest(endpoint: "browse", client: .webRemix, body: body)
        return parseBrowsePage(json: json, defaultTitle: nil)
    }

    // MARK: - Album, Artist, Playlist

    func fetchAlbum(browseId: String) async throws -> Album {
        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: ["browseId": browseId]
        )

        let twoColumn = dig(json, path: ["contents", "twoColumnBrowseResultsRenderer"]) as? [String: Any]
        let tabs = twoColumn?["tabs"] as? [[String: Any]] ?? (dig(json, path: ["contents", "singleColumnBrowseResultsRenderer", "tabs"]) as? [[String: Any]] ?? [])
        let primaryContents = dig(tabs.first, path: ["tabRenderer", "content", "sectionListRenderer", "contents"]) as? [[String: Any]] ?? []

        let responsiveHeader = primaryContents.compactMap { $0["musicResponsiveHeaderRenderer"] as? [String: Any] }.first
        let detailHeader = dig(json, path: ["header", "musicDetailHeaderRenderer"]) as? [String: Any]

        let title = firstRunText(in: responsiveHeader?["title"])
            ?? firstRunText(in: detailHeader?["title"])
            ?? "Unknown Album"

        var artists: [Artist] = []
        if let strapRuns = dig(responsiveHeader, path: ["straplineTextOne", "runs"]) as? [[String: Any]] {
            artists = extractArtists(fromRuns: strapRuns)
        } else if let subtitleRuns = dig(detailHeader, path: ["subtitle", "runs"]) as? [[String: Any]] {
            artists = extractArtists(fromRuns: subtitleRuns)
        }

        let yearText = (dig(responsiveHeader, path: ["subtitle", "runs"]) as? [[String: Any]] ?? []).last?["text"] as? String
            ?? (dig(detailHeader, path: ["subtitle", "runs"]) as? [[String: Any]] ?? []).last?["text"] as? String
        let year = yearText.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        let thumbnailURL = extractBestThumbnail(from: dig(responsiveHeader, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            ?? extractBestThumbnail(from: dig(detailHeader, path: ["thumbnail", "croppedSquareThumbnailRenderer", "thumbnail", "thumbnails"]))

        let description = extractRunsText(dig(responsiveHeader, path: ["description", "runs"]))
            ?? extractRunsText(dig(detailHeader, path: ["description", "runs"]))

        let canonicalURL = dig(json, path: ["microformat", "microformatDataRenderer", "urlCanonical"]) as? String
        let playlistId = canonicalURL?.components(separatedBy: "=").last

        var tracks: [Track] = []
        if let secondaryContents = dig(twoColumn, path: ["secondaryContents", "sectionListRenderer", "contents"]) as? [[String: Any]] {
            for content in secondaryContents {
                if let playlistShelf = content["musicPlaylistShelfRenderer"] as? [String: Any],
                   let rawTracks = playlistShelf["contents"] as? [[String: Any]] {
                    for item in rawTracks {
                        if let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
                           var track = parseTrack(fromResponsive: renderer) {
                            if track.artists.isEmpty { track.artists = artists }
                            if track.thumbnailURL == nil { track.thumbnailURL = thumbnailURL }
                            if track.album == nil {
                                track.album = Album(id: browseId, name: title, artists: artists, year: year, thumbnailURL: thumbnailURL)
                            }
                            tracks.append(track)
                        }
                    }
                }
            }
        }

        if tracks.isEmpty, let playlistId, !playlistId.isEmpty {
            let playlistResult = try? await fetchPlaylist(browseId: "VL\(playlistId)")
            if let fetchedTracks = playlistResult?.tracks, !fetchedTracks.isEmpty {
                tracks = fetchedTracks.map { t in
                    var copy = t
                    if copy.artists.isEmpty { copy.artists = artists }
                    if copy.thumbnailURL == nil { copy.thumbnailURL = thumbnailURL }
                    if copy.album == nil {
                        copy.album = Album(id: browseId, name: title, artists: artists, year: year, thumbnailURL: thumbnailURL)
                    }
                    return copy
                }
            }
        }

        return Album(
            id: browseId,
            name: title,
            artists: artists,
            year: year,
            thumbnailURL: thumbnailURL,
            tracks: tracks,
            browseId: browseId,
            playlistId: playlistId,
            songCount: tracks.count,
            duration: tracks.compactMap(\.durationSeconds).reduce(0, +),
            description: description
        )
    }

    func fetchArtist(browseId: String) async throws -> ArtistDetailResult {
        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: ["browseId": browseId]
        )

        let header = json["header"] as? [String: Any]
        let immersive = header?["musicImmersiveHeaderRenderer"] as? [String: Any]
        let visual = header?["musicVisualHeaderRenderer"] as? [String: Any]
        let plainHeader = header?["musicHeaderRenderer"] as? [String: Any]

        let name = firstRunText(in: immersive?["title"])
            ?? firstRunText(in: visual?["title"])
            ?? firstRunText(in: plainHeader?["title"])
            ?? "Unknown Artist"

        let thumbnailURL = extractBestThumbnail(from: dig(immersive, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            ?? extractBestThumbnail(from: dig(visual, path: ["foregroundThumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            ?? extractBestThumbnail(from: dig(visual, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))

        let subButton = dig(immersive, path: ["subscriptionButton", "subscribeButtonRenderer"]) as? [String: Any]
            ?? dig(immersive, path: ["subscriptionButton2", "subscribeButtonRenderer"]) as? [String: Any]
        let channelId = subButton?["channelId"] as? String
        let subscriberCount = firstRunText(in: subButton?["subscriberCountWithSubscribeText"])
            ?? firstRunText(in: subButton?["longSubscriberCountText"])
            ?? firstRunText(in: subButton?["shortSubscriberCountText"])
        let monthlyListeners = firstRunText(in: immersive?["monthlyListenerCount"])
        let description = extractRunsText(dig(immersive, path: ["description", "runs"]))

        let sectionContents = extractPrimarySectionContents(from: json)

        var topSongs: [Track] = []
        var albums: [Album] = []
        var singles: [Album] = []
        var videos: [Track] = []
        var playlists: [YouTubePlaylist] = []
        var relatedArtists: [Artist] = []
        var sections: [HomeSection] = []
        var sectionDescription: String?

        let artistObj = Artist(
            id: browseId,
            name: name,
            thumbnailURL: thumbnailURL,
            subscriberCount: subscriberCount,
            browseId: browseId,
            channelId: channelId
        )

        for content in sectionContents {
            if let descShelf = content["musicDescriptionShelfRenderer"] as? [String: Any] {
                sectionDescription = extractRunsText(dig(descShelf, path: ["description", "runs"]))
            } else if let shelf = content["musicShelfRenderer"] as? [String: Any] {
                let sectionTitle = firstRunText(in: shelf["title"]) ?? "Songs"
                let browseEndpoint = dig(shelf, path: ["bottomEndpoint", "browseEndpoint"]) as? [String: Any]
                let rawItems = shelf["contents"] as? [[String: Any]] ?? []
                var sectionItems: [HomeSectionItem] = []

                for raw in rawItems {
                    if let renderer = raw["musicResponsiveListItemRenderer"] as? [String: Any],
                       var track = parseTrack(fromResponsive: renderer) {
                        if track.artists.isEmpty { track.artists = [artistObj] }
                        topSongs.append(track)
                        sectionItems.append(.track(track))
                    }
                }
                if !sectionItems.isEmpty {
                    sections.append(HomeSection(
                        title: sectionTitle,
                        items: sectionItems,
                        browseId: browseEndpoint?["browseId"] as? String,
                        params: browseEndpoint?["params"] as? String
                    ))
                }
            } else if let carousel = content["musicCarouselShelfRenderer"] as? [String: Any],
                      let section = parseCarouselSection(carousel) {
                sections.append(section)
                let lowerTitle = section.title.lowercased()
                for item in section.items {
                    switch item {
                    case .album(let album):
                        if lowerTitle.contains("single") || lowerTitle.contains("ep") {
                            singles.append(album)
                        } else {
                            albums.append(album)
                        }
                    case .track(let track):
                        if track.isVideo || lowerTitle.contains("video") {
                            videos.append(track)
                        } else {
                            topSongs.append(track)
                        }
                    case .artist(let relArtist):
                        relatedArtists.append(relArtist)
                    case .playlist(let playlist):
                        playlists.append(playlist)
                    }
                }
            }
        }

        return ArtistDetailResult(
            artist: artistObj,
            description: description ?? sectionDescription,
            monthlyListeners: monthlyListeners,
            topSongs: topSongs,
            albums: albums,
            singles: singles,
            videos: videos,
            playlists: playlists,
            relatedArtists: relatedArtists,
            sections: sections
        )
    }

    func fetchPlaylist(browseId: String, loadAllContinuations: Bool = true) async throws -> YouTubePlaylist {
        let normalizedBrowseId = browseId.hasPrefix("VL") ? browseId : "VL\(browseId)"
        let cleanId = String(normalizedBrowseId.dropFirst(2))

        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: ["browseId": normalizedBrowseId]
        )

        let twoColumn = dig(json, path: ["contents", "twoColumnBrowseResultsRenderer"]) as? [String: Any]
        let tabs = twoColumn?["tabs"] as? [[String: Any]] ?? (dig(json, path: ["contents", "singleColumnBrowseResultsRenderer", "tabs"]) as? [[String: Any]] ?? [])
        let baseContent = (dig(tabs.first, path: ["tabRenderer", "content", "sectionListRenderer", "contents"]) as? [[String: Any]] ?? []).first

        let header = baseContent?["musicResponsiveHeaderRenderer"] as? [String: Any]
            ?? dig(baseContent, path: ["musicEditablePlaylistDetailHeaderRenderer", "header", "musicResponsiveHeaderRenderer"]) as? [String: Any]
            ?? dig(json, path: ["header", "musicDetailHeaderRenderer"]) as? [String: Any]

        let title = firstRunText(in: header?["title"]) ?? cleanId
        let author = firstRunText(in: header?["straplineTextOne"]) ?? firstRunText(in: header?["subtitle"])
        let thumbnailURL = extractBestThumbnail(from: dig(header, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            ?? extractBestThumbnail(from: dig(header, path: ["thumbnail", "croppedSquareThumbnailRenderer", "thumbnail", "thumbnails"]))
        let description = extractRunsText(dig(header, path: ["description", "runs"]))

        let secondaryContents = dig(twoColumn, path: ["secondaryContents", "sectionListRenderer", "contents"]) as? [[String: Any]]
        let singleContents = dig(tabs.first, path: ["tabRenderer", "content", "sectionListRenderer", "contents"]) as? [[String: Any]]
        let playlistShelf = (secondaryContents ?? singleContents ?? []).compactMap { $0["musicPlaylistShelfRenderer"] as? [String: Any] }.first
            ?? (secondaryContents ?? singleContents ?? []).compactMap { $0["musicShelfRenderer"] as? [String: Any] }.first

        var tracks = (playlistShelf?["contents"] as? [[String: Any]] ?? []).compactMap {
            parseTrack(fromResponsive: $0["musicResponsiveListItemRenderer"] as? [String: Any])
        }

        var continuation = extractContinuation(from: playlistShelf?["continuations"] as? [[String: Any]])
            ?? extractContinuationFromItems(playlistShelf?["contents"] as? [[String: Any]])

        if loadAllContinuations {
            var seenTokens = Set<String>()
            var pageCount = 0
            while let token = continuation, !seenTokens.contains(token), pageCount < 25 {
                seenTokens.insert(token)
                pageCount += 1
                let page = try await fetchPlaylistContinuation(continuation: token)
                tracks.append(contentsOf: page.tracks)
                continuation = page.continuation
            }
        }

        return YouTubePlaylist(
            id: cleanId,
            name: title,
            tracks: tracks,
            thumbnailURL: thumbnailURL,
            author: author,
            songCount: tracks.count,
            description: description
        )
    }

    func fetchPlaylistContinuation(continuation: String) async throws -> (tracks: [Track], continuation: String?) {
        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            queryItems: [
                URLQueryItem(name: "continuation", value: continuation),
                URLQueryItem(name: "ctoken", value: continuation)
            ],
            body: ["continuation": continuation]
        )

        var rawContents: [[String: Any]] = []
        if let playlistShelfCont = dig(json, path: ["continuationContents", "musicPlaylistShelfContinuation", "contents"]) as? [[String: Any]] {
            rawContents.append(contentsOf: playlistShelfCont)
        }
        if let shelfCont = dig(json, path: ["continuationContents", "musicShelfContinuation", "contents"]) as? [[String: Any]] {
            rawContents.append(contentsOf: shelfCont)
        }
        if let actions = json["onResponseReceivedActions"] as? [[String: Any]] {
            for action in actions {
                if let items = dig(action, path: ["appendContinuationItemsAction", "continuationItems"]) as? [[String: Any]] {
                    rawContents.append(contentsOf: items)
                }
            }
        }

        let tracks = rawContents.compactMap { parseTrack(fromResponsive: $0["musicResponsiveListItemRenderer"] as? [String: Any]) }
        let nextToken = tracks.isEmpty ? nil : (
            extractContinuation(from: dig(json, path: ["continuationContents", "musicPlaylistShelfContinuation", "continuations"]) as? [[String: Any]])
            ?? extractContinuation(from: dig(json, path: ["continuationContents", "musicShelfContinuation", "continuations"]) as? [[String: Any]])
            ?? extractContinuationFromItems(rawContents)
        )
        return (tracks, nextToken)
    }

    // MARK: - Up Next / Radio / History / Related

    func fetchUpNext(videoId: String, playlistId: String? = nil) async throws -> [Track] {
        let targetPlaylistId = playlistId ?? "RDAMVM\(videoId)"
        let json = try await performInnerTubeRequest(
            endpoint: "next",
            client: .webRemix,
            body: [
                "videoId": videoId,
                "playlistId": targetPlaylistId,
                "isAudioOnly": true
            ]
        )

        let tabs = dig(json, path: ["contents", "singleColumnMusicWatchNextResultsRenderer", "tabbedRenderer", "watchNextTabbedResultsRenderer", "tabs"]) as? [[String: Any]] ?? []
        let panelContents = dig(tabs.first, path: ["tabRenderer", "content", "musicQueueRenderer", "content", "playlistPanelRenderer", "contents"]) as? [[String: Any]] ?? []

        var tracks = panelContents.compactMap { parseTrack(fromPlaylistPanel: $0["playlistPanelVideoRenderer"] as? [String: Any]) }

        if tracks.isEmpty,
           let automixEndpoint = panelContents.last.flatMap({ dig($0, path: ["automixPreviewVideoRenderer", "content", "automixPlaylistVideoRenderer", "navigationEndpoint", "watchPlaylistEndpoint"]) as? [String: Any] }),
           let autoPlaylistId = automixEndpoint["playlistId"] as? String {
            let autoJSON = try await performInnerTubeRequest(
                endpoint: "next",
                client: .webRemix,
                body: [
                    "playlistId": autoPlaylistId,
                    "params": automixEndpoint["params"] as? String ?? "wAEB"
                ]
            )
            let autoTabs = dig(autoJSON, path: ["contents", "singleColumnMusicWatchNextResultsRenderer", "tabbedRenderer", "watchNextTabbedResultsRenderer", "tabs"]) as? [[String: Any]] ?? []
            let autoPanel = dig(autoTabs.first, path: ["tabRenderer", "content", "musicQueueRenderer", "content", "playlistPanelRenderer", "contents"]) as? [[String: Any]] ?? []
            tracks = autoPanel.compactMap { parseTrack(fromPlaylistPanel: $0["playlistPanelVideoRenderer"] as? [String: Any]) }
        }

        return tracks
    }

    func fetchHistory() async throws -> [HomeSection] {
        let json = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: ["browseId": "FEmusic_history"]
        )
        let sectionContents = extractPrimarySectionContents(from: json)
        var sections: [HomeSection] = []
        for content in sectionContents {
            if let shelf = content["musicShelfRenderer"] as? [String: Any] {
                let title = firstRunText(in: shelf["title"]) ?? "History"
                let items = (shelf["contents"] as? [[String: Any]] ?? []).compactMap {
                    parseHomeSectionItem(fromResponsive: $0["musicResponsiveListItemRenderer"] as? [String: Any])
                }
                if !items.isEmpty {
                    sections.append(HomeSection(title: title, items: items))
                }
            }
        }
        return sections
    }

    func fetchYouTubeLyrics(videoId: String) async throws -> String? {
        let nextJSON = try await performInnerTubeRequest(
            endpoint: "next",
            client: .webRemix,
            body: ["videoId": videoId]
        )
        let tabs = dig(nextJSON, path: ["contents", "singleColumnMusicWatchNextResultsRenderer", "tabbedRenderer", "watchNextTabbedResultsRenderer", "tabs"]) as? [[String: Any]] ?? []
        guard tabs.count > 1,
              let browseId = dig(tabs[1], path: ["tabRenderer", "endpoint", "browseEndpoint", "browseId"]) as? String else {
            return nil
        }

        let browseJSON = try await performInnerTubeRequest(
            endpoint: "browse",
            client: .webRemix,
            body: ["browseId": browseId]
        )
        let sectionContents = dig(browseJSON, path: ["contents", "sectionListRenderer", "contents"]) as? [[String: Any]] ?? []
        for content in sectionContents {
            if let descShelf = content["musicDescriptionShelfRenderer"] as? [String: Any],
               let text = extractRunsText(dig(descShelf, path: ["description", "runs"])),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    func fetchYouTubeCaptionsLRC(videoId: String) async throws -> String? {
        for client in [ClientProfile.ios, ClientProfile.androidVR] {
            guard let playerJSON = try? await requestPlayer(videoId: videoId, client: client),
                  let captionTracks = dig(playerJSON, path: ["captions", "playerCaptionsTracklistRenderer", "captionTracks"]) as? [[String: Any]],
                  let chosen = captionTracks.first(where: { ($0["kind"] as? String) != "asr" }) ?? captionTracks.first,
                  let baseUrlString = chosen["baseUrl"] as? String,
                  var components = URLComponents(string: baseUrlString) else {
                continue
            }

            var items = components.queryItems ?? []
            items.removeAll { $0.name == "fmt" }
            items.append(URLQueryItem(name: "fmt", value: "json3"))
            components.queryItems = items
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await session.data(for: request)
            if let parsed = parseTimedTextJSON3ToLRC(data) {
                return parsed
            }
        }
        return nil
    }

    // MARK: - Stream Resolution

    func resolveStream(videoId: String, quality: StreamQuality = AppSettings.shared.audioQuality) async throws -> ResolvedStream {
        if AppSettings.shared.offlineMode {
            throw InnerTubeError.offlineMode
        }

        let clients: [ClientProfile] = [.ios, .visionOS, .androidVR, .ipados]
        var lastError: Error = InnerTubeError.noPlayableStream

        for client in clients {
            do {
                let playerJSON = try await requestPlayer(videoId: videoId, client: client)

                if let playability = playerJSON["playabilityStatus"] as? [String: Any],
                   let status = playability["status"] as? String,
                   status != "OK" {
                    let reason = playability["reason"] as? String
                    lastError = InnerTubeError.playabilityError(status: status, reason: reason)
                    continue
                }

                guard let streamingData = playerJSON["streamingData"] as? [String: Any] else {
                    lastError = InnerTubeError.noPlayableStream
                    continue
                }

                let loudnessDb = (dig(playerJSON, path: ["playerConfig", "audioConfig", "loudnessDb"]) as? Double)
                    ?? (dig(playerJSON, path: ["playerConfig", "audioConfig", "perceptualLoudnessDb"]) as? Double)

                let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []
                let legacyFormats = streamingData["formats"] as? [[String: Any]] ?? []

                // AVPlayer on iOS natively supports audio/mp4 (AAC / ALAC / FLAC in MP4), not WebM/Opus.
                let audioMP4Formats = adaptiveFormats.filter { format in
                    guard let mime = (format["mimeType"] as? String)?.lowercased(),
                          let urlStr = format["url"] as? String, !urlStr.isEmpty else {
                        return false
                    }
                    let isAudio = mime.hasPrefix("audio/") && format["width"] == nil
                    let isAppleCompatible = mime.contains("audio/mp4") || mime.contains("mp4a")
                    return isAudio && isAppleCompatible
                }

                if let selected = selectBestFormat(from: audioMP4Formats, quality: quality),
                   let urlString = selected["url"] as? String,
                   let streamURL = URL(string: urlString) {
                    let itag = selected["itag"] as? Int ?? 140
                    let mimeType = selected["mimeType"] as? String ?? "audio/mp4"
                    let bitrate = selected["bitrate"] as? Int ?? 128_000
                    let sampleRate = (selected["audioSampleRate"] as? String).flatMap(Int.init) ?? (selected["audioSampleRate"] as? Int)
                    let contentLength = (selected["contentLength"] as? String).flatMap(Int64.init) ?? (selected["contentLength"] as? Int64) ?? 0
                    let formatLoudness = (selected["loudnessDb"] as? Double) ?? loudnessDb
                    let codecs = extractCodecs(from: mimeType)

                    return ResolvedStream(
                        url: streamURL,
                        userAgent: client.userAgent,
                        isAudioOnly: true,
                        itag: itag,
                        mimeType: mimeType.components(separatedBy: ";").first ?? "audio/mp4",
                        codecs: codecs,
                        bitrate: bitrate,
                        sampleRate: sampleRate,
                        contentLength: contentLength,
                        loudnessDb: formatLoudness
                    )
                }

                // Fallback 1: HLS manifest (native AVPlayer support, great on IOS/VISIONOS)
                if let hlsUrlStr = streamingData["hlsManifestUrl"] as? String,
                   let hlsURL = URL(string: hlsUrlStr) {
                    return ResolvedStream(
                        url: hlsURL,
                        userAgent: client.userAgent,
                        isAudioOnly: false,
                        itag: 91,
                        mimeType: "application/x-mpegURL",
                        codecs: "mp4a.40.2",
                        bitrate: 128_000,
                        sampleRate: 44100,
                        contentLength: 0,
                        loudnessDb: loudnessDb
                    )
                }

                // Fallback 2: Muxed MP4 format
                let muxedMP4 = legacyFormats.filter { format in
                    guard let mime = (format["mimeType"] as? String)?.lowercased(),
                          let urlStr = format["url"] as? String, !urlStr.isEmpty else {
                        return false
                    }
                    return mime.contains("video/mp4")
                }

                if let selected = muxedMP4.max(by: { ($0["bitrate"] as? Int ?? 0) < ($1["bitrate"] as? Int ?? 0) }),
                   let urlString = selected["url"] as? String,
                   let streamURL = URL(string: urlString) {
                    return ResolvedStream(
                        url: streamURL,
                        userAgent: client.userAgent,
                        isAudioOnly: false,
                        itag: selected["itag"] as? Int ?? 18,
                        mimeType: "video/mp4",
                        codecs: "mp4a.40.2",
                        bitrate: selected["bitrate"] as? Int ?? 128_000,
                        sampleRate: 44100,
                        contentLength: (selected["contentLength"] as? String).flatMap(Int64.init) ?? 0,
                        loudnessDb: loudnessDb
                    )
                }
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func requestPlayer(videoId: String, client: ClientProfile) async throws -> [String: Any] {
        let visitor = await visitorId(for: client)
        guard let url = URL(string: "\(client.apiOrigin)/youtubei/v1/player?prettyPrint=false") else {
            throw InnerTubeError.invalidURL
        }
        let body: [String: Any] = [
            "context": client.contextPayload(gl: currentGL, hl: currentHL, visitorData: visitor, dataSyncId: dataSyncId),
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        return try await postJSON(url: url, client: client, body: body, visitorOverride: visitor)
    }

    private func selectBestFormat(from formats: [[String: Any]], quality: StreamQuality) -> [String: Any]? {
        guard !formats.isEmpty else { return nil }
        let sorted = formats.sorted {
            ($0["bitrate"] as? Int ?? 0) < ($1["bitrate"] as? Int ?? 0)
        }
        switch quality {
        case .low:
            return sorted.first(where: { ($0["bitrate"] as? Int ?? 0) >= 48_000 }) ?? sorted.first
        case .medium:
            return sorted.min(by: {
                abs(($0["bitrate"] as? Int ?? 0) - 128_000) < abs(($1["bitrate"] as? Int ?? 0) - 128_000)
            })
        case .auto, .high, .lossless, .hiResLossless, .dolbyAtmos:
            return sorted.last
        }
    }

    private func extractCodecs(from mimeType: String) -> String {
        guard let range = mimeType.range(of: "codecs=\"") else { return "mp4a.40.2" }
        let after = mimeType[range.upperBound...]
        if let end = after.firstIndex(of: "\"") {
            return String(after[..<end])
        }
        return "mp4a.40.2"
    }

    // MARK: - HTTP Core with Exponential Backoff

    private func performInnerTubeRequest(
        endpoint: String,
        client: ClientProfile,
        queryItems: [URLQueryItem] = [],
        body: [String: Any]
    ) async throws -> [String: Any] {
        if AppSettings.shared.offlineMode {
            throw InnerTubeError.offlineMode
        }

        var components = URLComponents(string: "\(client.apiOrigin)/youtubei/v1/\(endpoint)")
        var items = [URLQueryItem(name: "prettyPrint", value: "false")]
        items.append(contentsOf: queryItems)
        components?.queryItems = items

        guard let url = components?.url else {
            throw InnerTubeError.invalidURL
        }

        let visitor = await visitorId(for: client)
        var fullBody = body
        fullBody["context"] = client.contextPayload(
            gl: currentGL,
            hl: currentHL,
            visitorData: visitor,
            dataSyncId: dataSyncId
        )

        return try await postJSON(url: url, client: client, body: fullBody, visitorOverride: visitor)
    }

    private func postJSON(
        url: URL,
        client: ClientProfile,
        body: [String: Any],
        visitorOverride: String?
    ) async throws -> [String: Any] {
        let dataBody = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dataBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(client.apiFormatVersion, forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue(client.clientId, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")

        if !client.isNativeApp {
            request.setValue(client.apiOrigin, forHTTPHeaderField: "X-Origin")
            request.setValue("\(client.apiOrigin)/", forHTTPHeaderField: "Referer")
        }

        if let visitor = visitorOverride, !visitor.isEmpty {
            request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        if client.loginSupported, let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            if let authHeader = sapisidAuthHeader(cookie: cookie, origin: client.apiOrigin) {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
        }

        return try await withRetry(maxAttempts: 3, initialDelay: 0.5) {
            let (data, response) = try await self.session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let msg = String(data: data, encoding: .utf8)
                throw InnerTubeError.httpError(httpResponse.statusCode, msg)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InnerTubeError.decodingError("Top-level JSON is not a dictionary")
            }
            return json
        }
    }

    private func withRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 0.5,
        block: () async throws -> T
    ) async throws -> T {
        var delay = initialDelay
        var attempt = 0
        while true {
            do {
                return try await block()
            } catch let error as InnerTubeError {
                if case .httpError(let code, _) = error, code < 500 && code != 429 {
                    throw error
                }
                attempt += 1
                if attempt >= maxAttempts { throw error }
            } catch {
                attempt += 1
                if attempt >= maxAttempts { throw InnerTubeError.networkError(error) }
            }
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay *= 2.0
        }
    }

    private func sapisidAuthHeader(cookie: String, origin: String) -> String? {
        let pairs = cookie.split(separator: ";").compactMap { part -> (String, String)? in
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            return (kv[0].trimmingCharacters(in: .whitespaces), kv[1].trimmingCharacters(in: .whitespaces))
        }
        let dict = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        guard let sapisid = dict["SAPISID"] ?? dict["__Secure-3PAPISID"] else { return nil }
        let ts = Int(Date().timeIntervalSince1970)
        let input = "\(ts) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(ts)_\(hex)"
    }

    // MARK: - Page & Renderer Parsing

    private func parseBrowsePage(json: [String: Any], defaultTitle: String?) -> BrowseResult {
        let title = firstRunText(in: dig(json, path: ["header", "musicHeaderRenderer", "title"]))
            ?? firstRunText(in: dig(json, path: ["header", "musicDetailHeaderRenderer", "title"]))
            ?? defaultTitle

        let sectionList = dig(json, path: ["contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer"]) as? [String: Any]
            ?? dig(json, path: ["contents", "twoColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer"]) as? [String: Any]

        let contents = sectionList?["contents"] as? [[String: Any]] ?? []
        var sections: [HomeSection] = []

        for content in contents {
            if let carousel = content["musicCarouselShelfRenderer"] as? [String: Any],
               let section = parseCarouselSection(carousel) {
                sections.append(section)
            } else if let grid = content["gridRenderer"] as? [String: Any],
                      let section = parseGridSection(grid) {
                sections.append(section)
            } else if let shelf = content["musicShelfRenderer"] as? [String: Any] {
                let sTitle = firstRunText(in: shelf["title"]) ?? defaultTitle ?? "Results"
                let items = (shelf["contents"] as? [[String: Any]] ?? []).compactMap {
                    parseHomeSectionItem(fromResponsive: $0["musicResponsiveListItemRenderer"] as? [String: Any])
                }
                if !items.isEmpty {
                    sections.append(HomeSection(title: sTitle, items: items))
                }
            }
        }

        let continuation = extractContinuation(from: sectionList?["continuations"] as? [[String: Any]])
        return BrowseResult(title: title, sections: sections, continuation: continuation)
    }

    private func parseBrowseContinuation(json: [String: Any]) -> BrowseResult {
        let sectionListCont = dig(json, path: ["continuationContents", "sectionListContinuation"]) as? [String: Any]
        let contents = sectionListCont?["contents"] as? [[String: Any]] ?? []
        var sections: [HomeSection] = []
        for content in contents {
            if let carousel = content["musicCarouselShelfRenderer"] as? [String: Any],
               let section = parseCarouselSection(carousel) {
                sections.append(section)
            } else if let grid = content["gridRenderer"] as? [String: Any],
                      let section = parseGridSection(grid) {
                sections.append(section)
            }
        }
        let nextCont = extractContinuation(from: sectionListCont?["continuations"] as? [[String: Any]])
        return BrowseResult(title: nil, sections: sections, continuation: nextCont)
    }

    private func parseCarouselSection(_ renderer: [String: Any]?) -> HomeSection? {
        guard let renderer else { return nil }
        let header = dig(renderer, path: ["header", "musicCarouselShelfBasicHeaderRenderer"]) as? [String: Any]
        let title = firstRunText(in: header?["title"]) ?? "Recommended"
        let subtitle = firstRunText(in: header?["strapline"])
        let moreBrowse = dig(header, path: ["moreContentButton", "buttonRenderer", "navigationEndpoint", "browseEndpoint"]) as? [String: Any]

        let rawItems = renderer["contents"] as? [[String: Any]] ?? []
        let items: [HomeSectionItem] = rawItems.compactMap { entry in
            if let twoRow = entry["musicTwoRowItemRenderer"] as? [String: Any] {
                return parseHomeSectionItem(fromTwoRow: twoRow)
            }
            if let responsive = entry["musicResponsiveListItemRenderer"] as? [String: Any] {
                return parseHomeSectionItem(fromResponsive: responsive)
            }
            return nil
        }

        guard !items.isEmpty else { return nil }
        return HomeSection(
            title: title,
            subtitle: subtitle,
            items: items,
            browseId: moreBrowse?["browseId"] as? String,
            params: moreBrowse?["params"] as? String
        )
    }

    private func parseGridSection(_ renderer: [String: Any]) -> HomeSection? {
        let title = firstRunText(in: dig(renderer, path: ["header", "gridHeaderRenderer", "title"])) ?? "Browse"
        let rawItems = renderer["items"] as? [[String: Any]] ?? []
        let items: [HomeSectionItem] = rawItems.compactMap { entry in
            if let twoRow = entry["musicTwoRowItemRenderer"] as? [String: Any] {
                return parseHomeSectionItem(fromTwoRow: twoRow)
            }
            if let responsive = entry["musicResponsiveListItemRenderer"] as? [String: Any] {
                return parseHomeSectionItem(fromResponsive: responsive)
            }
            return nil
        }
        guard !items.isEmpty else { return nil }
        let cont = extractContinuation(from: renderer["continuations"] as? [[String: Any]])
        return HomeSection(title: title, items: items, continuation: cont)
    }

    private func parseMoodAndGenreButton(_ renderer: [String: Any]) -> MoodAndGenreItem? {
        guard let title = firstRunText(in: renderer["buttonText"]),
              let browseEndpoint = dig(renderer, path: ["clickCommand", "browseEndpoint"]) as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String else {
            return nil
        }
        let params = browseEndpoint["params"] as? String
        let stripeColorInt = dig(renderer, path: ["colorStyle", "leftStripeColor"]) as? UInt32
            ?? (dig(renderer, path: ["colorStyle", "leftStripeColor"]) as? Int).map { UInt32(bitPattern: Int32(truncatingIfNeeded: $0)) }
        return MoodAndGenreItem(
            title: title,
            browseId: browseId,
            params: params,
            stripeColorHex: stripeColorInt
        )
    }

    private func parseSearchItem(from renderer: [String: Any]?) -> SearchResultItem? {
        guard let homeItem = parseHomeSectionItem(fromResponsive: renderer) else { return nil }
        switch homeItem {
        case .track(let track): return .track(track)
        case .album(let album): return .album(album)
        case .artist(let artist): return .artist(artist)
        case .playlist(let playlist): return .playlist(playlist)
        }
    }

    private func parseCardShelfTopItem(_ cardShelf: [String: Any]) -> HomeSectionItem? {
        let title = firstRunText(in: cardShelf["title"]) ?? ""
        guard !title.isEmpty else { return nil }
        let thumbnail = extractBestThumbnail(from: dig(cardShelf, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        let onTap = cardShelf["onTap"] as? [String: Any]

        if let watchEndpoint = onTap?["watchEndpoint"] as? [String: Any],
           let videoId = watchEndpoint["videoId"] as? String {
            let subtitleRuns = dig(cardShelf, path: ["subtitle", "runs"]) as? [[String: Any]] ?? []
            let artists = extractArtists(fromRuns: subtitleRuns)
            let duration = extractDuration(fromRuns: subtitleRuns)
            let track = Track(
                id: videoId,
                title: title,
                artists: artists,
                durationSeconds: duration,
                thumbnailURL: thumbnail
            )
            return .track(track)
        }

        if let browseEndpoint = onTap?["browseEndpoint"] as? [String: Any],
           let browseId = browseEndpoint["browseId"] as? String {
            let pageType = dig(browseEndpoint, path: ["browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"]) as? String
            if pageType == "MUSIC_PAGE_TYPE_ARTIST" || browseId.hasPrefix("UC") {
                return .artist(Artist(id: browseId, name: title, thumbnailURL: thumbnail, browseId: browseId))
            } else if pageType == "MUSIC_PAGE_TYPE_ALBUM" || browseId.hasPrefix("MPREb_") {
                let subtitleRuns = dig(cardShelf, path: ["subtitle", "runs"]) as? [[String: Any]] ?? []
                return .album(Album(id: browseId, name: title, artists: extractArtists(fromRuns: subtitleRuns), thumbnailURL: thumbnail))
            } else {
                return .playlist(YouTubePlaylist(id: browseId, name: title, thumbnailURL: thumbnail))
            }
        }
        return nil
    }

    private func parseHomeSectionItem(fromResponsive renderer: [String: Any]?) -> HomeSectionItem? {
        guard let renderer else { return nil }
        let navEndpoint = renderer["navigationEndpoint"] as? [String: Any]
        let pageType = dig(navEndpoint, path: ["browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"]) as? String
        let browseId = dig(navEndpoint, path: ["browseEndpoint", "browseId"]) as? String

        if pageType == "MUSIC_PAGE_TYPE_ARTIST" || pageType == "MUSIC_PAGE_TYPE_USER_CHANNEL" {
            if let artist = parseArtist(fromResponsive: renderer) {
                return .artist(artist)
            }
        } else if pageType == "MUSIC_PAGE_TYPE_ALBUM" || pageType == "MUSIC_PAGE_TYPE_AUDIOBOOK" {
            if let album = parseAlbum(fromResponsive: renderer) {
                return .album(album)
            }
        } else if pageType == "MUSIC_PAGE_TYPE_PLAYLIST" || (browseId?.hasPrefix("VL") == true) {
            if let playlist = parsePlaylist(fromResponsive: renderer) {
                return .playlist(playlist)
            }
        }

        if let track = parseTrack(fromResponsive: renderer) {
            return .track(track)
        }
        if let album = parseAlbum(fromResponsive: renderer) {
            return .album(album)
        }
        if let playlist = parsePlaylist(fromResponsive: renderer) {
            return .playlist(playlist)
        }
        if let artist = parseArtist(fromResponsive: renderer) {
            return .artist(artist)
        }
        return nil
    }

    private func parseHomeSectionItem(fromTwoRow renderer: [String: Any]) -> HomeSectionItem? {
        let navEndpoint = renderer["navigationEndpoint"] as? [String: Any]
        if dig(navEndpoint, path: ["watchEndpoint", "videoId"]) != nil {
            if let track = parseTrack(fromTwoRow: renderer) {
                return .track(track)
            }
        }

        let pageType = dig(navEndpoint, path: ["browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"]) as? String
        let browseId = dig(navEndpoint, path: ["browseEndpoint", "browseId"]) as? String ?? ""

        if pageType == "MUSIC_PAGE_TYPE_ARTIST" || browseId.hasPrefix("UC") {
            if let artist = parseArtist(fromTwoRow: renderer) {
                return .artist(artist)
            }
        } else if pageType == "MUSIC_PAGE_TYPE_ALBUM" || browseId.hasPrefix("MPREb_") {
            if let album = parseAlbum(fromTwoRow: renderer) {
                return .album(album)
            }
        } else if pageType == "MUSIC_PAGE_TYPE_PLAYLIST" || browseId.hasPrefix("VL") || browseId.hasPrefix("RD") {
            if let playlist = parsePlaylist(fromTwoRow: renderer) {
                return .playlist(playlist)
            }
        }

        if let album = parseAlbum(fromTwoRow: renderer) {
            return .album(album)
        }
        if let playlist = parsePlaylist(fromTwoRow: renderer) {
            return .playlist(playlist)
        }
        return nil
    }

    // MARK: - Item Parsers

    func parseTrack(fromResponsive renderer: [String: Any]?) -> Track? {
        guard let renderer else { return nil }
        let flexColumns = renderer["flexColumns"] as? [[String: Any]] ?? []
        guard !flexColumns.isEmpty else { return nil }

        let col0Runs = dig(flexColumns[0], path: ["musicResponsiveListItemFlexColumnRenderer", "text", "runs"]) as? [[String: Any]] ?? []
        let title = col0Runs.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let videoId = (dig(renderer, path: ["playlistItemData", "videoId"]) as? String)
            ?? (dig(col0Runs.first, path: ["navigationEndpoint", "watchEndpoint", "videoId"]) as? String)
            ?? (dig(renderer, path: ["overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer", "playNavigationEndpoint", "watchEndpoint", "videoId"]) as? String)
            ?? (dig(renderer, path: ["navigationEndpoint", "watchEndpoint", "videoId"]) as? String)

        guard let videoId, !videoId.isEmpty else { return nil }

        let col1Runs = flexColumns.count > 1
            ? (dig(flexColumns[1], path: ["musicResponsiveListItemFlexColumnRenderer", "text", "runs"]) as? [[String: Any]] ?? [])
            : []
        let col2Runs = flexColumns.count > 2
            ? (dig(flexColumns[2], path: ["musicResponsiveListItemFlexColumnRenderer", "text", "runs"]) as? [[String: Any]] ?? [])
            : []

        let fixedColumns = renderer["fixedColumns"] as? [[String: Any]] ?? []
        let fixedRuns = dig(fixedColumns.first, path: ["musicResponsiveListItemFixedColumnRenderer", "text", "runs"]) as? [[String: Any]] ?? []

        let allSubtitleRuns = col1Runs + col2Runs
        var artists = extractArtists(fromRuns: allSubtitleRuns)
        if artists.isEmpty, let firstText = col1Runs.first?["text"] as? String,
           !firstText.isEmpty, parseDurationSeconds(firstText) == nil,
           !["Song", "Video", "Album", "EP", "Single"].contains(firstText) {
            artists = [Artist(name: firstText)]
        }

        let album = extractAlbum(fromRuns: allSubtitleRuns)
        let duration = extractDuration(fromRuns: fixedRuns)
            ?? extractDuration(fromRuns: col2Runs)
            ?? extractDuration(fromRuns: col1Runs)

        let thumbnailURL = extractBestThumbnail(from: dig(renderer, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        let explicit = hasExplicitBadge(renderer["badges"] as? [[String: Any]])

        let musicVideoType = dig(renderer, path: ["overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer", "playNavigationEndpoint", "watchEndpoint", "watchEndpointMusicSupportedConfigs", "watchEndpointMusicConfig", "musicVideoType"]) as? String
            ?? dig(col0Runs.first, path: ["navigationEndpoint", "watchEndpoint", "watchEndpointMusicSupportedConfigs", "watchEndpointMusicConfig", "musicVideoType"]) as? String
        let isVideo = musicVideoType == "MUSIC_VIDEO_TYPE_OMV" || musicVideoType == "MUSIC_VIDEO_TYPE_UGC"

        return Track(
            id: videoId,
            title: title,
            artists: artists,
            album: album,
            durationSeconds: duration,
            thumbnailURL: thumbnailURL,
            explicit: explicit,
            isLocal: false,
            isVideo: isVideo
        )
    }

    private func parseTrack(fromTwoRow renderer: [String: Any]) -> Track? {
        guard let videoId = dig(renderer, path: ["navigationEndpoint", "watchEndpoint", "videoId"]) as? String,
              let title = firstRunText(in: renderer["title"]) else {
            return nil
        }
        let subtitleRuns = dig(renderer, path: ["subtitle", "runs"]) as? [[String: Any]] ?? []
        var artists = extractArtists(fromRuns: subtitleRuns)
        if artists.isEmpty, let fallbackArtist = subtitleRuns.first?["text"] as? String,
           !fallbackArtist.isEmpty, fallbackArtist != "Song", fallbackArtist != "Video" {
            artists = [Artist(name: fallbackArtist)]
        }
        let album = extractAlbum(fromRuns: subtitleRuns)
        let duration = extractDuration(fromRuns: subtitleRuns)
        let thumbnail = extractBestThumbnail(from: dig(renderer, path: ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        let explicit = hasExplicitBadge(renderer["subtitleBadges"] as? [[String: Any]])

        let musicVideoType = dig(renderer, path: ["navigationEndpoint", "watchEndpoint", "watchEndpointMusicSupportedConfigs", "watchEndpointMusicConfig", "musicVideoType"]) as? String
        let isVideo = musicVideoType == "MUSIC_VIDEO_TYPE_OMV" || musicVideoType == "MUSIC_VIDEO_TYPE_UGC"

        return Track(
            id: videoId,
            title: title,
            artists: artists,
            album: album,
            durationSeconds: duration,
            thumbnailURL: thumbnail,
            explicit: explicit,
            isLocal: false,
            isVideo: isVideo
        )
    }

    func parseTrack(fromPlaylistPanel renderer: [String: Any]?) -> Track? {
        guard let renderer,
              let videoId = renderer["videoId"] as? String,
              let title = firstRunText(in: renderer["title"]) else {
            return nil
        }
        let longBylineRuns = dig(renderer, path: ["longBylineText", "runs"]) as? [[String: Any]] ?? []
        let shortBylineRuns = dig(renderer, path: ["shortBylineText", "runs"]) as? [[String: Any]] ?? []
        let bylineRuns = longBylineRuns.isEmpty ? shortBylineRuns : longBylineRuns

        var artists = extractArtists(fromRuns: bylineRuns)
        if artists.isEmpty, let first = bylineRuns.first?["text"] as? String, !first.isEmpty {
            artists = [Artist(name: first)]
        }
        let album = extractAlbum(fromRuns: longBylineRuns)
        let lengthText = firstRunText(in: renderer["lengthText"])
        let duration = lengthText.flatMap(parseDurationSeconds)
        let thumbnail = extractBestThumbnail(from: dig(renderer, path: ["thumbnail", "thumbnails"]))
        let explicit = hasExplicitBadge(renderer["badges"] as? [[String: Any]])

        return Track(
            id: videoId,
            title: title,
            artists: artists,
            album: album,
            durationSeconds: duration,
            thumbnailURL: thumbnail,
            explicit: explicit,
            isLocal: false
        )
    }

    private func parseAlbum(fromResponsive renderer: [String: Any]) -> Album? {
        guard let browseId = dig(renderer, path: ["navigationEndpoint", "browseEndpoint", "browseId"]) as? String else {
            return nil
        }
        let flexColumns = renderer["flexColumns"] as? [[String: Any]] ?? []
        let title = flexColumns.first.flatMap {
            firstRunText(in: dig($0, path: ["musicResponsiveListItemFlexColumnRenderer", "text"]))
        } ?? ""
        guard !title.isEmpty else { return nil }

        let col1Runs = flexColumns.count > 1
            ? (dig(flexColumns[1], path: ["musicResponsiveListItemFlexColumnRenderer", "text", "runs"]) as? [[String: Any]] ?? [])
            : []
        let artists = extractArtists(fromRuns: col1Runs)
        let year = col1Runs.compactMap { ($0["text"] as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }.last
        let thumbnail = extractBestThumbnail(from: dig(renderer, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        let explicit = hasExplicitBadge(renderer["badges"] as? [[String: Any]])
        let playlistId = dig(renderer, path: ["overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer", "playNavigationEndpoint", "watchPlaylistEndpoint", "playlistId"]) as? String

        return Album(
            id: browseId,
            name: title,
            artists: artists,
            year: year,
            thumbnailURL: thumbnail,
            browseId: browseId,
            playlistId: playlistId,
            explicit: explicit
        )
    }

    private func parseAlbum(fromTwoRow renderer: [String: Any]) -> Album? {
        guard let browseId = dig(renderer, path: ["navigationEndpoint", "browseEndpoint", "browseId"]) as? String,
              let title = firstRunText(in: renderer["title"]) else {
            return nil
        }
        let subtitleRuns = dig(renderer, path: ["subtitle", "runs"]) as? [[String: Any]] ?? []
        let artists = extractArtists(fromRuns: subtitleRuns)
        let year = subtitleRuns.compactMap { ($0["text"] as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }.last
        let thumbnail = extractBestThumbnail(from: dig(renderer, path: ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        let explicit = hasExplicitBadge(renderer["subtitleBadges"] as? [[String: Any]])
        let playlistId = dig(renderer, path: ["thumbnailOverlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer", "playNavigationEndpoint", "watchPlaylistEndpoint", "playlistId"]) as? String

        return Album(
            id: browseId,
            name: title,
            artists: artists,
            year: year,
            thumbnailURL: thumbnail,
            browseId: browseId,
            playlistId: playlistId,
            explicit: explicit
        )
    }

    private func parseArtist(fromResponsive renderer: [String: Any]) -> Artist? {
        guard let browseId = dig(renderer, path: ["navigationEndpoint", "browseEndpoint", "browseId"]) as? String else {
            return nil
        }
        let flexColumns = renderer["flexColumns"] as? [[String: Any]] ?? []
        let name = flexColumns.first.flatMap {
            firstRunText(in: dig($0, path: ["musicResponsiveListItemFlexColumnRenderer", "text"]))
        } ?? ""
        guard !name.isEmpty else { return nil }

        let col1Runs = flexColumns.count > 1
            ? (dig(flexColumns[1], path: ["musicResponsiveListItemFlexColumnRenderer", "text", "runs"]) as? [[String: Any]] ?? [])
            : []
        let subscriberCount = col1Runs.compactMap { $0["text"] as? String }.first(where: { $0.localizedCaseInsensitiveContains("sub") || $0.contains("M") || $0.contains("K") })
        let thumbnail = extractBestThumbnail(from: dig(renderer, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))

        return Artist(
            id: browseId,
            name: name,
            thumbnailURL: thumbnail,
            subscriberCount: subscriberCount,
            browseId: browseId
        )
    }

    private func parseArtist(fromTwoRow renderer: [String: Any]) -> Artist? {
        guard let browseId = dig(renderer, path: ["navigationEndpoint", "browseEndpoint", "browseId"]) as? String,
              let name = firstRunText(in: renderer["title"]) else {
            return nil
        }
        let subscriberCount = firstRunText(in: renderer["subtitle"])
        let thumbnail = extractBestThumbnail(from: dig(renderer, path: ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        return Artist(
            id: browseId,
            name: name,
            thumbnailURL: thumbnail,
            subscriberCount: subscriberCount,
            browseId: browseId
        )
    }

    private func parsePlaylist(fromResponsive renderer: [String: Any]) -> YouTubePlaylist? {
        guard let browseId = dig(renderer, path: ["navigationEndpoint", "browseEndpoint", "browseId"]) as? String else {
            return nil
        }
        let flexColumns = renderer["flexColumns"] as? [[String: Any]] ?? []
        let title = flexColumns.first.flatMap {
            firstRunText(in: dig($0, path: ["musicResponsiveListItemFlexColumnRenderer", "text"]))
        } ?? ""
        guard !title.isEmpty else { return nil }

        let col1Runs = flexColumns.count > 1
            ? (dig(flexColumns[1], path: ["musicResponsiveListItemFlexColumnRenderer", "text", "runs"]) as? [[String: Any]] ?? [])
            : []
        let author = col1Runs.first(where: { $0["navigationEndpoint"] != nil })?["text"] as? String
            ?? col1Runs.last?["text"] as? String
        let thumbnail = extractBestThumbnail(from: dig(renderer, path: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        let cleanId = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId

        return YouTubePlaylist(
            id: cleanId,
            name: title,
            thumbnailURL: thumbnail,
            author: author
        )
    }

    private func parsePlaylist(fromTwoRow renderer: [String: Any]) -> YouTubePlaylist? {
        guard let browseId = dig(renderer, path: ["navigationEndpoint", "browseEndpoint", "browseId"]) as? String,
              let title = firstRunText(in: renderer["title"]) else {
            return nil
        }
        let subtitleRuns = dig(renderer, path: ["subtitle", "runs"]) as? [[String: Any]] ?? []
        let author = subtitleRuns.first(where: { $0["navigationEndpoint"] != nil })?["text"] as? String
            ?? subtitleRuns.compactMap { $0["text"] as? String }.filter { $0 != " • " && $0 != "Playlist" }.first
        let thumbnail = extractBestThumbnail(from: dig(renderer, path: ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        let cleanId = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId

        return YouTubePlaylist(
            id: cleanId,
            name: title,
            thumbnailURL: thumbnail,
            author: author
        )
    }

    // MARK: - JSON Traversal & Extraction Helpers

    private func extractPrimarySectionContents(from json: [String: Any]) -> [[String: Any]] {
        let singleTabs = dig(json, path: ["contents", "singleColumnBrowseResultsRenderer", "tabs"]) as? [[String: Any]]
        let twoTabs = dig(json, path: ["contents", "twoColumnBrowseResultsRenderer", "tabs"]) as? [[String: Any]]
        let tabs = singleTabs ?? twoTabs ?? []
        return dig(tabs.first, path: ["tabRenderer", "content", "sectionListRenderer", "contents"]) as? [[String: Any]] ?? []
    }

    private func extractArtists(fromRuns runs: [[String: Any]]) -> [Artist] {
        var result: [Artist] = []
        for run in runs {
            guard let text = run["text"] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "•" || trimmed == "," || trimmed == "&" { continue }

            if let browseEndpoint = dig(run, path: ["navigationEndpoint", "browseEndpoint"]) as? [String: Any],
               let browseId = browseEndpoint["browseId"] as? String {
                let pageType = dig(browseEndpoint, path: ["browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"]) as? String
                if pageType == "MUSIC_PAGE_TYPE_ARTIST" || pageType == "MUSIC_PAGE_TYPE_USER_CHANNEL" || browseId.hasPrefix("UC") {
                    result.append(Artist(id: browseId, name: trimmed, browseId: browseId))
                }
            }
        }
        return result
    }

    private func extractAlbum(fromRuns runs: [[String: Any]]) -> Album? {
        for run in runs {
            guard let text = run["text"] as? String else { continue }
            if let browseEndpoint = dig(run, path: ["navigationEndpoint", "browseEndpoint"]) as? [String: Any],
               let browseId = browseEndpoint["browseId"] as? String {
                let pageType = dig(browseEndpoint, path: ["browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"]) as? String
                if pageType == "MUSIC_PAGE_TYPE_ALBUM" || browseId.hasPrefix("MPREb_") {
                    return Album(id: browseId, name: text, browseId: browseId)
                }
            }
        }
        return nil
    }

    private func extractDuration(fromRuns runs: [[String: Any]]) -> Int? {
        for run in runs.reversed() {
            if let text = run["text"] as? String,
               let seconds = parseDurationSeconds(text) {
                return seconds
            }
        }
        return nil
    }

    func parseDurationSeconds(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private func extractBestThumbnail(from raw: Any?) -> String? {
        guard let list = raw as? [[String: Any]], !list.isEmpty else { return nil }
        let sorted = list.sorted {
            ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0)
        }
        guard var url = sorted.last?["url"] as? String else { return nil }
        if url.hasPrefix("//") {
            url = "https:\(url)"
        }
        // Upgrade Googleusercontent thumbnails to crisp square resolution if small
        if url.contains("lh3.googleusercontent.com") && url.contains("=w") {
            if let eqRange = url.range(of: "=w\\d+-h\\d+", options: .regularExpression) {
                url.replaceSubrange(eqRange, with: "=w544-h544")
            }
        }
        return url
    }

    private func hasExplicitBadge(_ badges: [[String: Any]]?) -> Bool {
        guard let badges else { return false }
        return badges.contains {
            (dig($0, path: ["musicInlineBadgeRenderer", "icon", "iconType"]) as? String) == "MUSIC_EXPLICIT_BADGE"
        }
    }

    private func extractContinuation(from continuations: [[String: Any]]?) -> String? {
        guard let continuations else { return nil }
        for cont in continuations {
            if let token = dig(cont, path: ["nextContinuationData", "continuation"]) as? String {
                return token
            }
            if let token = dig(cont, path: ["nextRadioContinuationData", "continuation"]) as? String {
                return token
            }
        }
        return nil
    }

    private func extractContinuationFromItems(_ items: [[String: Any]]?) -> String? {
        guard let items else { return nil }
        for item in items {
            if let token = dig(item, path: ["continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token"]) as? String {
                return token
            }
        }
        return nil
    }

    private func firstRunText(in object: Any?) -> String? {
        guard let dict = object as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.first?["text"] as? String
        }
        return nil
    }

    private func extractRunsText(_ object: Any?) -> String? {
        guard let runs = object as? [[String: Any]] else { return nil }
        let joined = runs.compactMap { $0["text"] as? String }.joined()
        return joined.isEmpty ? nil : joined
    }

    private func parseTimedTextJSON3ToLRC(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            return nil
        }
        var lines: [String] = []
        for event in events {
            guard let startMs = event["tStartMs"] as? Int,
                  let segs = event["segs"] as? [[String: Any]] else {
                continue
            }
            let text = segs.compactMap { $0["utf8"] as? String }
                .joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let minutes = startMs / 60000
            let seconds = (startMs % 60000) / 1000
            let centis = (startMs % 1000) / 10
            lines.append(String(format: "[%02d:%02d.%02d]%@", minutes, seconds, centis, text))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func dig(_ root: Any?, path: [Any]) -> Any? {
        var current: Any? = root
        for step in path {
            if let key = step as? String, let dict = current as? [String: Any] {
                current = dict[key]
            } else if let idx = step as? Int, let arr = current as? [Any], idx >= 0, idx < arr.count {
                current = arr[idx]
            } else {
                return nil
            }
        }
        return current
    }
}
