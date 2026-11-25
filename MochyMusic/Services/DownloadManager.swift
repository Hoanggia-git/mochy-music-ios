import Foundation

/// Background URLSession download manager with concurrency limit, pause/resume/cancel, and local persistence.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var downloadProgress: [String: Double] = [:]
    @Published var activeDownloads: Set<String> = []
    @Published var pausedDownloads: Set<String> = []
    @Published var downloadErrors: [String: String] = [:]

    private let maxConcurrentDownloads = 3
    private var pendingQueue: [Track] = []
    private var tracksByTaskId: [Int: Track] = [:]
    private var tasksByTrackId: [String: URLSessionDownloadTask] = [:]
    private var resumeDataByTrackId: [String: Data] = [:]

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.mochyy.mochymusic.downloads")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        _ = urlSession
    }

    // MARK: - Public API

    func isDownloading(_ trackId: String) -> Bool {
        activeDownloads.contains(trackId) || pendingQueue.contains { $0.id == trackId }
    }

    func download(track: Track) {
        guard !track.isLocal else { return }
        guard !LibraryStore.shared.isDownloaded(track.id) else { return }
        guard !activeDownloads.contains(track.id),
              !pendingQueue.contains(where: { $0.id == track.id }) else {
            return
        }

        downloadErrors.removeValue(forKey: track.id)
        pausedDownloads.remove(track.id)

        if activeDownloads.count >= maxConcurrentDownloads {
            pendingQueue.append(track)
            downloadProgress[track.id] = 0
            return
        }

        startDownloadTask(for: track)
    }

    func pauseDownload(trackId: String) {
        guard let task = tasksByTrackId[trackId] else { return }
        task.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data {
                    self.resumeDataByTrackId[trackId] = data
                }
                self.activeDownloads.remove(trackId)
                self.pausedDownloads.insert(trackId)
                self.tasksByTrackId.removeValue(forKey: trackId)
                self.startNextPendingIfNeeded()
            }
        })
    }

    func resumeDownload(track: Track) {
        guard pausedDownloads.contains(track.id) else {
            download(track: track)
            return
        }

        pausedDownloads.remove(track.id)
        if let resumeData = resumeDataByTrackId.removeValue(forKey: track.id) {
            if activeDownloads.count >= maxConcurrentDownloads {
                pendingQueue.append(track)
                return
            }
            let task = urlSession.downloadTask(withResumeData: resumeData)
            registerTask(task, for: track)
            task.resume()
        } else {
            download(track: track)
        }
    }

    func cancelDownload(trackId: String) {
        pendingQueue.removeAll { $0.id == trackId }
        resumeDataByTrackId.removeValue(forKey: trackId)
        pausedDownloads.remove(trackId)

        if let task = tasksByTrackId.removeValue(forKey: trackId) {
            tracksByTaskId.removeValue(forKey: task.taskIdentifier)
            task.cancel()
        }

        activeDownloads.remove(trackId)
        downloadProgress.removeValue(forKey: trackId)
        downloadErrors.removeValue(forKey: trackId)
        startNextPendingIfNeeded()
    }

    func deleteDownload(trackId: String) {
        cancelDownload(trackId: trackId)
        LibraryStore.shared.removeDownload(trackId: trackId)
    }

    // MARK: - Internal Task Orchestration

    private func startDownloadTask(for track: Track) {
        activeDownloads.insert(track.id)
        downloadProgress[track.id] = 0

        let quality = mapDownloadQuality(AppSettings.shared.downloadQuality)

        Task {
            do {
                let resolved = try await InnerTubeService.shared.resolveStream(videoId: track.id, quality: quality)
                var request = URLRequest(url: resolved.url)
                if let ua = resolved.userAgent {
                    request.setValue(ua, forHTTPHeaderField: "User-Agent")
                }
                let task = self.urlSession.downloadTask(with: request)
                self.registerTask(task, for: track)
                task.resume()
            } catch {
                self.activeDownloads.remove(track.id)
                self.downloadProgress.removeValue(forKey: track.id)
                self.downloadErrors[track.id] = error.localizedDescription
                self.startNextPendingIfNeeded()
            }
        }
    }

    private func registerTask(_ task: URLSessionDownloadTask, for track: Track) {
        activeDownloads.insert(track.id)
        tracksByTaskId[task.taskIdentifier] = track
        tasksByTrackId[track.id] = task
    }

    private func startNextPendingIfNeeded() {
        while activeDownloads.count < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let nextTrack = pendingQueue.removeFirst()
            startDownloadTask(for: nextTrack)
        }
    }

    private func mapDownloadQuality(_ quality: DownloadQuality) -> StreamQuality {
        switch quality {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        let taskId = downloadTask.taskIdentifier

        Task { @MainActor [weak self] in
            guard let self, let track = self.tracksByTaskId[taskId] else { return }
            self.downloadProgress[track.id] = fraction
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier
        let fileManager = FileManager.default
        let downloadsDir = PersistenceManager.shared.downloadsDirectoryURL

        // Move synchronously before URLSession deletes the temporary file
        let tempCopy = downloadsDir.appendingPathComponent("tmp_\(UUID().uuidString).m4a")
        try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let moved = (try? fileManager.moveItem(at: location, to: tempCopy)) != nil

        Task { @MainActor [weak self] in
            guard let self else {
                try? fileManager.removeItem(at: tempCopy)
                return
            }
            guard let track = self.tracksByTaskId.removeValue(forKey: taskId) else {
                try? fileManager.removeItem(at: tempCopy)
                return
            }
            self.tasksByTrackId.removeValue(forKey: track.id)
            self.activeDownloads.remove(track.id)

            guard moved else {
                self.downloadErrors[track.id] = "Failed to save downloaded audio file."
                self.downloadProgress.removeValue(forKey: track.id)
                self.startNextPendingIfNeeded()
                return
            }

            let fileName = "\(track.id).m4a"
            let finalURL = downloadsDir.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: finalURL)

            do {
                try fileManager.moveItem(at: tempCopy, to: finalURL)
                let attrs = try? fileManager.attributesOfItem(atPath: finalURL.path)
                let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                LibraryStore.shared.markDownloaded(track: track, fileName: fileName, fileSizeBytes: fileSize)
                self.downloadProgress[track.id] = 1.0
                self.downloadProgress.removeValue(forKey: track.id)
            } catch {
                try? fileManager.removeItem(at: tempCopy)
                self.downloadErrors[track.id] = error.localizedDescription
                self.downloadProgress.removeValue(forKey: track.id)
            }

            self.startNextPendingIfNeeded()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }

        let taskId = task.taskIdentifier
        Task { @MainActor [weak self] in
            guard let self, let track = self.tracksByTaskId.removeValue(forKey: taskId) else { return }
            self.tasksByTrackId.removeValue(forKey: track.id)
            self.activeDownloads.remove(track.id)
            self.downloadProgress.removeValue(forKey: track.id)
            self.downloadErrors[track.id] = error.localizedDescription
            self.startNextPendingIfNeeded()
        }
    }
}
