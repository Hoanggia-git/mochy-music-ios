import Foundation
import WebKit

/// BotGuard Proof-of-Origin (poToken) generator using `WKWebView` + bundled `po_token.html`.
/// Mirrors Android Mochy `PoTokenGenerator` & `PoTokenWebView`.
@MainActor
final class PoTokenService: NSObject {
    static let shared = PoTokenService()

    struct PoTokenResult {
        let playerRequestPoToken: String
        let streamingDataPoToken: String
    }

    private enum Constants {
        static let googleAPIKey = "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw"
        static let requestKey = "O43z0dpjhgX20SCx4KAo"
        static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        static let messageHandlerName = "mochyPoToken"
        static let coldStartTimeoutSeconds: TimeInterval = 45.0
        static let mintTimeoutSeconds: TimeInterval = 10.0
        static let cooldownDurationSeconds: TimeInterval = 300.0
    }

    private var webView: WKWebView?
    private var expirationDate: Date?
    private var sessionId: String?
    private var streamingPoToken: String?
    private var cooldownUntil: Date?

    private var initContinuation: CheckedContinuation<Void, Error>?
    private var mintContinuations: [String: CheckedContinuation<String, Error>] = [:]
    private var isBooting = false
    private var bootWaiters: [CheckedContinuation<Void, Error>] = []

    var hasSessionToken: Bool {
        guard let streamingPoToken, !streamingPoToken.isEmpty,
              let expirationDate, Date() < expirationDate,
              webView != nil else {
            return false
        }
        return true
    }

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func preWarm(sessionId: String) async {
        guard !sessionId.isEmpty else { return }
        _ = await poToken(for: "dQw4w9WgXcQ", sessionId: sessionId)
    }

    func poToken(for videoId: String, sessionId: String) async -> PoTokenResult? {
        guard !videoId.isEmpty, !sessionId.isEmpty else { return nil }
        if let cooldownUntil, Date() < cooldownUntil {
            return nil
        }

        do {
            let needsRecreate = (webView == nil)
                || (self.sessionId != sessionId)
                || (streamingPoToken == nil)
                || (expirationDate == nil || Date() >= (expirationDate ?? .distantPast))

            if needsRecreate {
                try await bootBotGuard(for: sessionId)
            }

            guard let sessionPot = streamingPoToken else { return nil }
            do {
                let playerPot = try await mintPoToken(identifier: videoId)
                return PoTokenResult(playerRequestPoToken: sessionPot, streamingDataPoToken: playerPot)
            } catch {
                // Retry once with a fresh BotGuard session on stale minter errors
                try await bootBotGuard(for: sessionId)
                guard let freshSessionPot = streamingPoToken else { return nil }
                let playerPot = try await mintPoToken(identifier: videoId)
                return PoTokenResult(playerRequestPoToken: freshSessionPot, streamingDataPoToken: playerPot)
            }
        } catch {
            cooldownUntil = Date().addingTimeInterval(Constants.cooldownDurationSeconds)
            return nil
        }
    }

    func releaseWebView() {
        tearDownWebView(with: CancellationError())
    }

    // MARK: - BotGuard Lifecycle

    private func bootBotGuard(for sessionId: String) async throws {
        if isBooting {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                bootWaiters.append(cont)
            }
            if self.sessionId == sessionId, self.hasSessionToken {
                return
            }
        }

        isBooting = true
        defer { isBooting = false }

        tearDownWebView(with: nil)

