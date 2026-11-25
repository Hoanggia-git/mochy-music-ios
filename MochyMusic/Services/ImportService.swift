import Foundation
import AuthenticationServices
import CryptoKit
import MusicKit
import UIKit

/// Imports playlists and tracks from Spotify, Apple Music, TIDAL, and CSV/text files, matching via InnerTube.
@MainActor
final class ImportService: NSObject, ObservableObject {
    static let shared = ImportService()

    @Published var progress: ImportProgress?
    @Published var isImporting: Bool = false
    @Published var importedPlaylists: [ImportedPlaylist] = []
    @Published var lastError: String?

    private var importTask: Task<Void, Never>?
    private var authSession: ASWebAuthenticationSession?
    private var authPresentationProvider: ImportWebAuthPresentationProvider?
    private var spotifyAccessToken: String?
    private var tidalAccessToken: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private override init() {
        super.init()
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        isImporting = false
        if var current = progress {
            current.status = .cancelled
            progress = current
        }
    }

    // MARK: - Spotify OAuth & Import

    func buildSpotifyAuthURL(clientId: String, redirectURI: String = "mochymusic://spotify-callback") -> (url: URL, codeVerifier: String)? {
        let verifier = randomURLSafeString(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "playlist-read-private playlist-read-collaborative user-library-read"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]
        guard let url = components?.url else { return nil }
        return (url, verifier)
    }

    func authenticateSpotify(clientId: String, redirectURI: String = "mochymusic://spotify-callback") async throws -> String {
        guard let (authURL, verifier) = buildSpotifyAuthURL(clientId: clientId, redirectURI: redirectURI),
              let scheme = URL(string: redirectURI)?.scheme else {
            throw NSError(domain: "ImportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Spotify OAuth configuration."])
        }

