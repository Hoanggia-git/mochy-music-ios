import Foundation
import UIKit

/// Export, restore, share-sheet presentation, and scheduled auto-backup for Mochy Music user data.
@MainActor
final class BackupService: ObservableObject {
    static let shared = BackupService()

    @Published var lastBackupDate: Date? {
        didSet {
            if let lastBackupDate {
                UserDefaults.standard.set(lastBackupDate.timeIntervalSince1970, forKey: lastBackupKey)
            }
        }
    }
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    private let lastBackupKey = "mochy_last_backup_timestamp"
    private let persistence = PersistenceManager.shared
    private var autoBackupTask: Task<Void, Never>?

    private static let fileTimestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private init() {
        let ts = UserDefaults.standard.double(forKey: lastBackupKey)
        if ts > 0 {
            self.lastBackupDate = Date(timeIntervalSince1970: ts)
        }
        startAutoBackupMonitorIfEnabled()
    }

    // MARK: - Export & Restore

    func exportBackupFile() throws -> URL {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let data = try persistence.exportBackupData()
        let filename = "MochyMusic-Backup-\(Self.fileTimestampFormatter.string(from: Date())).json"
        let exportDir = FileManager.default.temporaryDirectory
        let fileURL = exportDir.appendingPathComponent(filename)

        try data.write(to: fileURL, options: [.atomic])
        lastBackupDate = Date()
        return fileURL
    }

    @discardableResult
    func importBackup(from url: URL) throws -> MochyFullBackup {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let restored = try persistence.restoreBackup(from: data)

        // Restore UserDefaults preferences included in settingsBackup
        applyRestoredSettings(restored.settingsBackup)
        LibraryStore.shared.reloadFromPersistence()
        return restored
    }

    func presentShareSheet(for fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(activityVC, animated: true)
    }

    // MARK: - Auto Backup

    func startAutoBackupMonitorIfEnabled() {
        autoBackupTask?.cancel()
        guard AppSettings.shared.cloudBackupAuto else { return }

        autoBackupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let intervalMinutes = max(15, AppSettings.shared.cloudBackupEveryMinutes)
                let intervalSeconds = TimeInterval(intervalMinutes * 60)

                let shouldBackup: Bool
                if let last = self.lastBackupDate {
                    shouldBackup = Date().timeIntervalSince(last) >= intervalSeconds
                } else {
                    shouldBackup = true
                }

                if shouldBackup {
                    self.performSilentAutoBackup()
                }
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
            }
        }
    }

    private func performSilentAutoBackup() {
        guard let data = try? persistence.exportBackupData() else { return }
        let autoURL = persistence.dataDirectoryURL.appendingPathComponent("auto_backup_latest.json")
        try? data.write(to: autoURL, options: [.atomic])
        lastBackupDate = Date()
    }

    private func applyRestoredSettings(_ settingsDict: [String: String]) {
        let defaults = UserDefaults.standard
        let knownKeys: Set<String> = [
            "themeMode", "accentColorPreset", "dynamicTheme", "pureBlack", "pureBlackMiniPlayer",
            "disableBlur", "blurStrengthPx", "animationSpeed", "cornerRadius", "fontSizePreset",
            "homeStyle", "playlistStyle", "playerStyle", "sliderStyle", "audioQuality",
            "audioNormalization", "crossfadeEnabled", "crossfadeDuration", "downloadQuality",
            "lyricsProviderOrder", "contentLanguage", "contentCountry", "username"
        ]
        for (key, value) in settingsDict where knownKeys.contains(key) {
            if value == "true" {
                defaults.set(true, forKey: key)
            } else if value == "false" {
                defaults.set(false, forKey: key)
            } else if let intVal = Int(value) {
                defaults.set(intVal, forKey: key)
            } else if let doubleVal = Double(value) {
                defaults.set(doubleVal, forKey: key)
            } else {
                defaults.set(value, forKey: key)
            }
        }
    }
}