        guard let htmlURL = Bundle.main.url(forResource: "po_token", withExtension: "html"),
              let rawHTML = try? String(contentsOf: htmlURL, encoding: .utf8) else {
            let err = NSError(domain: "PoTokenService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing po_token.html resource"])
            failAllBootWaiters(with: err)
            throw err
        }

        let bridgeScript = """
        window.PoTokenWebView = {
            downloadAndRunBotguard: function() {
                window.webkit.messageHandlers.\(Constants.messageHandlerName).postMessage({ type: "downloadAndRunBotguard" });
            },
            onRunBotguardResult: function(res) {
                window.webkit.messageHandlers.\(Constants.messageHandlerName).postMessage({ type: "onRunBotguardResult", value: String(res || "") });
            },
            onMinterCreated: function() {
                window.webkit.messageHandlers.\(Constants.messageHandlerName).postMessage({ type: "onMinterCreated" });
            },
            onObtainPoTokenResult: function(id, u8) {
                window.webkit.messageHandlers.\(Constants.messageHandlerName).postMessage({ type: "onObtainPoTokenResult", id: String(id || ""), value: String(u8 || "") });
            },
            onObtainPoTokenError: function(id, err) {
                window.webkit.messageHandlers.\(Constants.messageHandlerName).postMessage({ type: "onObtainPoTokenError", id: String(id || ""), error: String(err || "") });
            },
            onJsInitializationError: function(err) {
                window.webkit.messageHandlers.\(Constants.messageHandlerName).postMessage({ type: "onJsInitializationError", error: String(err || "") });
            }
        };
        """

        let patchedHTML: String
        if let range = rawHTML.range(of: "</script>") {
            patchedHTML = rawHTML.replacingCharacters(
                in: range,
                with: "\n\(bridgeScript)\nPoTokenWebView.downloadAndRunBotguard();\n</script>"
            )
        } else {
            patchedHTML = rawHTML
        }

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let contentController = WKUserContentController()
        let proxyHandler = WeakScriptMessageHandler(delegate: self)
        contentController.add(proxyHandler, name: Constants.messageHandlerName)
        config.userContentController = contentController

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.customUserAgent = Constants.userAgent
        self.webView = wv

        do {
            try await withTimeout(seconds: Constants.coldStartTimeoutSeconds) {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self.initContinuation = cont
                    wv.loadHTMLString(patchedHTML, baseURL: URL(string: "https://www.youtube.com"))
                }
            }

            let sessionPot = try await mintPoToken(identifier: sessionId)
            self.sessionId = sessionId
            self.streamingPoToken = sessionPot
            succeedAllBootWaiters()
        } catch {
            tearDownWebView(with: error)
            failAllBootWaiters(with: error)
            throw error
        }
    }

    private func mintPoToken(identifier: String) async throws -> String {
        guard let wv = webView else {
            throw NSError(domain: "PoTokenService", code: -2, userInfo: [NSLocalizedDescriptionKey: "PoToken WebView unavailable"])
        }

        return try await withTimeout(seconds: Constants.mintTimeoutSeconds) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                self.mintContinuations[identifier] = cont
                let quotedId = Self.jsonQuotedString(identifier)
                let u8Expr = Self.uint8ArrayExpression(for: Data(identifier.utf8))
                let js = """
                try {
                    var identifier = \(quotedId);
                    var u8Identifier = \(u8Expr);
                    obtainPoToken(u8Identifier).then(function(poTokenU8) {
                        var poTokenU8String = Array.prototype.join.call(poTokenU8, ",");
                        PoTokenWebView.onObtainPoTokenResult(identifier, poTokenU8String);
                    }).catch(function(error) {
                        PoTokenWebView.onObtainPoTokenError(identifier, String(error) + "\\n" + (error && error.stack ? error.stack : ""));
                    });
                } catch (error) {
                    PoTokenWebView.onObtainPoTokenError(\(quotedId), String(error));
                }
                """
                wv.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    private func handleDownloadAndRunBotguard() {
        Task { @MainActor [weak self] in
            guard let self, let wv = self.webView else { return }
            do {
                let body = Data("[ \"\(Constants.requestKey)\" ]".utf8)
                let data = try await self.postBotguard(urlString: "https://www.youtube.com/api/jnn/v1/Create", body: body)
                let parsedChallenge = try Self.parseChallengeData(from: data)
                let js = """
                try {
                    var data = \(parsedChallenge);
                    runBotGuard(data).then(function(result) {
                        window.webPoSignalOutput = result.webPoSignalOutput;
                        PoTokenWebView.onRunBotguardResult(result.botguardResponse);
                    }, function(error) {
                        PoTokenWebView.onJsInitializationError(String(error) + "\\n" + (error && error.stack ? error.stack : ""));
                    });
                } catch (error) {
                    PoTokenWebView.onJsInitializationError(String(error) + "\\n" + (error && error.stack ? error.stack : ""));
                }
                """
                wv.evaluateJavaScript(js, completionHandler: nil)
            } catch {
                self.finishInit(with: error)
            }
        }
    }

    private func handleRunBotguardResult(_ botguardResponse: String) {
        Task { @MainActor [weak self] in
            guard let self, let wv = self.webView else { return }
            do {
                let payload = try JSONSerialization.data(withJSONObject: [Constants.requestKey, botguardResponse])
                let data = try await self.postBotguard(urlString: "https://www.youtube.com/api/jnn/v1/GenerateIT", body: payload)
                let (integrityTokenU8, expirationSeconds) = try Self.parseIntegrityTokenData(from: data)
                self.expirationDate = Date().addingTimeInterval(TimeInterval(max(120, expirationSeconds - 600)))

                let js = """
                try {
                    window.integrityToken = \(integrityTokenU8);
                    createPoTokenMinter(window.webPoSignalOutput, window.integrityToken).then(function() {
                        PoTokenWebView.onMinterCreated();
                    }).catch(function(error) {
                        PoTokenWebView.onJsInitializationError(String(error) + "\\n" + (error && error.stack ? error.stack : ""));
                    });
                } catch (error) {
                    PoTokenWebView.onJsInitializationError(String(error) + "\\n" + (error && error.stack ? error.stack : ""));
                }
                """
                wv.evaluateJavaScript(js, completionHandler: nil)
            } catch {
                self.finishInit(with: error)
            }
        }
    }

    private func postBotguard(urlString: String, body: Data) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue(Constants.googleAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "PoTokenService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "BotGuard HTTP \(http.statusCode)"])
        }
        return data
    }

    private func finishInit(with error: Error?) {
        guard let cont = initContinuation else { return }
        initContinuation = nil
        if let error {
            cont.resume(throwing: error)
        } else {
            cont.resume()
        }
    }

    private func succeedAllBootWaiters() {
        let waiters = bootWaiters
        bootWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func failAllBootWaiters(with error: Error) {
        let waiters = bootWaiters
        bootWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func tearDownWebView(with error: Error?) {
        if let error {
            finishInit(with: error)
            let pending = mintContinuations
            mintContinuations.removeAll()
            pending.values.forEach { $0.resume(throwing: error) }
        } else {
            initContinuation = nil
            mintContinuations.removeAll()
        }
        if let wv = webView {
            wv.stopLoading()
            wv.configuration.userContentController.removeScriptMessageHandler(forName: Constants.messageHandlerName)
            webView = nil
        }
        streamingPoToken = nil
        expirationDate = nil
        sessionId = nil
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "PoTokenService", code: -408, userInfo: [NSLocalizedDescriptionKey: "BotGuard timed out"])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - BotGuard Data Parsers

    private static func parseChallengeData(from data: Data) throws -> String {
        guard let scrambled = try JSONSerialization.jsonObject(with: data) as? [Any], !scrambled.isEmpty else {
            throw NSError(domain: "PoTokenService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid challenge array"])
        }

        let challengeData: [Any]
        if scrambled.count > 1, let encoded = scrambled[1] as? String {
            let descrambled = try descramble(encoded)
            guard let parsed = try JSONSerialization.jsonObject(with: descrambled) as? [Any] else {
                throw NSError(domain: "PoTokenService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Invalid descrambled challenge"])
            }
            challengeData = parsed
        } else if let plain = scrambled[0] as? [Any] {
            challengeData = plain
        } else {
            throw NSError(domain: "PoTokenService", code: -12, userInfo: [NSLocalizedDescriptionKey: "Missing challenge payload"])
        }

        guard challengeData.count >= 8 else {
            throw NSError(domain: "PoTokenService", code: -13, userInfo: [NSLocalizedDescriptionKey: "Truncated challenge payload"])
        }

        let messageId = challengeData[0] as? String ?? ""
        let safeScript = (challengeData[1] as? [Any])?.compactMap { $0 as? String }.first
        let trustedURL = (challengeData[2] as? [Any])?.compactMap { $0 as? String }.first
        let interpreterHash = challengeData[3] as? String ?? ""
        let program = challengeData[4] as? String ?? ""
        let globalName = challengeData[5] as? String ?? ""
        let clientExperimentsStateBlob = challengeData[7] as? String ?? ""

        let dict: [String: Any] = [
            "messageId": messageId,
            "interpreterJavascript": [
                "privateDoNotAccessOrElseSafeScriptWrappedValue": safeScript as Any,
                "privateDoNotAccessOrElseTrustedResourceUrlWrappedValue": trustedURL as Any
            ],
            "interpreterHash": interpreterHash,
            "program": program,
            "globalName": globalName,
            "clientExperimentsStateBlob": clientExperimentsStateBlob
        ]
        let outData = try JSONSerialization.data(withJSONObject: dict)
        return String(data: outData, encoding: .utf8) ?? "{}"
    }

    private static func parseIntegrityTokenData(from data: Data) throws -> (String, Int64) {
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [Any],
              arr.count >= 2,
              let tokenB64 = arr[0] as? String else {
            throw NSError(domain: "PoTokenService", code: -14, userInfo: [NSLocalizedDescriptionKey: "Invalid integrity token payload"])
        }
        let expiry: Int64
        if let num = arr[1] as? NSNumber {
            expiry = num.int64Value
        } else if let str = arr[1] as? String, let parsed = Int64(str) {
            expiry = parsed
        } else {
            expiry = 3600
        }
        let bytes = try decodeBase64Flexible(tokenB64)
        return (uint8ArrayExpression(for: bytes), expiry)
    }

    private static func descramble(_ scrambled: String) throws -> Data {
        let raw = try decodeBase64Flexible(scrambled)
        return Data(raw.map { UInt8((Int($0) + 97) & 0xFF) })
    }

    private static func decodeBase64Flexible(_ input: String) throws -> Data {
        var mod = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: ".", with: "=")
        let rem = mod.count % 4
        if rem > 0 {
            mod += String(repeating: "=", count: 4 - rem)
        }
        guard let data = Data(base64Encoded: mod, options: [.ignoreUnknownCharacters]) else {
            throw NSError(domain: "PoTokenService", code: -15, userInfo: [NSLocalizedDescriptionKey: "Base64 decode failed"])
        }
        return data
    }

    private static func uint8ArrayExpression(for data: Data) -> String {
        let body = data.map { String($0) }.joined(separator: ",")
        return "new Uint8Array([\(body)])"
    }

    private static func u8CommaStringToBase64URL(_ commaSeparated: String) -> String {
        let bytes = commaSeparated
            .split(separator: ",")
            .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    private static func jsonQuotedString(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let arrStr = String(data: data, encoding: .utf8),
           arrStr.count >= 2 {
            return String(arrStr.dropFirst().dropLast())
        }
        return "\"\""
    }
}

extension PoTokenService: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else {
            return
        }
        let value = dict["value"] as? String ?? ""
        let id = dict["id"] as? String ?? ""
        let err = dict["error"] as? String ?? "Unknown JS error"

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch type {
            case "downloadAndRunBotguard":
                self.handleDownloadAndRunBotguard()
            case "onRunBotguardResult":
                self.handleRunBotguardResult(value)
            case "onMinterCreated":
                self.finishInit(with: nil)
            case "onObtainPoTokenResult":
                let token = Self.u8CommaStringToBase64URL(value)
                self.mintContinuations.removeValue(forKey: id)?.resume(returning: token)
            case "onObtainPoTokenError":
                self.mintContinuations.removeValue(forKey: id)?.resume(
                    throwing: NSError(domain: "PoTokenService", code: -20, userInfo: [NSLocalizedDescriptionKey: err])
                )
            case "onJsInitializationError":
                self.finishInit(
                    with: NSError(domain: "PoTokenService", code: -21, userInfo: [NSLocalizedDescriptionKey: err])
                )
            default:
                break
            }
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