        let callbackURL = try await startWebAuth(url: authURL, callbackScheme: scheme)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NSError(domain: "ImportService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Spotify authorization code missing."])
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyParams = URLComponents()
        bodyParams.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = bodyParams.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw NSError(domain: "ImportService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to exchange Spotify token."])
        }
        spotifyAccessToken = token
        return token
    }

    func fetchSpotifyPlaylists(accessToken: String? = nil) async throws -> [ImportedPlaylist] {
        guard let token = accessToken ?? spotifyAccessToken, !token.isEmpty else {
            throw NSError(domain: "ImportService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Not signed in to Spotify."])
        }

        let playlistsJSON = try await authorizedGET(urlString: "https://api.spotify.com/v1/me/playlists?limit=50", bearerToken: token)
        let items = playlistsJSON["items"] as? [[String: Any]] ?? []

        var result: [ImportedPlaylist] = []
        for item in items {
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String else { continue }
            let images = item["images"] as? [[String: Any]]
            let thumb = images?.first?["url"] as? String
            let owner = (item["owner"] as? [String: Any])?["display_name"] as? String
            let rawTracks = try await fetchSpotifyPlaylistTracks(playlistId: id, token: token)

            result.append(ImportedPlaylist(
                id: "spotify_\(id)",
                name: name,
                source: .spotify,
                authorName: owner,
                thumbnailURL: thumb,
                remoteURL: "https://open.spotify.com/playlist/\(id)",
                rawTracks: rawTracks
            ))
        }
        return result
    }

    private func fetchSpotifyPlaylistTracks(playlistId: String, token: String) async throws -> [ImportedRawTrack] {
        var nextURL: String? = "https://api.spotify.com/v1/playlists/\(playlistId)/tracks?limit=100"
        var tracks: [ImportedRawTrack] = []

        while let urlStr = nextURL {
            let json = try await authorizedGET(urlString: urlStr, bearerToken: token)
            let items = json["items"] as? [[String: Any]] ?? []
            for entry in items {
                guard let trackDict = entry["track"] as? [String: Any],
                      let title = trackDict["name"] as? String else { continue }
                let artists = (trackDict["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                let albumName = (trackDict["album"] as? [String: Any])?["name"] as? String
                let durationMs = trackDict["duration_ms"] as? Int
                let isrc = (trackDict["external_ids"] as? [String: Any])?["isrc"] as? String
                tracks.append(ImportedRawTrack(
                    title: title,
                    artist: artists.joined(separator: ", "),
                    album: albumName,
                    durationSeconds: durationMs.map { $0 / 1000 },
                    isrc: isrc
                ))
            }
            nextURL = json["next"] as? String
        }
        return tracks
    }

    // MARK: - Apple Music Import (MusicKit)

    func importFromAppleMusic() async throws -> [UserPlaylist] {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            throw NSError(domain: "ImportService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Apple Music access was denied."])
        }

        let request = MusicLibraryRequest<MusicKit.Playlist>()
        let response = try await request.response()

        var rawPlaylists: [ImportedPlaylist] = []
        for playlist in response.items {
            let detailed = try? await playlist.with([.tracks])
            let rawTracks: [ImportedRawTrack] = detailed?.tracks?.map { track in
                ImportedRawTrack(
                    title: track.title,
                    artist: track.artistName,
                    album: track.albumTitle,
                    durationSeconds: track.duration.map { Int($0.rounded()) },
                    isrc: track.isrc
                )
            } ?? []
            rawPlaylists.append(ImportedPlaylist(
                id: "apple_\(playlist.id.rawValue)",
                name: playlist.name,
                source: .appleMusic,
                authorName: playlist.curatorName,
                rawTracks: rawTracks
            ))
        }

        return await matchAndSavePlaylists(rawPlaylists, source: .appleMusic)
    }

    // MARK: - TIDAL OAuth & Import

    func authenticateTidal(clientId: String, redirectURI: String = "mochymusic://tidal-callback") async throws -> String {
        let verifier = randomURLSafeString(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents(string: "https://login.tidal.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user.read playlists.read"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        guard let authURL = components?.url,
              let scheme = URL(string: redirectURI)?.scheme else {
            throw NSError(domain: "ImportService", code: -6, userInfo: [NSLocalizedDescriptionKey: "Invalid TIDAL OAuth configuration."])
        }

        let callbackURL = try await startWebAuth(url: authURL, callbackScheme: scheme)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NSError(domain: "ImportService", code: -7, userInfo: [NSLocalizedDescriptionKey: "TIDAL authorization code missing."])
        }

        var request = URLRequest(url: URL(string: "https://auth.tidal.com/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var bodyParams = URLComponents()
        bodyParams.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = bodyParams.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw NSError(domain: "ImportService", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to exchange TIDAL token."])
        }
        tidalAccessToken = token
        return token
    }

    func fetchTidalPlaylist(playlistId: String, accessToken: String? = nil) async throws -> ImportedPlaylist {
        guard let token = accessToken ?? tidalAccessToken, !token.isEmpty else {
            throw NSError(domain: "ImportService", code: -9, userInfo: [NSLocalizedDescriptionKey: "Not signed in to TIDAL."])
        }
        let cleanId = playlistId.components(separatedBy: "/").last ?? playlistId
        let meta = try await authorizedGET(urlString: "https://openapi.tidal.com/v2/playlists/\(cleanId)?countryCode=US", bearerToken: token)
        let title = ((meta["data"] as? [String: Any])?["attributes"] as? [String: Any])?["name"] as? String ?? "TIDAL Playlist"

        let itemsJSON = try await authorizedGET(
            urlString: "https://openapi.tidal.com/v2/playlists/\(cleanId)/relationships/items?countryCode=US&include=items",
            bearerToken: token
        )
        let included = itemsJSON["included"] as? [[String: Any]] ?? []
        let rawTracks: [ImportedRawTrack] = included.compactMap { entry in
            guard let attrs = entry["attributes"] as? [String: Any],
                  let name = attrs["title"] as? String else { return nil }
            let isrc = attrs["isrc"] as? String
            return ImportedRawTrack(title: name, artist: "", isrc: isrc)
        }

        return ImportedPlaylist(
            id: "tidal_\(cleanId)",
            name: title,
            source: .tidal,
            remoteURL: "https://tidal.com/browse/playlist/\(cleanId)",
            rawTracks: rawTracks
        )
    }

    // MARK: - CSV / Text Import

    func importFromCSV(fileURL: URL, playlistName: String? = nil) async throws -> UserPlaylist? {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let name = playlistName ?? fileURL.deletingPathExtension().lastPathComponent
        return await importFromCSVText(content, playlistName: name)
    }

    func importFromCSVText(_ text: String, playlistName: String = "Imported Playlist") async -> UserPlaylist? {
        let rawTracks = parseCSVOrTextTracks(text)
        guard !rawTracks.isEmpty else {
            lastError = "No tracks found in CSV/text input."
            return nil
        }

        let imported = ImportedPlaylist(
            name: playlistName,
            source: .csv,
            rawTracks: rawTracks
        )
        let playlists = await matchAndSavePlaylists([imported], source: .csv)
        return playlists.first
    }

    func parseCSVOrTextTracks(_ input: String) -> [ImportedRawTrack] {
        let lines = input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        // Detect CSV header row
        let firstColumns = parseCSVRow(lines[0]).map { $0.lowercased() }
        var titleIndex: Int?
        var artistIndex: Int?
        var albumIndex: Int?
        var startRow = 0

        if firstColumns.count >= 2 && (
            firstColumns.contains(where: { $0.contains("title") || $0.contains("track") || $0.contains("song") }) ||
            firstColumns.contains(where: { $0.contains("artist") })
        ) {
            titleIndex = firstColumns.firstIndex(where: { $0.contains("title") || $0.contains("track name") || $0 == "track" || $0.contains("song") }) ?? 0
            artistIndex = firstColumns.firstIndex(where: { $0.contains("artist") }) ?? 1
            albumIndex = firstColumns.firstIndex(where: { $0.contains("album") })
            startRow = 1
        }

        var tracks: [ImportedRawTrack] = []
        for line in lines.dropFirst(startRow) {
            let cols = parseCSVRow(line)
            if cols.count >= 2 {
                let tIdx = titleIndex ?? 0
                let aIdx = artistIndex ?? 1
                let title = cols.indices.contains(tIdx) ? cols[tIdx] : ""
                let artist = cols.indices.contains(aIdx) ? cols[aIdx] : ""
                let album = albumIndex.flatMap { cols.indices.contains($0) ? cols[$0] : nil }
                if !title.isEmpty {
                    tracks.append(ImportedRawTrack(title: title, artist: artist, album: album))
                }
            } else if let dashRange = line.range(of: " - ") {
                // Plain text "Artist - Title" format
                let artist = String(line[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let title = String(line[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    tracks.append(ImportedRawTrack(title: title, artist: artist))
                }
            } else {
                tracks.append(ImportedRawTrack(title: line, artist: ""))
            }
        }
        return tracks
    }

    private func parseCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(row)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    // MARK: - InnerTube Matching Pipeline

    func matchAndSavePlaylists(_ playlists: [ImportedPlaylist], source: ImportSource) async -> [UserPlaylist] {
        let total = playlists.reduce(0) { $0 + $1.rawTracks.count }
        isImporting = true
        lastError = nil
        progress = ImportProgress(
            source: source,
            totalItems: total,
            processedItems: 0,
            matchedItems: 0,
            failedItems: 0,
            status: .matching
        )

        var createdPlaylists: [UserPlaylist] = []
        var importedPlaylistIds: [String] = []

        for var playlist in playlists {
            var matched: [Track] = []
            for raw in playlist.rawTracks {
                if Task.isCancelled { break }
                progress?.currentItemName = "\(raw.artist.isEmpty ? "" : "\(raw.artist) - ")\(raw.title)"

                if let track = await matchTrackViaInnerTube(raw) {
                    matched.append(track)
                    progress?.matchedItems += 1
                } else {
                    progress?.failedItems += 1
                }
                progress?.processedItems += 1
            }

            playlist.matchedTracks = matched
            importedPlaylists.append(playlist)

            if !matched.isEmpty {
                let saved = LibraryStore.shared.createPlaylist(
                    name: playlist.name,
                    description: "Imported from \(source.displayName)",
                    tracks: matched,
                    thumbnailURL: playlist.thumbnailURL ?? matched.first?.thumbnailURL
                )
                createdPlaylists.append(saved)
                importedPlaylistIds.append(saved.id.uuidString)
            }
        }

        if !importedPlaylistIds.isEmpty {
            var sessions = PersistenceManager.shared.loadImportSessions()
            sessions.insert(ImportSession(source: source.rawValue, importedPlaylistIds: importedPlaylistIds), at: 0)
            PersistenceManager.shared.saveImportSessions(sessions)
        }

        progress?.status = Task.isCancelled ? .cancelled : .completed
        progress?.currentItemName = nil
        isImporting = false
        return createdPlaylists
    }

    func matchTrackViaInnerTube(_ raw: ImportedRawTrack) async -> Track? {
        let query = [raw.artist, raw.title].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty,
              let candidates = try? await InnerTubeService.shared.searchSongs(query: query),
              !candidates.isEmpty else {
            return nil
        }

        if let expectedDuration = raw.durationSeconds {
            let best = candidates.prefix(5).min { a, b in
                let diffA = abs((a.durationSeconds ?? expectedDuration) - expectedDuration)
                let diffB = abs((b.durationSeconds ?? expectedDuration) - expectedDuration)
                return diffA < diffB
            }
            return best ?? candidates.first
        }
        return candidates.first
    }

    // MARK: - Helpers

    private func authorizedGET(urlString: String, bearerToken: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw InnerTubeError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw InnerTubeError.httpError(http.statusCode, String(data: data, encoding: .utf8))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.decodingError("Invalid JSON response")
        }
        return json
    }

    private func startWebAuth(url: URL, callbackScheme: String) async throws -> URL {
        let anchor = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        let provider = ImportWebAuthPresentationProvider(anchor: anchor)
        self.authPresentationProvider = provider

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: URLError(.cancelled))
                }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    private func randomURLSafeString(length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

private final class ImportWebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
