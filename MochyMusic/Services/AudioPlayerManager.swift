import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Full-featured AVFoundation audio player with queue management, crossfade, normalization, Now Playing & remote commands, and sleep timer.
@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()

    // MARK: - Published State

    @Published var currentTrack: Track?
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var history: [Track] = []
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffled: Bool = false
    @Published var playbackSpeed: Float = 1.0
    @Published var sleepTimerRemaining: TimeInterval?
    @Published var currentStream: ResolvedStream?

    // MARK: - Private AVPlayer & State

    private var player: AVPlayer?
    private var fadeOutPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    private var unshuffledQueue: [Track] = []
    private var loadTask: Task<Void, Never>?
    private var crossfadeTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var didCrossfadeCurrentTrack = false
    private var hasScrobbledCurrentTrack = false
    private var trackStartDate = Date()
    private var lastAccumulatedTime: TimeInterval = 0
    private var baseTrackVolume: Float = 1.0

    private let artworkCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()

    private override init() {
        super.init()
        configureAudioSession()
        setupRemoteCommandCenter()
        observeAudioInterruptions()
    }

    // MARK: - Audio Session & Remote Commands

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = AppSettings.shared.mixWithOtherApps ? [.mixWithOthers] : []
        do {
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            errorMessage = "Audio session configuration failed: \(error.localizedDescription)"
        }
    }

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.play() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.next() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.previous() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: posEvent.positionTime) }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor [weak self] in self?.skipForward(interval) }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor [weak self] in self?.skipBackward(interval) }
            return .success
        }

        center.likeCommand.isEnabled = true
        center.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let track = self?.currentTrack else { return }
                LibraryStore.shared.toggleFavorite(track)
                center.likeCommand.isActive = LibraryStore.shared.isFavorite(track)
            }
            return .success
        }
    }

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                switch type {
                case .began:
                    self.pause()
                case .ended:
                    let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.play()
                    }
                @unknown default:
                    break
                }
            }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                  reason == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in
                self?.pause()
            }
        }
    }

    // MARK: - Playback Controls

    func play(track: Track) {
        play(tracks: [track], startIndex: 0)
    }

    func play(tracks: [Track], startIndex: Int = 0) {
        guard !tracks.isEmpty else { return }
        let safeIndex = max(0, min(startIndex, tracks.count - 1))

        unshuffledQueue = tracks
        if isShuffled {
            var remaining = tracks
            let chosen = remaining.remove(at: safeIndex)
            remaining.shuffle()
            queue = [chosen] + remaining
            currentIndex = 0
        } else {
            queue = tracks
            currentIndex = safeIndex
        }

        loadCurrentTrack()
    }

    func play() {
        guard let player else {
            if currentTrack != nil {
                loadCurrentTrack()
            }
            return
        }
        configureAudioSession()
        player.play()
        player.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()
        DiscordRPCService.shared.updatePresence(
            track: currentTrack,
            isPlaying: true,
            currentTime: currentTime,
            duration: duration
        )
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        DiscordRPCService.shared.updatePresence(
            track: currentTrack,
            isPlaying: false,
            currentTime: currentTime,
            duration: duration
        )
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        loadTask?.cancel()
        crossfadeTask?.cancel()
        tearDownPlayer(player)
        tearDownPlayer(fadeOutPlayer)
        player = nil
        fadeOutPlayer = nil
        isPlaying = false
        isLoading = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        DiscordRPCService.shared.updatePresence(track: nil, isPlaying: false, currentTime: 0, duration: 0)
    }

    func next() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            seek(to: 0)
            play()
            return
        }

        if currentIndex + 1 < queue.count {
            currentIndex += 1
            loadCurrentTrack()
        } else if repeatMode == .all {
            currentIndex = 0
            loadCurrentTrack()
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
            loadCurrentTrack()
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            loadCurrentTrack()
        } else {
            seek(to: 0)
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        lastAccumulatedTime = clamped
        updateNowPlayingInfo()
        DiscordRPCService.shared.updatePresence(
            track: currentTrack,
            isPlaying: isPlaying,
            currentTime: clamped,
            duration: duration
        )
    }

    func skipForward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    func skipBackward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    func setPlaybackSpeed(_ speed: Float) {
        let clamped = max(0.5, min(2.0, speed))
        playbackSpeed = clamped
        if isPlaying {
            player?.rate = clamped
        }
        updateNowPlayingInfo()
    }

    // MARK: - Queue & Modes

    func toggleShuffle() {
        isShuffled.toggle()
        AppSettings.shared.shuffleMode = isShuffled

        guard !queue.isEmpty else { return }
        let activeTrack = queue.indices.contains(currentIndex) ? queue[currentIndex] : currentTrack

        if isShuffled {
            unshuffledQueue = queue
            var others = queue
            if let activeTrack, let idx = others.firstIndex(where: { $0.id == activeTrack.id }) {
                let current = others.remove(at: idx)
                others.shuffle()
                queue = [current] + others
                currentIndex = 0
            } else {
                queue.shuffle()
                currentIndex = 0
            }
        } else if !unshuffledQueue.isEmpty {
            queue = unshuffledQueue
            if let activeTrack, let idx = queue.firstIndex(where: { $0.id == activeTrack.id }) {
                currentIndex = idx
            } else {
                currentIndex = 0
            }
        }
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    func addToQueue(_ track: Track) {
        if queue.isEmpty {
            play(track: track)
            return
        }
        queue.append(track)
        unshuffledQueue.append(track)
    }

    func playNext(_ track: Track) {
        if queue.isEmpty {
            play(track: track)
            return
        }
        let insertIndex = min(currentIndex + 1, queue.count)
        queue.insert(track, at: insertIndex)
        unshuffledQueue.append(track)
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let removed = queue.remove(at: index)
        unshuffledQueue.removeAll { $0.id == removed.id }

        if index < currentIndex {
            currentIndex = max(0, currentIndex - 1)
        } else if index == currentIndex {
            if queue.isEmpty {
                stop()
                currentTrack = nil
            } else {
                currentIndex = min(currentIndex, queue.count - 1)
                loadCurrentTrack()
            }
        }
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        let activeId = currentTrack?.id
        queue.move(fromOffsets: source, toOffset: destination)
        if let activeId, let newIndex = queue.firstIndex(where: { $0.id == activeId }) {
            currentIndex = newIndex
        }
    }

    func clearQueue() {
        if let currentTrack {
            queue = [currentTrack]
            unshuffledQueue = [currentTrack]
            currentIndex = 0
        } else {
            queue.removeAll()
            unshuffledQueue.removeAll()
            currentIndex = 0
        }
    }

    // MARK: - Sleep Timer

    func startSleepTimer(minutes: Int) {
        startSleepTimer(seconds: TimeInterval(max(1, minutes) * 60))
    }

    func startSleepTimer(seconds: TimeInterval) {
        cancelSleepTimer()
        guard seconds > 0 else { return }
        sleepTimerRemaining = seconds

        sleepTimerTask = Task { [weak self] in
            while let self, let remaining = self.sleepTimerRemaining, remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                let updated = max(0, remaining - 1)
                self.sleepTimerRemaining = updated
                if updated <= 0 {
                    self.sleepTimerRemaining = nil
                    self.pause()
                    break
                }
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemaining = nil
    }

    // MARK: - Track Loading & Crossfade

    private func loadCurrentTrack(isCrossfadeHandoff: Bool = false) {
        guard queue.indices.contains(currentIndex) else { return }
        let track = queue[currentIndex]

        loadTask?.cancel()
        errorMessage = nil
        isLoading = true
        didCrossfadeCurrentTrack = false
        hasScrobbledCurrentTrack = false
        trackStartDate = Date()
        lastAccumulatedTime = 0
        currentTime = 0
        duration = TimeInterval(track.durationSeconds ?? 0)
        currentTrack = track

        if !history.contains(where: { $0.id == track.id }) {
            history.insert(track, at: 0)
            if history.count > 100 { history = Array(history.prefix(100)) }
        } else {
            history.removeAll { $0.id == track.id }
            history.insert(track, at: 0)
        }

        LibraryStore.shared.recordPlay(track: track)
        MPRemoteCommandCenter.shared().likeCommand.isActive = LibraryStore.shared.isFavorite(track)
        LyricsManager.shared.loadLyricsInBackground(for: track)

        if AppSettings.shared.lastFmEnabled && AppSettings.shared.lastFmNowPlaying {
            Task { await ScrobbleService.shared.updateNowPlaying(track: track) }
        }

        // Auto-expand queue near the end when autoLoadMore / infiniteQueue is active
        if (AppSettings.shared.autoLoadMore || AppSettings.shared.infiniteQueue) &&
            !track.isLocal &&
            currentIndex >= max(0, queue.count - 2) {
            Task {
                await appendUpNextIfNeeded(for: track)
            }
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await self.preparePlayerItem(for: track)
                if Task.isCancelled {
                    prepared.player.pause()
                    prepared.player.replaceCurrentItem(with: nil)
                    return
                }

                let newPlayer = prepared.player
                let playerItem = prepared.item
                let resolvedLoudness = prepared.loudnessDb
                self.currentStream = prepared.stream

                // Volume normalization relative to -14 LUFS
                let targetVolume = self.normalizedVolume(loudnessDb: resolvedLoudness)
                self.baseTrackVolume = targetVolume

                if isCrossfadeHandoff, let outgoing = self.player {
                    self.tearDownPlayer(self.fadeOutPlayer)
                    self.fadeOutPlayer = outgoing
                    self.player = nil
                    self.runCrossfadeOut(on: outgoing, duration: AppSettings.shared.crossfadeDuration)
                } else {
                    self.tearDownPlayer(self.player)
                    self.player = nil
                }

                newPlayer.automaticallyWaitsToMinimizeStalling = true
                newPlayer.volume = isCrossfadeHandoff ? 0.0 : targetVolume
                self.player = newPlayer

                self.attachObservers(to: newPlayer, item: playerItem)
                self.configureAudioSession()

                newPlayer.play()
                newPlayer.rate = self.playbackSpeed
                self.isPlaying = true
                self.isLoading = false

                if isCrossfadeHandoff {
                    self.runCrossfadeIn(on: newPlayer, targetVolume: targetVolume, duration: AppSettings.shared.crossfadeDuration)
                }

                if let assetDuration = try? await playerItem.asset.load(.duration) {
                    let seconds = CMTimeGetSeconds(assetDuration)
                    if seconds.isFinite && seconds > 0 {
                        self.duration = seconds
                    }
                }

                self.updateNowPlayingInfo()
                self.loadArtworkForNowPlaying(track: track)
                DiscordRPCService.shared.updatePresence(
                    track: track,
                    isPlaying: true,
                    currentTime: 0,
                    duration: self.duration
                )
            } catch {
                if Task.isCancelled { return }
                self.isLoading = false
                self.isPlaying = false
                self.errorMessage = error.localizedDescription
                if !AppSettings.shared.dontSkipOnFailure && self.currentIndex + 1 < self.queue.count {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled {
                        self.next()
                    }
                }
            }
        }
    }

    private struct PreparedPlayback {
        let player: AVPlayer
        let item: AVPlayerItem
        let stream: ResolvedStream
        let loudnessDb: Double?
    }

    private func preparePlayerItem(for track: Track) async throws -> PreparedPlayback {
        if let localURL = track.resolvedLocalURL, FileManager.default.fileExists(atPath: localURL.path) {
            let asset = AVURLAsset(url: localURL)
            let item = AVPlayerItem(asset: asset)
            if EqualizerService.shared.isEnabled,
               let mix = await EqualizerService.shared.createAudioMix(for: asset) {
                item.audioMix = mix
            }
            let stream = ResolvedStream(
                url: localURL,
                isAudioOnly: true,
                mimeType: "audio/mp4",
                codecs: localURL.pathExtension.lowercased(),
                sourceLabel: "Local File",
                qualityBadgeText: localURL.pathExtension.uppercased()
            )
            return PreparedPlayback(player: AVPlayer(playerItem: item), item: item, stream: stream, loudnessDb: nil)
        }

        if let downloadedURL = LibraryStore.shared.localFileURL(forTrackId: track.id) {
            let asset = AVURLAsset(url: downloadedURL)
            let item = AVPlayerItem(asset: asset)
            if EqualizerService.shared.isEnabled,
               let mix = await EqualizerService.shared.createAudioMix(for: asset) {
                item.audioMix = mix
            }
            let stream = ResolvedStream(
                url: downloadedURL,
                isAudioOnly: true,
                mimeType: "audio/mp4",
                codecs: downloadedURL.pathExtension.lowercased(),
                sourceLabel: "Downloaded",
                qualityBadgeText: "Offline · AAC"
            )
            return PreparedPlayback(player: AVPlayer(playerItem: item), item: item, stream: stream, loudnessDb: nil)
        }

        let orderedSources = streamSourceOrder(for: track)
        var lastError: Error = InnerTubeError.noPlayableStream

        for resolver in orderedSources {
            if Task.isCancelled { throw CancellationError() }
            do {
                let stream = try await resolver()
                if Task.isCancelled { throw CancellationError() }

                let (candidatePlayer, candidateItem) = try await buildAndValidateRemoteItem(for: stream)
                return PreparedPlayback(player: candidatePlayer, item: candidateItem, stream: stream, loudnessDb: stream.loudnessDb)
            } catch {
                if Task.isCancelled { throw error }
                lastError = error
            }
        }

        throw lastError
    }

    private func buildAndValidateRemoteItem(for stream: ResolvedStream) async throws -> (AVPlayer, AVPlayerItem) {
        let isHLS = stream.mimeType.lowercased().contains("mpegurl") || stream.url.pathExtension.lowercased() == "m3u8"

        var playbackURL = stream.url
        if !isHLS {
            var mergedHeaders = stream.httpHeaders
            if let ua = stream.userAgent, !ua.isEmpty, mergedHeaders["User-Agent"] == nil {
                mergedHeaders["User-Agent"] = ua
            }
            if !mergedHeaders.isEmpty,
               let proxied = await LocalStreamProxy.shared.proxyURL(for: stream.url, headers: mergedHeaders, mimeTypeHint: stream.mimeType) {
                playbackURL = proxied
            }
        }

        let asset = AVURLAsset(url: playbackURL)
        let item = AVPlayerItem(asset: asset)
        if !isHLS && EqualizerService.shared.isEnabled,
           let mix = await EqualizerService.shared.createAudioMix(for: asset) {
            item.audioMix = mix
        }

        let candidatePlayer = AVPlayer(playerItem: item)
        candidatePlayer.volume = 0
        do {
            try await waitUntilReady(item: item)
            return (candidatePlayer, item)
        } catch {
            candidatePlayer.pause()
            candidatePlayer.replaceCurrentItem(with: nil)
            throw error
        }
    }

    private func waitUntilReady(item: AVPlayerItem) async throws {
        if item.status == .readyToPlay { return }
        if item.status == .failed {
            throw item.error ?? InnerTubeError.noPlayableStream
        }

        final class ReadinessBox {
            let lock = NSLock()
            var settled = false
            var observation: NSKeyValueObservation?
            var continuation: CheckedContinuation<Void, Error>?

            func finish(result: Result<Void, Error>) {
                lock.lock()
                guard !settled else {
                    lock.unlock()
                    return
                }
                settled = true
                let obs = observation
                observation = nil
                let cont = continuation
                continuation = nil
                lock.unlock()

                obs?.invalidate()
                if let cont {
                    switch result {
                    case .success: cont.resume()
                    case .failure(let err): cont.resume(throwing: err)
                    }
                }
            }
        }

        let box = ReadinessBox()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        box.lock.lock()
                        box.continuation = continuation
                        box.observation = item.observe(\.status, options: [.initial, .new]) { observedItem, _ in
                            switch observedItem.status {
                            case .readyToPlay:
                                box.finish(result: .success(()))
                            case .failed:
                                box.finish(result: .failure(observedItem.error ?? InnerTubeError.noPlayableStream))
                            case .unknown:
                                break
                            @unknown default:
                                break
                            }
                        }
                        box.lock.unlock()
                    }
                } onCancel: {
                    box.finish(result: .failure(CancellationError()))
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 14_000_000_000)
                throw NSError(domain: "AudioPlayerManager", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Stream timed out while buffering"])
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func streamSourceOrder(for track: Track) -> [() async throws -> ResolvedStream] {
        let settings = AppSettings.shared
        let source = settings.preferredAudioSource.lowercased()
        let quality = settings.audioQuality

        let youtubeResolver: () async throws -> ResolvedStream = {
            try await InnerTubeService.shared.resolveStream(videoId: track.id, quality: quality)
        }
        let monochromeResolver: () async throws -> ResolvedStream = {
            try await MonochromeService.shared.resolveStream(for: track)
        }
        let jiosaavnResolver: () async throws -> ResolvedStream = {
            try await JioSaavnService.shared.resolveStream(for: track, quality: settings.jiosaavnQuality)
        }

        var resolvers: [() async throws -> ResolvedStream] = []
        if source == "monochrome" && settings.monochromeEnabled {
            resolvers.append(monochromeResolver)
            resolvers.append(youtubeResolver)
            if settings.jiosaavnEnabled { resolvers.append(jiosaavnResolver) }
        } else if source == "jiosaavn" && settings.jiosaavnEnabled {
            resolvers.append(jiosaavnResolver)
            resolvers.append(youtubeResolver)
            if settings.monochromeEnabled { resolvers.append(monochromeResolver) }
        } else if settings.monochromeEnabled && (quality == .lossless || quality == .hiResLossless) {
            resolvers.append(monochromeResolver)
            resolvers.append(youtubeResolver)
            if settings.jiosaavnEnabled { resolvers.append(jiosaavnResolver) }
        } else {
            resolvers.append(youtubeResolver)
            if settings.monochromeEnabled { resolvers.append(monochromeResolver) }
            if settings.jiosaavnEnabled { resolvers.append(jiosaavnResolver) }
        }
        return resolvers
    }

    private func normalizedVolume(loudnessDb: Double?) -> Float {
        guard AppSettings.shared.normalization, let loudnessDb else { return 1.0 }
        // YouTube loudnessDb is relative to -14 LUFS. Attenuate hot tracks to prevent clipping.
        let gainDb = -loudnessDb
        let clampedDb = max(-12.0, min(0.0, gainDb))
        return Float(pow(10.0, clampedDb / 20.0))
    }

    private func runCrossfadeOut(on outgoing: AVPlayer, duration fadeSeconds: TimeInterval) {
        let steps = 20
        let total = max(1.0, fadeSeconds)
        let startVolume = outgoing.volume
        Task { [weak self] in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64((total / Double(steps)) * 1_000_000_000))
                let progress = Float(step) / Float(steps)
                outgoing.volume = max(0, startVolume * (1.0 - progress))
            }
            self?.tearDownPlayer(outgoing)
            if self?.fadeOutPlayer === outgoing {
                self?.fadeOutPlayer = nil
            }
        }
    }

    private func runCrossfadeIn(on incoming: AVPlayer, targetVolume: Float, duration fadeSeconds: TimeInterval) {
        crossfadeTask?.cancel()
        let steps = 20
        let total = max(1.0, fadeSeconds)
        crossfadeTask = Task {
            for step in 1...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64((total / Double(steps)) * 1_000_000_000))
                let progress = Float(step) / Float(steps)
                incoming.volume = targetVolume * progress
            }
            incoming.volume = targetVolume
        }
    }

    private func attachObservers(to player: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
            let seconds = CMTimeGetSeconds(cmTime)
            guard seconds.isFinite else { return }
            Task { @MainActor [weak self] in
                self?.handlePeriodicTimeUpdate(seconds, item: item)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.didCrossfadeCurrentTrack {
                    self.next()
                }
            }
        }

        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.errorMessage = err?.localizedDescription ?? "Stream playback failed"
            }
        }

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            let message = observedItem.error?.localizedDescription ?? "Playback failed"
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.errorMessage = message
            }
        }
    }

    private func handlePeriodicTimeUpdate(_ seconds: TimeInterval, item: AVPlayerItem) {
        currentTime = seconds

        let itemDuration = CMTimeGetSeconds(item.duration)
        if itemDuration.isFinite && itemDuration > 0 {
            duration = itemDuration
        }

        if let track = currentTrack {
            let delta = seconds - lastAccumulatedTime
            if delta > 0 && delta < 2.0 {
                LibraryStore.shared.recordListeningTime(delta, for: track)
            }
            lastAccumulatedTime = seconds

            // Last.fm Scrobble trigger (50% or 4 minutes, respecting min duration)
            if AppSettings.shared.lastFmEnabled && !hasScrobbledCurrentTrack {
                let effectiveDuration = duration > 0 ? duration : TimeInterval(track.durationSeconds ?? 0)
                let minDuration = TimeInterval(AppSettings.shared.scrobbleMinSongDuration)
                let threshold = min(effectiveDuration * AppSettings.shared.scrobbleDelayPercent, 240.0)
                if effectiveDuration >= minDuration && seconds >= max(15.0, threshold) {
                    hasScrobbledCurrentTrack = true
                    let started = trackStartDate
                    Task {
                        await ScrobbleService.shared.scrobble(track: track, timestamp: started)
                    }
                }
            }
        }

        // Crossfade trigger before track ends
        let settings = AppSettings.shared
        if settings.crossfadeEnabled &&
            !didCrossfadeCurrentTrack &&
            repeatMode != .one &&
            duration > settings.crossfadeDuration + 2.0 &&
            (duration - seconds) <= settings.crossfadeDuration &&
            (currentIndex + 1 < queue.count || repeatMode == .all) {
            didCrossfadeCurrentTrack = true
            if currentIndex + 1 < queue.count {
                currentIndex += 1
            } else {
                currentIndex = 0
            }
            loadCurrentTrack(isCrossfadeHandoff: true)
            return
        }

        updateNowPlayingInfo()
    }

    private func tearDownPlayer(_ target: AVPlayer?) {
        guard let target else { return }
        if target === player {
            if let token = timeObserverToken {
                target.removeTimeObserver(token)
                timeObserverToken = nil
            }
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            if let failedObserver {
                NotificationCenter.default.removeObserver(failedObserver)
                self.failedObserver = nil
            }
            statusObserver?.invalidate()
            statusObserver = nil
        }
        target.pause()
        target.replaceCurrentItem(with: nil)
    }

    private func appendUpNextIfNeeded(for track: Track) async {
        guard let upNext = try? await InnerTubeService.shared.fetchUpNext(videoId: track.id),
              !upNext.isEmpty else {
            return
        }
        let existingIds = Set(queue.map(\.id))
        let fresh = upNext.filter { !existingIds.contains($0.id) }
        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: fresh)
        unshuffledQueue.append(contentsOf: fresh)
    }

    // MARK: - Now Playing Info & Artwork

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistsText,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0
        ]
        if let albumTitle = track.album?.name {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        if let urlStr = track.thumbnailURL,
           let cached = artworkCache.object(forKey: NSString(string: urlStr)) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtworkForNowPlaying(track: Track) {
        guard let urlStr = track.thumbnailURL, let url = URL(string: urlStr) else { return }
        let cacheKey = NSString(string: urlStr)
        if artworkCache.object(forKey: cacheKey) != nil {
            updateNowPlayingInfo()
            return
        }

        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else {
                return
            }
            self.artworkCache.setObject(image, forKey: cacheKey)
            if self.currentTrack?.id == track.id {
                self.updateNowPlayingInfo()
            }
        }
    }
}
