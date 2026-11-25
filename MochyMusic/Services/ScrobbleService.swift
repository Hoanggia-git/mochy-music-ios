import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Last.fm scrobbling service using Audioscrobbler 2.0 API (`ws.audioscrobbler.com/2.0/`).
@MainActor
final class ScrobbleService: NSObject, ObservableObject {
    static let shared = ScrobbleService()

    @Published var isAuthenticated: Bool = false
    @Published var username: String = ""
    @Published var lastError: String?

    private let apiRoot = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private let session: URLSession
    private var authSession: ASWebAuthenticationSession?
    private var authPresentationProvider: ScrobbleWebAuthPresentationProvider?

    private override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        super.init()
        syncAuthState()
    }

    func syncAuthState() {
        let settings = AppSettings.shared
        username = settings.lastFmUsername
        isAuthenticated = !settings.lastFmSession.isEmpty && !settings.lastFmUsername.isEmpty
    }

    var isConfigured: Bool {
        let settings = AppSettings.shared
        return !settings.lastFmApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.lastFmApiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Authentication

    func getWebAuthURL(callbackURL: String = "mochymusic://lastfm-callback") -> URL? {
        let apiKey = AppSettings.shared.lastFmApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.last.fm/api/auth/")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "cb", value: callbackURL)
        ]
        return components?.url
    }

    func authenticateWithWebLogin(callbackScheme: String = "mochymusic") async throws {
        guard let url = getWebAuthURL(callbackURL: "\(callbackScheme)://lastfm-callback") else {
            throw NSError(domain: "ScrobbleService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Last.fm API key is missing."])
        }

        let anchor = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        let provider = ScrobbleWebAuthPresentationProvider(anchor: anchor)
        self.authPresentationProvider = provider

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let webAuth = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { resultURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let resultURL {
                    continuation.resume(returning: resultURL)
                } else {
                    continuation.resume(throwing: URLError(.cancelled))
                }
            }
            webAuth.presentationContextProvider = provider
            self.authSession = webAuth
            webAuth.start()
        }

        guard let token = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "token" })?.value else {
            throw NSError(domain: "ScrobbleService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing Last.fm auth token."])
        }

        try await exchangeSessionToken(token)
    }

    func exchangeSessionToken(_ token: String) async throws {
        let json = try await signedCall(method: "auth.getSession", params: ["token": token], sessionKey: nil)
        guard let sessionObj = json["session"] as? [String: Any],
              let name = sessionObj["name"] as? String,
              let key = sessionObj["key"] as? String else {
            throw NSError(domain: "ScrobbleService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid Last.fm session payload."])
        }

        AppSettings.shared.lastFmUsername = name
        AppSettings.shared.lastFmSession = key
        AppSettings.shared.lastFmEnabled = true
        syncAuthState()
    }

    func signInWithPassword(username: String, password: String) async throws {
        let json = try await signedCall(
            method: "auth.getMobileSession",
            params: [
                "username": username,
                "password": password
            ],
            sessionKey: nil
        )
        guard let sessionObj = json["session"] as? [String: Any],
              let name = sessionObj["name"] as? String,
              let key = sessionObj["key"] as? String else {
            throw NSError(domain: "ScrobbleService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid Last.fm login response."])
        }

        AppSettings.shared.lastFmUsername = name
        AppSettings.shared.lastFmSession = key
        AppSettings.shared.lastFmEnabled = true
        syncAuthState()
    }

    func signOut() {
        AppSettings.shared.lastFmUsername = ""
        AppSettings.shared.lastFmSession = ""
        AppSettings.shared.lastFmEnabled = false
        syncAuthState()
    }

    // MARK: - Scrobble Actions

    func updateNowPlaying(track: Track) async {
        let settings = AppSettings.shared
        guard settings.lastFmEnabled,
              settings.lastFmNowPlaying,
              !settings.lastFmSession.isEmpty,
              isConfigured else {
            return
        }

        var params: [String: String] = [
            "artist": track.artistsText,
            "track": track.title
        ]
        if let album = track.album?.name, !album.isEmpty {
            params["album"] = album
        }
        if let duration = track.durationSeconds, duration > 0 {
            params["duration"] = String(duration)
        }

        do {
            _ = try await signedCall(method: "track.updateNowPlaying", params: params, sessionKey: settings.lastFmSession)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func scrobble(track: Track, timestamp: Date = Date()) async {
        let settings = AppSettings.shared
        guard settings.lastFmEnabled,
              !settings.lastFmSession.isEmpty,
              isConfigured else {
            return
        }

        var params: [String: String] = [
            "artist": track.artistsText,
            "track": track.title,
            "timestamp": String(Int(timestamp.timeIntervalSince1970))
        ]
        if let album = track.album?.name, !album.isEmpty {
            params["album"] = album
        }
        if let duration = track.durationSeconds, duration > 0 {
            params["duration"] = String(duration)
        }

        do {
            _ = try await signedCall(method: "track.scrobble", params: params, sessionKey: settings.lastFmSession)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func love(track: Track, loved: Bool) async {
        let settings = AppSettings.shared
        guard settings.lastFmEnabled,
              !settings.lastFmSession.isEmpty,
              isConfigured else {
            return
        }

        let method = loved ? "track.love" : "track.unlove"
        do {
            _ = try await signedCall(
                method: method,
                params: [
                    "artist": track.artistsText,
                    "track": track.title
                ],
                sessionKey: settings.lastFmSession
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Signed Audioscrobbler 2.0 Transport

    private func signedCall(method: String, params: [String: String], sessionKey: String?) async throws -> [String: Any] {
        let settings = AppSettings.shared
        let apiKey = settings.lastFmApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = settings.lastFmApiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !secret.isEmpty else {
            throw NSError(domain: "ScrobbleService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Last.fm API key or secret not configured."])
        }

        var signedParams = params
        signedParams["method"] = method
        signedParams["api_key"] = apiKey
        if let sessionKey, !sessionKey.isEmpty {
            signedParams["sk"] = sessionKey
        }

        let signatureBase = signedParams.keys.sorted().map { "\($0)\(signedParams[$0] ?? "")" }.joined() + secret
        let apiSig = md5Hex(signatureBase)

        var formParams = signedParams
        formParams["api_sig"] = apiSig
        formParams["format"] = "json"

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = formParams.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: apiRoot)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mochy", forHTTPHeaderField: "User-Agent")
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "ScrobbleService", code: status, userInfo: [NSLocalizedDescriptionKey: "Unreadable Last.fm response (HTTP \(status))."])
        }

        if let errorCode = json["error"] as? Int {
            let msg = json["message"] as? String ?? "Last.fm error \(errorCode)"
            if errorCode == 9 {
                signOut()
            }
            throw NSError(domain: "ScrobbleService", code: errorCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return json
    }

    private func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private final class ScrobbleWebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
