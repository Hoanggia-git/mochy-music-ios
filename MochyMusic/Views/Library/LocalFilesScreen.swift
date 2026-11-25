import SwiftUI
import UniformTypeIdentifiers

/// Local audio files scanner & player grouped by folder, with document import and Add-to-Playlist actions.
struct LocalFilesScreen: View {
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @State private var showFileImporter = false
    @State private var trackForPlaylist: Track?
    @State private var importError: String?

    private var folderGroups: [(folder: String, tracks: [Track])] {
        viewModel.groupedLocalTracksByFolder(library.localTracks)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                controlsHeader

                if let importError {
                    Text(importError)
                        .font(.mochyCaption)
                        .foregroundColor(.mochyRed)
                        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                }

                if library.isScanningLocal && library.localTracks.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(settings.accentColor)
                        Text("Scanning Documents folder for audio...")
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else if folderGroups.isEmpty {
                    emptyState
                } else {
                    ForEach(folderGroups, id: \.folder) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(group.folder, systemImage: "folder.fill")
                                    .font(.mochyHeadline)
                                    .foregroundColor(.mochyOnBackground)
                                Spacer()
                                Text("\(group.tracks.count)")
                                    .font(.mochyCaption)
                                    .foregroundColor(.mochySecondary)
                            }
                            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

                            LazyVStack(spacing: 4) {
                                ForEach(Array(group.tracks.enumerated()), id: \.element.id) { idx, track in
                                    HStack(spacing: 8) {
                                        TrackRowView(track: track) {
                                            player.play(tracks: group.tracks, startIndex: idx)
                                        }

                                        Button {
                                            trackForPlaylist = track
                                        } label: {
                                            Image(systemName: "text.badge.plus")
                                                .font(.system(size: 16))
                                                .foregroundColor(settings.accentColor)
                                                .padding(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Local Files")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(settings.accentColor)
                }

                Button {
                    Task { await viewModel.scanLocalFiles() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.mochyOnBackground)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        .sheet(item: $trackForPlaylist) { track in
            AddToPlaylistSheet(track: track)
        }
        .task {
            if library.localTracks.isEmpty {
                await viewModel.scanLocalFiles()
            }
        }
    }

    private var controlsHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.mochySecondary)
                TextField("Filter local audio...", text: $viewModel.searchText)
                    .font(.mochyBody)
                    .foregroundColor(.mochyOnBackground)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.mochyEffectiveSurface))

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.scanLocalFiles() }
                } label: {
                    Label(library.isScanningLocal ? "Scanning..." : "Scan Storage", systemImage: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochyBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(settings.accentColor))
                }
                .buttonStyle(.plain)

                Button {
                    showFileImporter = true
                } label: {
                    Label("Import Files", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochyOnBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.mochyEffectiveSurface))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundColor(.mochySecondary)
            Text("No Local Audio Found")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
            Text("Import MP3, M4A, FLAC, or WAV files from Files app or place them in Mochy Music's Documents folder.")
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let localDir = docs.appendingPathComponent("LocalMusic", isDirectory: true)
            try? fm.createDirectory(at: localDir, withIntermediateDirectories: true)

            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                let dest = localDir.appendingPathComponent(url.lastPathComponent)
                try? fm.removeItem(at: dest)
                try? fm.copyItem(at: url, to: dest)
            }
            Task { await viewModel.scanLocalFiles() }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
