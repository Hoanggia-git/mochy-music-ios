import Foundation
import JavaScriptCore

/// Solves YouTube `signatureCipher` and `n`-parameter challenges natively via `JavaScriptCore`
/// using bundled `meriyah.js`, `astring.js`, and `yt.solver.core.js` extracted from Mochy Android.
actor CipherSolverService {
    static let shared = CipherSolverService()

    private enum Constants {
        static let iframeAPIURL = "https://www.youtube.com/iframe_api"
        static let playerJSTemplate = "https://www.youtube.com/s/player/%@/player_ias.vflset/en_GB/base.js"
        static let cacheTTL: TimeInterval = 6 * 60 * 60
        static let userAgent = "Mozilla/5.0"
    }

    private var cachedHash: String?
    private var cachedPlayerJS: String?
    private var cachedSignatureTimestamp: Int?
    private var cachedPreprocessedPlayer: String?
    private var cachedCacheDate: Date?

    private var jsContext: JSContext?

    // MARK: - Public API

    func signatureTimestamp() async -> Int? {
        _ = await ensurePlayerScript()
        return cachedSignatureTimestamp
    }

    func prewarm() async {
        _ = await ensurePlayerScript()
    }

    func deobfuscateSignatureCipher(_ signatureCipher: String) async -> URL? {
        let params = parseQueryParams(signatureCipher)
        guard let obfuscatedSig = params["s"],
              let baseURLString = params["url"],
              !obfuscatedSig.isEmpty,
              !baseURLString.isEmpty else {
            return nil
        }

        let sp = params["sp"] ?? "signature"
        guard let solved = await solveChallenges(type: "sig", challenges: [obfuscatedSig]),
              let sig = solved[obfuscatedSig],
              !sig.isEmpty else {
            return nil
        }

        let sep = baseURLString.contains("?") ? "&" : "?"
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let encodedSig = sig.addingPercentEncoding(withAllowedCharacters: allowed) ?? sig
        return URL(string: "\(baseURLString)\(sep)\(sp)=\(encodedSig)")
    }

    func transformNParam(in url: URL) async -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var items = components.queryItems,
              let idx = items.firstIndex(where: { $0.name == "n" }),
              let nValue = items[idx].value,
              !nValue.isEmpty else {
            return url
        }

        guard let solved = await solveChallenges(type: "n", challenges: [nValue]),
              let transformed = solved[nValue],
              !transformed.isEmpty else {
            return url
        }

        items[idx].value = transformed
        components.queryItems = items
        return components.url ?? url
    }

    // MARK: - JS Solver Engine

    private func solveChallenges(type: String, challenges: [String]) async -> [String: String]? {
        guard !challenges.isEmpty,
              let playerJS = await ensurePlayerScript(),
              let ctx = ensureJSContext() else {
            return nil
        }

        let requestPayload: [String: Any]
        if let preprocessed = cachedPreprocessedPlayer {
            requestPayload = [
                "type": "preprocessed",
                "preprocessed_player": preprocessed,
                "requests": [
                    ["type": type, "challenges": challenges]
                ]
            ]
        } else {
            requestPayload = [
                "type": "player",
                "player": playerJS,
                "output_preprocessed": true,
                "requests": [
                    ["type": type, "challenges": challenges]
                ]
            ]
        }

        guard let inputValue = ctx.objectForKeyedSubscript("jsc")?.call(withArguments: [requestPayload]),
              let outputDict = inputValue.toDictionary() as? [String: Any],
              (outputDict["type"] as? String) == "result" else {
            return nil
        }

        if let preprocessed = outputDict["preprocessed_player"] as? String, !preprocessed.isEmpty {
            cachedPreprocessedPlayer = preprocessed
        }

        guard let responses = outputDict["responses"] as? [[String: Any]],
              let first = responses.first,
              (first["type"] as? String) == "result",
              let data = first["data"] as? [String: String] else {
            return nil
        }
        return data
    }

    private func ensureJSContext() -> JSContext? {
        if let jsContext {
            return jsContext
        }

        guard let meriyahURL = Bundle.main.url(forResource: "meriyah", withExtension: "js"),
              let astringURL = Bundle.main.url(forResource: "astring", withExtension: "js"),
              let coreURL = Bundle.main.url(forResource: "yt.solver.core", withExtension: "js"),
              let meriyahCode = try? String(contentsOf: meriyahURL, encoding: .utf8),
              let astringCode = try? String(contentsOf: astringURL, encoding: .utf8),
              let coreCode = try? String(contentsOf: coreURL, encoding: .utf8) else {
            return nil
        }

        let ctx = JSContext()
        ctx?.exceptionHandler = { _, _ in }
        ctx?.evaluateScript("var window = globalThis; var self = globalThis;")
        ctx?.evaluateScript(meriyahCode)
        ctx?.evaluateScript(astringCode)
        ctx?.evaluateScript(coreCode)

        guard ctx?.objectForKeyedSubscript("jsc")?.isObject == true else {
            return nil
        }
        jsContext = ctx
        return ctx
    }

    // MARK: - Player Script Fetching & Cache

    private func ensurePlayerScript() async -> String? {
        if let cachedPlayerJS, let cachedCacheDate,
           Date().timeIntervalSince(cachedCacheDate) < Constants.cacheTTL {
            return cachedPlayerJS
        }

        if let disk = loadFromDiskCache() {
            cachedHash = disk.hash
            cachedPlayerJS = disk.playerJS
            cachedSignatureTimestamp = Self.extractSignatureTimestamp(from: disk.playerJS)
            cachedCacheDate = disk.date
            return disk.playerJS
        }

        guard let hash = await fetchPlayerHash(),
              let playerJS = await downloadPlayerJS(hash: hash) else {
            return cachedPlayerJS
        }

        cachedHash = hash
        cachedPlayerJS = playerJS
        cachedSignatureTimestamp = Self.extractSignatureTimestamp(from: playerJS)
        cachedPreprocessedPlayer = nil
        cachedCacheDate = Date()
        saveToDiskCache(hash: hash, playerJS: playerJS)
        return playerJS
    }

    private func fetchPlayerHash() async -> String? {
        guard let url = URL(string: Constants.iframeAPIURL) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let body = String(data: data, encoding: .utf8) else {
            return nil
        }

        let pattern = #"\\?/s\\?/player\\?/([a-zA-Z0-9_-]+)\\?/"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: body) else {
            return nil
        }
        return String(body[range])
    }

    private func downloadPlayerJS(hash: String) async -> String? {
        let urlString = String(format: Constants.playerJSTemplate, hash)
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 25

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func extractSignatureTimestamp(from playerJS: String) -> Int? {
        let patterns = [
            #"signatureTimestamp\s*:\s*(\d+)"#,
            #"sts\s*:\s*(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: playerJS, range: NSRange(playerJS.startIndex..., in: playerJS)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: playerJS),
                  let val = Int(playerJS[range]) else {
                continue
            }
            return val
        }
        return nil
    }

    private func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("cipher_cache")
    }

    private func loadFromDiskCache() -> (hash: String, playerJS: String, date: Date)? {
        guard let dir = cacheDirectory() else { return nil }
        let metaURL = dir.appendingPathComponent("current_hash.txt")
        guard let meta = try? String(contentsOf: metaURL, encoding: .utf8) else { return nil }
        let lines = meta.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2,
              let ts = Double(lines[1]) else {
            return nil
        }
        let date = Date(timeIntervalSince1970: ts)
        guard Date().timeIntervalSince(date) < Constants.cacheTTL else {
            return nil
        }
        let hash = String(lines[0])
        let scriptURL = dir.appendingPathComponent("player_\(hash).js")
        guard let script = try? String(contentsOf: scriptURL, encoding: .utf8), !script.isEmpty else {
            return nil
        }
        return (hash, script, date)
    }

    private func saveToDiskCache(hash: String, playerJS: String) {
        guard let dir = cacheDirectory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let existing = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in existing where file.lastPathComponent.hasPrefix("player_") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        try? playerJS.write(to: dir.appendingPathComponent("player_\(hash).js"), atomically: true, encoding: .utf8)
        let meta = "\(hash)\n\(Date().timeIntervalSince1970)"
        try? meta.write(to: dir.appendingPathComponent("current_hash.txt"), atomically: true, encoding: .utf8)
    }

    private func parseQueryParams(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let rawVal = String(parts[1]).replacingOccurrences(of: "+", with: " ")
            let val = rawVal.removingPercentEncoding ?? rawVal
            result[key] = val
        }
        return result
    }
}
