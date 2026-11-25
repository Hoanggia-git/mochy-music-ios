import SwiftUI
import UniformTypeIdentifiers

struct StorageAndBackupScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var backupService = BackupService.shared
    @ObservedObject private var router = NavigationRouter.shared

    @State private var cacheBytes: Int64 = 0
    @State private var showRestorePicker = false
    @State private var statusBanner: String?
    @State private var isErrorBanner = false
    @State private var exportedFileURL: URL?

    init() {}

    private var downloadsBytes: Int64 {
        library.totalDownloadSizeBytes
    }

    private var totalManagedBytes: Int64 {
        max(1, downloadsBytes + cacheBytes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let statusBanner {
                    HStack(spacing: 10) {
                        Image(systemName: isErrorBanner ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(isErrorBanner ? .mochyRed : .mochyGreen)
                        Text(statusBanner)
                            .font(.mochyCaption)
                            .foregroundColor(.mochyOnSurface)
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusMedium, style: .continuous)
                            .fill((isErrorBanner ? Color.mochyRed : Color.mochyGreen).opacity(0.14))
                    )
                }

                storageBreakdownCard
                cacheAndDownloadsCard
                backupAndRestoreCard
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Bộ nhớ & Sao lưu")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshCacheSize()
        }
        .fileImporter(
            isPresented: $showRestorePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleRestoreResult(result)
        }
    }

    // MARK: - Storage Breakdown Bar

    private var storageBreakdownCard: some View {
        let downloadRatio = Double(downloadsBytes) / Double(totalManagedBytes)
        let cacheRatio = Double(cacheBytes) / Double(totalManagedBytes)

        return MochySettingsCard(title: "Phân bổ dung lượng") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ByteCountFormatter.string(fromByteCount: downloadsBytes + cacheBytes, countStyle: .file))
                        .font(.mochyTitle)
                        .foregroundColor(.mochyOnSurface)
                    Spacer()
                    Text("\(library.downloadedTracks.count) bài đã tải")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                }

                GeometryReader { proxy in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(settings.accentColor)
                            .frame(width: max(8, proxy.size.width * CGFloat(downloadRatio)))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.mochyBlue)
                            .frame(width: max(8, proxy.size.width * CGFloat(cacheRatio)))
                    }
                }
                .frame(height: 14)
                .clipShape(Capsule())

                HStack(spacing: 18) {
                    legendItem(
                        color: settings.accentColor,
                        title: "Nhạc ngoại tuyến",
                        size: ByteCountFormatter.string(fromByteCount: downloadsBytes, countStyle: .file)
                    )
                    legendItem(
                        color: .mochyBlue,
                        title: "Bộ đệm (Ảnh & Lời)",
                        size: ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
                    )
                }
            }
            .padding(16)
        }
    }

    private func legendItem(color: Color, title: String, size: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
                Text(size)
                    .font(.mochyCaption.weight(.semibold))
                    .foregroundColor(.mochyOnSurface)
            }
        }
    }

    // MARK: - Cache & Downloads

    private var cacheAndDownloadsCard: some View {
        MochySettingsCard(title: "Quản lý bộ nhớ") {
            Button {
                clearCaches()
            } label: {
                MochySettingsNavRow(
                    title: "Xóa bộ đệm Lời & Hình ảnh",
                    subtitle: "Giải phóng cache tạm mà không xóa nhạc đã tải",
                    icon: "trash.slash.fill",
                    tint: .mochyBlue,
                    trailingValue: ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            Button {
                router.push(.downloads)
            } label: {
                MochySettingsNavRow(
                    title: "Quản lý nhạc đã tải",
                    subtitle: "Xem danh sách hoặc xóa từng bài hát ngoại tuyến",
                    icon: "arrow.down.circle.fill",
                    tint: settings.accentColor,
                    trailingValue: "\(library.downloadedTracks.count)"
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Tiết kiệm dữ liệu (Data Saver)",
                subtitle: "Giảm chất lượng ảnh và stream khi dùng mạng di động",
                icon: "antenna.radiowaves.left.and.right",
                tint: .mochyYellow,
                isOn: $settings.dataSaver
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Chế độ Ngoại tuyến (Offline Mode)",
                subtitle: "Chỉ phát nhạc đã tải xuống và nhạc cục bộ",
                icon: "airplane.circle.fill",
                tint: .mochyRed,
                isOn: $settings.offlineMode
            )
        }
    }

    // MARK: - Backup & Restore

    private var backupAndRestoreCard: some View {
        MochySettingsCard(title: "Sao lưu & Khôi phục JSON") {
            Button {
                exportBackup()
            } label: {
                MochySettingsNavRow(
                    title: "Xuất bản sao lưu (.json)",
                    subtitle: lastBackupSubtitle,
                    icon: "square.and.arrow.up.fill",
                    tint: .mochyGreen,
                    trailingValue: backupService.isProcessing ? "Đang xuất..." : nil
                )
            }
            .buttonStyle(.plain)

            if let exportedFileURL {
                MochySettingsDivider()
                ShareLink(item: exportedFileURL) {
                    MochySettingsNavRow(
                        title: "Chia sẻ lại tệp sao lưu vừa tạo",
                        subtitle: exportedFileURL.lastPathComponent,
                        icon: "paperplane.fill",
                        tint: .mochySapphire
                    )
                }
                .buttonStyle(.plain)
            }

            MochySettingsDivider()

            Button {
                showRestorePicker = true
            } label: {
                MochySettingsNavRow(
                    title: "Khôi phục từ tệp JSON",
                    subtitle: "Nhập lại Yêu thích, Playlist, Lịch sử & Cài đặt",
                    icon: "arrow.counterclockwise.circle.fill",
                    tint: .mochyPeach
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Tự động sao lưu định kỳ",
                subtitle: "Lưu bản sao tự động mỗi \(settings.cloudBackupEveryMinutes) phút",
                icon: "clock.arrow.2.circlepath",
                tint: .mochyLavender,
                isOn: Binding(
                    get: { settings.cloudBackupAuto },
                    set: { newValue in
                        settings.cloudBackupAuto = newValue
                        backupService.startAutoBackupMonitorIfEnabled()
                    }
                )
            )
        }
    }

    private var lastBackupSubtitle: String {
        if let date = backupService.lastBackupDate {
            let formatted = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
            return "Lần cuối: \(formatted)"
        }
        return "Bao gồm Yêu thích, Playlist, Thống kê & Cài đặt"
    }

    // MARK: - Actions

    private func refreshCacheSize() {
        let urlCacheBytes = Int64(URLCache.shared.currentDiskUsage)
        var dirBytes: Int64 = 0
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let enumerator = FileManager.default.enumerator(at: cachesURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    dirBytes += Int64(size)
                }
            }
        }
        cacheBytes = max(urlCacheBytes, dirBytes)
    }

    private func clearCaches() {
        LyricsManager.shared.clearCache()
        CanvasService.shared.clearCache()
        URLCache.shared.removeAllCachedResponses()
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let items = try? FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil) {
            for item in items {
                try? FileManager.default.removeItem(at: item)
            }
        }
        refreshCacheSize()
        isErrorBanner = false
        statusBanner = "Đã dọn sạch bộ đệm lời bài hát và hình ảnh."
    }

    private func exportBackup() {
        do {
            let fileURL = try backupService.exportBackupFile()
            exportedFileURL = fileURL
            backupService.presentShareSheet(for: fileURL)
            isErrorBanner = false
            statusBanner = "Đã xuất sao lưu thành công: \(fileURL.lastPathComponent)"
        } catch {
            isErrorBanner = true
            statusBanner = "Xuất sao lưu thất bại: \(error.localizedDescription)"
        }
    }

    private func handleRestoreResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let backup = try backupService.importBackup(from: url)
                isErrorBanner = false
                statusBanner = "Đã khôi phục \(backup.playlists.count) playlist & \(backup.favorites.count) bài yêu thích."
            } catch {
                isErrorBanner = true
                statusBanner = "Không thể khôi phục tệp: \(error.localizedDescription)"
            }
        case .failure(let error):
            isErrorBanner = true
            statusBanner = error.localizedDescription
        }
    }
}
