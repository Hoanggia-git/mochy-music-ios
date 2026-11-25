import SwiftUI
import UIKit
import CoreImage

/// Full Album detail screen with dynamic artwork-tinted gradient, artist navigation, tracklist, and share sheet.
struct AlbumScreen: View {
    let browseId: String

    @StateObject private var viewModel = AlbumViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var tintColor: Color = .mochySurface0
    @State private var isSavedInLibrary: Bool = false
    @State private var isDownloadingAll: Bool = false

    private let savedAlbumsKey = "mochy_saved_albums"

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                if viewModel.isLoading && viewModel.album == nil {
                    loadingState
                } else if let error = viewModel.error, viewModel.album == nil {
                    errorState(error)
                } else if let album = viewModel.album {
                    albumHeader(album)
                    actionButtonsRow(album)
                    tracksListSection(album)
                    albumFooter(album)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(
            LinearGradient(
                colors: [tintColor.opacity(0.5), Color.mochyEffectiveBackground, Color.mochyEffectiveBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(viewModel.album?.name ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let album = viewModel.album, let shareURL = albumShareURL(album) {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.mochyOnBackground)
                    }
                }
            }
        }
        .task {
            await viewModel.loadAlbum(browseId: browseId)
            if let album = viewModel.album {
                checkIfSaved(album)
                await extractTintColor(from: album.artworkURL)
            }
        }
    }

    // MARK: - Header

    private func albumHeader(_ album: Album) -> some View {
        VStack(spacing: 14) {
            AsyncImage(url: album.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.mochyEffectiveSurface)
                        .overlay(
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 56))
                                .foregroundColor(.mochySecondary)
                        )
                }
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.55), radius: 22, x: 0, y: 12)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(album.name)
                        .font(MochyTheme.titleFont(size: 23))
                        .foregroundColor(.mochyOnBackground)
                        .multilineTextAlignment(.center)

                    if album.explicit {
                        Text("E")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mochyBackground)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.mochySecondary))
                    }
                }

                if !album.artists.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(album.artists.enumerated()), id: \.offset) { idx, artist in
                            Button {
                                let targetId = artist.browseId ?? artist.id
                                if !targetId.hasPrefix("LA_") {
                                    router.push(.artist(id: targetId))
                                }
                            } label: {
                                Text(artist.name + (idx < album.artists.count - 1 ? "," : ""))
                                    .font(.mochySubheadline)
                                    .foregroundColor(settings.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Text("Album")
                    if let year = album.year {
                        Text("•")
                        Text(String(year))
                    }
                }
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Actions

    private func actionButtonsRow(_ album: Album) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    guard !album.tracks.isEmpty else { return }
                    player.play(tracks: album.tracks, startIndex: 0)
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.mochyBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(settings.accentColor))
                }
                .buttonStyle(.plain)

                Button {
                    guard !album.tracks.isEmpty else { return }
                    let shuffled = album.tracks.shuffled()
                    player.play(tracks: shuffled, startIndex: 0)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.mochyOnBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(Color.mochyEffectiveSurface))
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Button {
                    toggleLibrarySave(album)
                } label: {
                    Label(isSavedInLibrary ? "In Library" : "Add to Library",
                          systemImage: isSavedInLibrary ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSavedInLibrary ? settings.accentColor : .mochyPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.mochyEffectiveSurface))
                }
                .buttonStyle(.plain)

                Button {
                    isDownloadingAll = true
                    for track in album.tracks {
                        DownloadManager.shared.download(track: track)
                    }
                } label: {
                    Label(isDownloadingAll ? "Downloading..." : "Download Album",
                          systemImage: "arrow.down.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.mochyPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.mochyEffectiveSurface))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    // MARK: - Tracks

    private func tracksListSection(_ album: Album) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                TrackRowView(track: track, index: index + 1) {
                    player.play(tracks: album.tracks, startIndex: index)
                }
            }
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    // MARK: - Footer

    private func albumFooter(_ album: Album) -> some View {
        let count = album.tracks.count
        let totalSecs = album.duration > 0 ? album.duration : album.tracks.compactMap(\.durationSeconds).reduce(0, +)
        let mins = totalSecs / 60

        return VStack(alignment: .leading, spacing: 6) {
            if let description = album.description, !description.isEmpty {
                Text(description)
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
                    .padding(.bottom, 4)
            }
            Text("\(count) song\(count == 1 ? "" : "s") • \(mins) min\(mins == 1 ? "" : "s")")
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
            if let year = album.year {
                Text("Released \(year)")
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func albumShareURL(_ album: Album) -> URL? {
        if let playlistId = album.playlistId, !playlistId.isEmpty {
            return URL(string: "https://music.youtube.com/playlist?list=\(playlistId)")
        }
        return URL(string: "https://music.youtube.com/browse/\(album.browseId ?? album.id)")
    }

    private func checkIfSaved(_ album: Album) {
        let saved = Set(UserDefaults.standard.stringArray(forKey: savedAlbumsKey) ?? [])
        isSavedInLibrary = saved.contains(album.id) || saved.contains(browseId)
    }

    private func toggleLibrarySave(_ album: Album) {
        var saved = Set(UserDefaults.standard.stringArray(forKey: savedAlbumsKey) ?? [])
        if isSavedInLibrary {
            saved.remove(album.id)
            saved.remove(browseId)
            isSavedInLibrary = false
        } else {
            saved.insert(album.id)
            saved.insert(browseId)
            isSavedInLibrary = true
            library.createPlaylist(
                name: album.name,
                description: "Album by \(album.artistsText)",
                tracks: album.tracks,
                thumbnailURL: album.thumbnailURL
            )
        }
        UserDefaults.standard.set(Array(saved), forKey: savedAlbumsKey)
    }

    private func extractTintColor(from url: URL?) async {
        guard let url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data), let average = uiImage.mochyAverageColor else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.45)) {
                    tintColor = Color(uiColor: average)
                }
            }
        } catch {
            // Keep default tint
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.mochyEffectiveSurface)
                .frame(width: 280, height: 280)
                .mochyShimmer()
            ForEach(0..<6, id: \.self) { _ in
                ShimmerRowPlaceholder()
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 38))
                .foregroundColor(.mochySecondary)
            Text(message)
                .font(.mochyBody)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                Task { await viewModel.loadAlbum(browseId: browseId) }
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private extension UIImage {
    var mochyAverageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(
            x: inputImage.extent.origin.x,
            y: inputImage.extent.origin.y,
            z: inputImage.extent.size.width,
            w: inputImage.extent.size.height
        )
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: inputImage,
            kCIInputExtentKey: extentVector
        ]),
        let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return UIColor(
            red: CGFloat(bitmap[0]) / 255.0,
            green: CGFloat(bitmap[1]) / 255.0,
            blue: CGFloat(bitmap[2]) / 255.0,
            alpha: 1.0
        )
    }
}
