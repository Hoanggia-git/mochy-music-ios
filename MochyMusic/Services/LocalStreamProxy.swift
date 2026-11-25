import Foundation
import Network

/// Local loopback HTTP/1.1 Range proxy so `AVPlayer` reliably receives custom headers
/// (`User-Agent`, `Origin`, `Referer`, `Cookie`) on every byte request without relying on private `AVURLAsset` options.
final class LocalStreamProxy {
    static let shared = LocalStreamProxy()

    private struct StreamRegistration {
        let remoteURL: URL
        let headers: [String: String]
        let mimeTypeHint: String
    }

    private let queue = DispatchQueue(label: "com.mochyy.localstreamproxy", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var registrations: [String: StreamRegistration] = [:]
    private var registrationOrder: [String] = []
    private let maxRegistrations = 16

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Registers a remote media URL + headers and returns a `http://127.0.0.1:<port>/stream/<id>` URL for `AVPlayer`.
    func proxyURL(for remoteURL: URL, headers: [String: String], mimeTypeHint: String = "audio/mp4") async -> URL? {
        guard let activePort = await ensureRunning() else {
            return nil
        }

        let token = UUID().uuidString.lowercased()
        let ext = fileExtension(for: mimeTypeHint, fallback: remoteURL.pathExtension)
        let entry = StreamRegistration(remoteURL: remoteURL, headers: headers, mimeTypeHint: mimeTypeHint)

        lock.lock()
        registrations[token] = entry
        registrationOrder.append(token)
        while registrationOrder.count > maxRegistrations {
            let evicted = registrationOrder.removeFirst()
            registrations.removeValue(forKey: evicted)
        }
        lock.unlock()

        return URL(string: "http://127.0.0.1:\(activePort)/stream/\(token).\(ext)")
    }

    private func fileExtension(for mimeType: String, fallback: String) -> String {
        let lower = mimeType.lowercased()
        if lower.contains("flac") { return "flac" }
        if lower.contains("mpeg") || lower.contains("mp3") { return "mp3" }
        if lower.contains("aac") { return "aac" }
        if lower.contains("video/mp4") { return "mp4" }
        if lower.contains("mp4") || lower.contains("m4a") { return "m4a" }
        return fallback.isEmpty ? "m4a" : fallback
    }

    private func ensureRunning() async -> UInt16? {
        if let existing = lock.withLock({ listener != nil && port > 0 ? port : nil }) {
            return existing
        }

        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                if let readyPort = self.lock.withLock({ self.listener != nil && self.port > 0 ? self.port : nil }) {
                    continuation.resume(returning: readyPort)
                    return
                }

                do {
                    let params = NWParameters.tcp
                    params.allowLocalEndpointReuse = true
                    let nwListener = try NWListener(using: params, on: .any)
                    var resumed = false

                    nwListener.newConnectionHandler = { [weak self] conn in
                        self?.handleConnection(conn)
                    }

                    nwListener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            let boundPort = nwListener.port?.rawValue ?? 0
                            self.lock.lock()
                            self.port = boundPort
                            self.lock.unlock()
                            if !resumed {
                                resumed = true
                                continuation.resume(returning: boundPort > 0 ? boundPort : nil)
                            }
                        case .failed, .cancelled:
                            self.lock.lock()
                            if self.listener === nwListener {
                                self.listener = nil
                                self.port = 0
                            }
                            self.lock.unlock()
                            if !resumed {
                                resumed = true
                                continuation.resume(returning: nil)
                            }
                        default:
                            break
                        }
                    }

                    self.lock.lock()
                    self.listener = nwListener
                    self.lock.unlock()
                    nwListener.start(queue: self.queue)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection, buffer: Data())
    }

    private func receiveHTTPRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = accumulated[..<headerEnd.lowerBound]
                if let headerText = String(data: headerData, encoding: .utf8) {
                    self.processRequest(headerText: headerText, on: connection)
                } else {
                    self.sendErrorResponse(status: "400 Bad Request", on: connection)
                }
                return
            }

            if isComplete || accumulated.count > 65_536 {
                connection.cancel()
                return
            }

            self.receiveHTTPRequest(on: connection, buffer: accumulated)
        }
    }

    private func processRequest(headerText: String, on connection: NWConnection) {
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendErrorResponse(status: "400 Bad Request", on: connection)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendErrorResponse(status: "400 Bad Request", on: connection)
            return
        }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        guard method == "GET" || method == "HEAD" else {
            sendErrorResponse(status: "405 Method Not Allowed", on: connection)
            return
        }

        // Parse `/stream/<uuid>.ext`
        let cleanPath = path.components(separatedBy: "?").first ?? path
        let lastComponent = cleanPath.split(separator: "/").last.map(String.init) ?? ""
        let token = lastComponent.components(separatedBy: ".").first ?? lastComponent

        guard let registration = lock.withLock({ registrations[token] }) else {
            sendErrorResponse(status: "404 Not Found", on: connection)
            return
        }

        var rangeHeader: String?
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if name == "range" {
                    rangeHeader = value
                }
            }
        }

        Task {
            await self.forwardUpstream(
                registration: registration,
                method: method,
                rangeHeader: rangeHeader,
                on: connection
            )
        }
    }

    private func forwardUpstream(
        registration: StreamRegistration,
        method: String,
        rangeHeader: String?,
        on connection: NWConnection
    ) async {
        var req = URLRequest(url: registration.remoteURL)
        req.httpMethod = method
        req.timeoutInterval = 20

        for (key, value) in registration.headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if req.value(forHTTPHeaderField: "Accept") == nil {
            req.setValue("*/*", forHTTPHeaderField: "Accept")
        }
        if let rangeHeader {
            req.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        do {
            if method == "HEAD" {
                let (_, response) = try await urlSession.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    sendErrorResponse(status: "502 Bad Gateway", on: connection)
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    sendErrorResponse(status: "\(http.statusCode) Upstream Error", on: connection)
                    return
                }
                let headBytes = buildResponseHeader(from: http, mimeTypeHint: registration.mimeTypeHint)
                sendAndClose(headBytes, on: connection)
                return
            }

            let (asyncBytes, response) = try await urlSession.bytes(for: req)
            guard let http = response as? HTTPURLResponse else {
                sendErrorResponse(status: "502 Bad Gateway", on: connection)
                return
            }
            guard (200...299).contains(http.statusCode) else {
                sendErrorResponse(status: "\(http.statusCode) Upstream Error", on: connection)
                return
            }

            let headerBytes = buildResponseHeader(from: http, mimeTypeHint: registration.mimeTypeHint)
            try await sendData(headerBytes, on: connection)

            var chunk = Data()
            chunk.reserveCapacity(32_768)
            for try await byte in asyncBytes {
                if connection.state == .cancelled { break }
                chunk.append(byte)
                if chunk.count >= 32_768 {
                    let toSend = chunk
                    chunk.removeAll(keepingCapacity: true)
                    try await sendData(toSend, on: connection)
                }
            }
            if !chunk.isEmpty && connection.state != .cancelled {
                try await sendData(chunk, on: connection)
            }
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }

    private func buildResponseHeader(from http: HTTPURLResponse, mimeTypeHint: String) -> Data {
        let statusLine = http.statusCode == 206 ? "HTTP/1.1 206 Partial Content" : "HTTP/1.1 \(http.statusCode) OK"
        var lines = [statusLine, "Connection: close", "Accept-Ranges: bytes"]

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? mimeTypeHint
        lines.append("Content-Type: \(contentType)")

        if let contentLength = http.value(forHTTPHeaderField: "Content-Length") {
            lines.append("Content-Length: \(contentLength)")
        } else if http.expectedContentLength > 0 {
            lines.append("Content-Length: \(http.expectedContentLength)")
        }

        if let contentRange = http.value(forHTTPHeaderField: "Content-Range") {
            lines.append("Content-Range: \(contentRange)")
        }

        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private func sendErrorResponse(status: String, on connection: NWConnection) {
        let payload = Data("HTTP/1.1 \(status)\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)
        sendAndClose(payload, on: connection)
    }

    private func sendAndClose(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendData(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
