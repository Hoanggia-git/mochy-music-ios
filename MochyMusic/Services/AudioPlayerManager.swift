import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()

    @Published private(set) var currentTrack: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    @Published private(set) var lyrics: LyricsResult?
    @Published private(set) var isLoadingLyrics: Bool = false

    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffled: Bool = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var artworkImage: UIImage?

    private init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    // MARK: - Playback Controls

    func play(track: Track, inQueue newQueue: [Track]? = nil) {
        if let newQueue, !newQueue.isEmpty {
            self.queue = newQueue
            self.currentIndex = newQueue.firstIndex(where: { $0.id == track.id }) ?? 0
        } else if let existingIndex = queue.firstIndex(where: { $0.id == track.id }) {
            self.currentIndex = existingIndex
        } else {
            self.queue = [track]
            self.currentIndex = 0
        }

        startLoadingCurrentTrack()
    }

    func playNext() {
        guard !queue.isEmpty else { return }
        if isShuffled && queue.count > 1 {
            var nextIdx = Int.random(in: 0..<queue.count)
            while nextIdx == currentIndex {
                nextIdx = Int.random(in: 0..<queue.count)
            }
            currentIndex = nextIdx
        } else if currentIndex + 1 < queue.count {
            currentIndex += 1
        } else if repeatMode == .all {
            currentIndex = 0
        } else {
            return
        }
        startLoadingCurrentTrack()
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
        } else {
            seek(to: 0)
            return
        }
        startLoadingCurrentTrack()
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = clamped
                self?.updateNowPlayingInfo()
            }
        }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Internal Track Loading

    private func startLoadingCurrentTrack() {
        guard queue.indices.contains(currentIndex) else { return }
        let track = queue[currentIndex]

        loadTask?.cancel()
        lyricsTask?.cancel()
        cleanupPlayerObservers()
        player?.pause()

        currentTrack = track
        currentTime = 0
        duration = TimeInterval(track.durationSeconds ?? 0)
        isPlaying = false
        isLoading = true
        errorMessage = nil
        lyrics = nil
        artworkImage = nil

        LibraryStore.shared.recordPlay(track)
        loadLyrics(for: track)
        loadArtwork(for: track)

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let item: AVPlayerItem
                if let localURL = LibraryStore.shared.localAudioURL(for: track.id) {
                    item = AVPlayerItem(url: localURL)
                } else {
                    let stream = try await InnerTubeService.shared.resolveStream(videoId: track.id)
                    try Task.checkCancellation()
                    let asset = AVURLAsset(
                        url: stream.url,
                        options: [
                            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": stream.userAgent]
                        ]
                    )
                    item = AVPlayerItem(asset: asset)
                }

                try Task.checkCancellation()

                let avPlayer = AVPlayer(playerItem: item)
                avPlayer.automaticallyWaitsToMinimizeStalling = true
                self.player = avPlayer
                self.attachObservers(to: avPlayer, item: item)

                avPlayer.play()
                self.isPlaying = true
                self.isLoading = false
                self.updateNowPlayingInfo()

                // Auto-populate Up Next radio tracks if playing a single song
                if self.queue.count == 1 {
                    Task {
                        if let related = try? await InnerTubeService.shared.fetchUpNext(videoId: track.id),
                           !related.isEmpty,
                           self.currentTrack?.id == track.id,
                           self.queue.count == 1 {
                            self.queue.append(contentsOf: related)
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self.isLoading = false
                self.isPlaying = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func loadLyrics(for track: Track) {
        isLoadingLyrics = true
        lyricsTask = Task { [weak self] in
            let result = await LrcLibService.shared.fetchLyrics(for: track)
            guard !Task.isCancelled else { return }
            self?.lyrics = result
            self?.isLoadingLyrics = false
        }
    }

    private func loadArtwork(for track: Track) {
        guard let url = track.artworkURL else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            guard self?.currentTrack?.id == track.id else { return }
            self?.artworkImage = image
            self?.updateNowPlayingInfo()
        }
    }

    private func attachObservers(to avPlayer: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    self.currentTime = seconds
                }
                if let itemDuration = avPlayer.currentItem?.duration {
                    let durSeconds = CMTimeGetSeconds(itemDuration)
                    if durSeconds.isFinite && durSeconds > 0 {
                        self.duration = durSeconds
                    }
                }
                self.isPlaying = avPlayer.timeControlStatus == .playing || avPlayer.rate > 0
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackFinished()
            }
        }
    }

    private func cleanupPlayerObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func handleTrackFinished() {
        if repeatMode == .one {
            seek(to: 0)
            player?.play()
            isPlaying = true
            return
        }
        if currentIndex + 1 < queue.count || repeatMode == .all || (isShuffled && queue.count > 1) {
            playNext()
        } else {
            isPlaying = false
            currentTime = 0
            updateNowPlayingInfo()
        }
    }

    // MARK: - AVAudioSession & Lock Screen Controls

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Audio session failure will surface when attempting playback
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playNext()
            }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playPrevious()
            }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let targetTime = posEvent.positionTime
            Task { @MainActor [weak self] in
                self?.seek(to: targetTime)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let album = track.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
