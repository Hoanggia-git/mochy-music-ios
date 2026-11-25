import Foundation
import AVFoundation
import ShazamKit

/// ShazamKit + AVAudioEngine microphone music recognition service.
@MainActor
final class RecognitionService: NSObject, ObservableObject {
    static let shared = RecognitionService()

    @Published var isListening: Bool = false
    @Published var matchedTrack: Track?
    @Published var matchedTitle: String?
    @Published var matchedArtist: String?
    @Published var matchedArtworkURL: URL?
    @Published var shazamID: String?
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0

    private let audioEngine = AVAudioEngine()
    private var shazamSession: SHSession?
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    // MARK: - Public Controls

    func startListening() {
        guard !isListening else { return }

        errorMessage = nil
        matchedTrack = nil
        matchedTitle = nil
        matchedArtist = nil
        matchedArtworkURL = nil
        shazamID = nil

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard granted else {
                    self.errorMessage = "Microphone permission is required to recognize music."
                    return
                }
                self.beginCaptureAndMatching()
            }
        }
    }

    func stopListening() {
        timeoutTask?.cancel()
        timeoutTask = nil

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        shazamSession = nil
        isListening = false
        audioLevel = 0
    }

    // MARK: - Audio Capture & ShazamKit Session

    private func beginCaptureAndMatching() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)

            let session = SHSession()
            session.delegate = self
            self.shazamSession = session

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 2048, format: recordingFormat) { [weak self, weak session] buffer, time in
                session?.matchStreamingBuffer(buffer, at: time)

                let level = Self.calculateRMSLevel(buffer: buffer)
                Task { @MainActor [weak self] in
                    self?.audioLevel = level
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            // Stop automatically after 18 seconds if no match arrives
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 18_000_000_000)
                guard let self, !Task.isCancelled, self.isListening else { return }
                self.stopListening()
                if self.matchedTrack == nil && self.errorMessage == nil {
                    self.errorMessage = "Could not recognize song. Please try again closer to the audio source."
                }
            }
        } catch {
            stopListening()
            errorMessage = "Could not start microphone capture: \(error.localizedDescription)"
        }
    }

    private nonisolated static func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        return min(1.0, max(0.0, rms * 6.0))
    }

    private func handleMatch(_ match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        stopListening()

        let title = item.title ?? "Unknown Track"
        let artist = item.artist ?? "Unknown Artist"
        let artworkURL = item.artworkURL
        let itemShazamID = item.shazamID

        self.matchedTitle = title
        self.matchedArtist = artist
        self.matchedArtworkURL = artworkURL
        self.shazamID = itemShazamID

        Task {
            let query = "\(artist) \(title)"
            if let results = try? await InnerTubeService.shared.searchSongs(query: query),
               let best = results.first {
                self.matchedTrack = best
            } else {
                self.matchedTrack = Track(
                    id: itemShazamID ?? UUID().uuidString,
                    title: title,
                    artists: [Artist(name: artist)],
                    thumbnailURL: artworkURL?.absoluteString
                )
            }
        }
    }
}

// MARK: - SHSessionDelegate

extension RecognitionService: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        Task { @MainActor [weak self] in
            self?.handleMatch(match)
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.isListening else { return }
            if let error {
                self.stopListening()
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
