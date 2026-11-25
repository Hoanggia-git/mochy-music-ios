import SwiftUI

/// Offline downloaded tracks screen with storage indicator, active download queue, sorting, and individual/bulk deletion.
struct DownloadsScreen: View {
    @StateObject private var viewModel = LibraryViewModel()
    @ObservedObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @State private var showDeleteAllConfirm = false

    private var sortedRecords: [DownloadedTrackRecord] {
        viewModel.filteredDownloads(from: library.downloadedTracks)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                storageHeaderCard

                if !downloadManager.activeDownloads.isEmpty || !downloadManager.pausedDownloads.isEmpty {
                    downloadQueueSection
                }

                sortAndFilterBar

                if sortedRecords.isEmpty {
                    emptyState
                } else {
                    let tracks = sortedRecords.map(\.track)
                    LazyVStack(spacing: 6) {
                        ForEach(Array(sortedRecords.enumerated()), id: \.element.id) { index, record in
                            HStack(spacing: 8) {
                                TrackRowView(track: record.track) {
                                    player.play(tracks: tracks, startIndex: index)
                                }

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(formatBytes(record.fileSizeBytes))
                                        .font(.mochyMono)
                                        .foregroundColor(.mochySecondary)

                                    Button(role: .destructive) {
                                        downloadManager.deleteDownload(trackId: record.track.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundColor(.mochyRed)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !library.downloadedTracks.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Text("Delete All")
                            .foregroundColor(.mochyRed)
                    }
                }
            }
        }
        .confirmationDialog("Delete all offline downloads?", isPresented: $showDeleteAllConfirm, titleVisibility: .visible) {
            Button("Delete All Downloads", role: .destructive) {
                let ids = library.downloadedTracks.map(\.track.id)
                for id in ids {
                    downloadManager.deleteDownload(trackId: id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Storage Header

    private var storageHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Offline Storage Used")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                    Text(formatBytes(library.totalDownloadSizeBytes))
                        .font(MochyTheme.titleFont(size: 22))
                        .foregroundColor(.mochyOnBackground)
                }
                Spacer()
                Text("\(library.downloadedTracks.count) track\(library.downloadedTracks.count == 1 ? "" : "s")")
                    .font(.mochyCaption)
                    .foregroundColor(settings.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(settings.accentColor.opacity(0.16)))
            }

            let maxBytes = max(1, Double(settings.maxSongCacheSize) * 1024 * 1024)
            let ratio = min(1.0, Double(library.totalDownloadSizeBytes) / maxBytes)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(settings.accentColor)
                        .frame(width: max(6, geo.size.width * ratio))
                }
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                Button {
                    let tracks = sortedRecords.map(\.track)
                    if !tracks.isEmpty {
                        player.play(tracks: tracks, startIndex: 0)
                    }
                } label: {
                    Label("Play Offline", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochyBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(settings.accentColor))
                }
                .buttonStyle(.plain)

                Button {
                    let tracks = sortedRecords.map(\.track).shuffled()
                    if !tracks.isEmpty {
                        player.play(tracks: tracks, startIndex: 0)
                    }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochyOnBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .mochyCard(cornerRadius: 16, fillColor: .mochyEffectiveSurface)
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    // MARK: - Download Queue

    private var downloadQueueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download Queue")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            let activeIds = Array(downloadManager.activeDownloads).sorted()
            ForEach(activeIds, id: \.self) { trackId in
                let progress = downloadManager.downloadProgress[trackId] ?? 0
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downloading \(trackId)")
                            .font(.mochyCaption)
                            .foregroundColor(.mochyOnBackground)
                        ProgressView(value: progress)
                            .tint(settings.accentColor)
                    }
                    Button {
                        downloadManager.pauseDownload(trackId: trackId)
                    } label: {
                        Image(systemName: "pause.circle")
                            .foregroundColor(.mochyPrimary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        downloadManager.cancelDownload(trackId: trackId)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.mochyRed)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .mochyCard(cornerRadius: 12, fillColor: .mochyEffectiveSurface)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    // MARK: - Sort & Filter

    private var sortAndFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibrarySortOption.allCases) { option in
                    let selected = viewModel.sortOption == option
                    Button {
                        viewModel.sortOption = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .foregroundColor(selected ? .mochyBackground : .mochyPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(selected ? settings.accentColor : Color.mochyEffectiveSurface))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundColor(.mochySecondary)
            Text("No Offline Downloads")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
            Text("Download songs from any menu to listen offline.")
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
