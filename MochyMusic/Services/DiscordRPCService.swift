import Foundation

/// Discord Gateway v9 WebSocket Rich Presence service.
@MainActor
final class DiscordRPCService: ObservableObject {
    static let shared = DiscordRPCService()

    @Published var isConnected: Bool = false
    @Published var statusText: String = "Off"
    @Published var lastError: String?

    private let gatewayURL = URL(string: "wss://gateway.discord.gg/?v=9&encoding=json")!
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private var sequenceNumber: Int?
    private var heartbeatAcked = true
    private var isReady = false
    private var lastTrack: Track?
    private var lastIsPlaying: Bool = false
    private var lastTime: TimeInterval = 0
    private var lastDuration: TimeInterval = 0

    private static let capabilities = (1 << 4) | (1 << 5) | (1 << 12) | (1 << 16)
    private static let intents = (1 << 12) | (1 << 18) | (1 << 19) | (1 << 22) | (1 << 27) | (1 << 28) | (1 << 29)

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connection Management

    func connectIfNeeded() {
        let settings = AppSettings.shared
        let token = settings.discordToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard settings.discordRPCEnabled else {
            disconnect()
            statusText = "Off"
            return
        }
        guard !settings.offlineMode else {
            disconnect()
            statusText = "Offline"
            return
        }
        guard !token.isEmpty else {
            disconnect()
            statusText = "No Token"
            lastError = "Discord token is empty."
            return
        }
        guard webSocketTask == nil else { return }

        lastError = nil
        statusText = "Connecting…"
        isReady = false
        heartbeatAcked = true
        sequenceNumber = nil

        let task = session.webSocketTask(with: gatewayURL)
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.listenLoop(for: task, token: token)
        }
    }

    func disconnect() {
        if isReady {
            Task {
                await sendPresencePayload(activity: nil)
            }
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isReady = false
        isConnected = false
        statusText = AppSettings.shared.discordRPCEnabled ? "Idle" : "Off"
    }

    func updatePresence(track: Track?, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        lastTrack = track
        lastIsPlaying = isPlaying
        lastTime = currentTime
        lastDuration = duration

        let settings = AppSettings.shared
        guard settings.discordRPCEnabled,
              !settings.offlineMode,
              !settings.discordToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if isConnected { disconnect() }
            return
        }

        if webSocketTask == nil {
            connectIfNeeded()
            return
        }
        guard isReady else { return }

        guard let track else {
            Task { await sendPresencePayload(activity: nil) }
            return
        }

        if !isPlaying && settings.discordClearOnPause {
            Task { await sendPresencePayload(activity: nil) }
            return
        }

        let activity = buildActivity(
            track: track,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration
        )
        Task { await sendPresencePayload(activity: activity) }
    }

    // MARK: - Gateway Loop

    private func listenLoop(for task: URLSessionWebSocketTask, token: String) async {
        while !Task.isCancelled && webSocketTask === task {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    await handleMessageText(text, token: token)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessageText(text, token: token)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled && webSocketTask === task {
                    lastError = error.localizedDescription
                    statusText = "Disconnected"
                    isConnected = false
                    isReady = false
                    heartbeatTask?.cancel()
                    webSocketTask = nil
                }
                break
            }
        }
    }

    private func handleMessageText(_ text: String, token: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let seq = json["s"] as? Int {
            sequenceNumber = seq
        }

        let op = json["op"] as? Int ?? -1
        switch op {
        case 10: // Hello
            let intervalMs = ((json["d"] as? [String: Any])?["heartbeat_interval"] as? Double) ?? 41_250
            startHeartbeat(intervalMs: intervalMs)
            await sendIdentify(token: token)

        case 11: // Heartbeat ACK
            heartbeatAcked = true

        case 1: // Heartbeat requested
            await sendHeartbeat()

        case 7, 9: // Reconnect / Invalid session
            lastError = "Discord gateway requested reconnect (op \(op))."
            disconnect()

        case 0: // Dispatch
            let event = json["t"] as? String
            if event == "READY" {
                isReady = true
                isConnected = true
                statusText = "Live"
                lastError = nil
                if let user = ((json["d"] as? [String: Any])?["user"] as? [String: Any])?["username"] as? String,
                   !user.isEmpty {
                    AppSettings.shared.discordUsername = user
                }
                updatePresence(
                    track: lastTrack,
                    isPlaying: lastIsPlaying,
                    currentTime: lastTime,
                    duration: lastDuration
                )
            }

        default:
            break
        }
    }

    private func startHeartbeat(intervalMs: Double) {
        heartbeatTask?.cancel()
        let seconds = max(5.0, intervalMs / 1000.0)
        heartbeatTask = Task { [weak self] in
            let jitter = Double.random(in: 0.1...0.9) * seconds
            try? await Task.sleep(nanoseconds: UInt64(jitter * 1_000_000_000))
            while !Task.isCancelled {
                guard let self else { return }
                if !self.heartbeatAcked {
                    self.lastError = "Discord heartbeat timed out."
                    self.disconnect()
                    return
                }
                await self.sendHeartbeat()
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    private func sendHeartbeat() async {
        heartbeatAcked = false
        let seqValue: Any = sequenceNumber ?? NSNull()
        await sendFrame(op: 1, data: seqValue)
    }

    private func sendIdentify(token: String) async {
        let payload: [String: Any] = [
            "token": token,
            "capabilities": Self.capabilities,
            "intents": Self.intents,
            "properties": [
                "os": "iOS",
                "browser": "Mochy",
                "device": "iPhone"
            ]
        ]
        await sendFrame(op: 2, data: payload)
    }

    private func sendPresencePayload(activity: [String: Any]?) async {
        let activities: [[String: Any]] = activity.map { [$0] } ?? []
        let payload: [String: Any] = [
            "since": NSNull(),
            "activities": activities,
            "status": "online",
            "afk": false
        ]
        await sendFrame(op: 3, data: payload)
    }

    private func sendFrame(op: Int, data: Any) async {
        guard let task = webSocketTask else { return }
        let frame: [String: Any] = [
            "op": op,
            "d": data
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: frame),
              let text = String(data: jsonData, encoding: .utf8) else {
            return
        }
        try? await task.send(.string(text))
    }

    // MARK: - Activity Payload Builder

    private func buildActivity(
        track: Track,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> [String: Any] {
        let settings = AppSettings.shared
        let activityType: Int
        switch settings.discordActivityType.uppercased() {
        case "PLAYING": activityType = 0
        case "WATCHING": activityType = 3
        case "COMPETING": activityType = 5
        default: activityType = 2 // LISTENING
        }

        var activity: [String: Any] = [
            "name": "Mochy Music",
            "type": activityType,
            "details": String(track.title.prefix(128)),
            "state": String(track.artistsText.prefix(128))
        ]

        if isPlaying && duration > 0 {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let startMs = nowMs - Int64(max(0, currentTime) * 1000)
            let endMs = startMs + Int64(duration * 1000)
            var timestamps: [String: Any] = ["start": startMs]
            if activityType == 2 {
                timestamps["end"] = endMs
            }
            activity["timestamps"] = timestamps
        }

        if settings.discordShowButtons {
            let songURL = track.isLocal
                ? "https://music.youtube.com/search?q=\((track.title + " " + track.artistsText).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                : "https://music.youtube.com/watch?v=\(track.id)"
            activity["buttons"] = ["Listen on YouTube Music", "Mochy Music"]
            activity["metadata"] = [
                "button_urls": [songURL, "https://github.com/realidkroo/Mochy-Music"]
            ]
        }

        return activity
    }
}
