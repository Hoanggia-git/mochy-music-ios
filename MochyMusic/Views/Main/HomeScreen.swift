import SwiftUI
import UIKit

/// Main Home feed featuring dynamic greeting, quick-play recently played grid, mood chips, and YouTube Music shelves.
struct HomeScreen: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var showRecognition = false

    private let moodChips: [(title: String, params: String?)] = [
        ("For You", nil),
        ("Energize", "ggMPOg1uX1JOQWZFeDByc2Jm"),
        ("Relax", "ggMPOg1uX1Vxa2Zna3hKMXdV"),
        ("Workout", "ggMPOg1uX1V0WW15NXl2ZUp1"),
        ("Focus", "ggMPOg1uX050eU9tQ201eHlV"),
        ("Commute", "ggMPOg1uX1ZpU21GSm5zRWdZ")
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                headerView
                quickChipsRow

                if !library.recentlyPlayed.isEmpty {
                    quickPlaySection
                }

                if viewModel.isLoading && viewModel.sections.isEmpty {
                    loadingPlaceholders
                } else if let error = viewModel.error, viewModel.sections.isEmpty {
                    errorStateView(message: error)
                } else {
                    ForEach(viewModel.sections) { section in
                        sectionView(section)
                    }

                    if viewModel.continuation != nil {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .tint(settings.accentColor)
                            } else {
                                Color.clear
                                    .frame(height: 20)
                                    .onAppear {
                                        Task { await viewModel.loadMore() }
                                    }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadHomeFeedIfNeeded()
        }
        .sheet(isPresented: $showRecognition) {
            RecognitionSheet()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.greetingText)
                    .font(MochyTheme.titleFont(size: 26))
                    .foregroundColor(.mochyOnBackground)

                Text(settings.username)
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
            }

            Spacer()

            Button {
                showRecognition = true
            } label: {
                Image(systemName: "shazam.logo.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.mochyPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.mochyEffectiveSurface))
            }
            .buttonStyle(.plain)

            Button {
                router.push(.explore)
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(settings.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.mochyEffectiveSurface))
            }
            .buttonStyle(.plain)

            Button {
                router.push(.recap)
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.mochyPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.mochyEffectiveSurface))
            }
            .buttonStyle(.plain)

            Button {
                router.push(.profile)
            } label: {
                Circle()
                    .fill(settings.accentColor.opacity(0.22))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String(settings.username.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(settings.accentColor)
                    )
                    .overlay(
                        Circle()
                            .stroke(settings.accentColor.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    // MARK: - Mood Chips & Explore Link

    private var quickChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    router.push(.explore)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 13))
                        Text("Explore")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.mochyBackground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(settings.accentColor))
                }
                .buttonStyle(.plain)

                ForEach(moodChips, id: \.title) { chip in
                    let isSelected = viewModel.selectedMoodParam == chip.params
                    Button {
                        Task { await viewModel.loadHomeFeed(params: chip.params) }
                    } label: {
                        Text(chip.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isSelected ? .mochyOnBackground : .mochySecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.mochyPrimaryContainer : Color.mochyEffectiveSurface)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(isSelected ? 0.2 : 0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    // MARK: - Quick Play / Recently Played

    private var quickPlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Jump back in")
                    .font(.mochyHeadline)
                    .foregroundColor(.mochyOnBackground)
                Spacer()
                Button("History") {
                    router.push(.history)
                }
                .font(.mochyCaption)
                .foregroundColor(settings.accentColor)
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    let recentTracks = Array(library.recentlyPlayed.prefix(12).map(\.track))
                    ForEach(Array(recentTracks.enumerated()), id: \.element.id) { index, track in
                        Button {
                            player.play(tracks: recentTracks, startIndex: index)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: track.artworkURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    default:
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.mochyEffectiveSurface)
                                            .overlay(
                                                Image(systemName: "music.note")
                                                    .foregroundColor(.mochySecondary)
                                            )
                                    }
                                }
                                .frame(width: 104, height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    if player.currentTrack?.id == track.id && player.isPlaying {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.mochyBackground)
                                            .padding(6)
                                            .background(Circle().fill(settings.accentColor))
                                            .padding(6)
                                    }
                                }

                                Text(track.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.mochyOnBackground)
                                    .lineLimit(1)

                                Text(track.artistsText)
                                    .font(.system(size: 11))
                                    .foregroundColor(.mochySecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 104)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    // MARK: - Home Section Shelf

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle = section.subtitle, !subtitle.isEmpty {
                        Text(subtitle.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.mochySecondary)
                    }
                    Text(section.title)
                        .font(.mochyHeadline)
                        .foregroundColor(.mochyOnBackground)
                        .lineLimit(1)
                }

                Spacer()

                NavigationLink {
                    SectionDetailScreen(
                        title: section.title,
                        browseId: section.browseId,
                        params: section.params,
                        initialItems: section.items
                    )
                } label: {
                    Text("More")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.mochyPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.mochyEffectiveSurface))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            if isTrackOnlySection(section) {
                let tracks = section.items.compactMap { item -> Track? in
                    if case .track(let track) = item { return track }
                    return nil
                }
                let chunks = stride(from: 0, to: tracks.count, by: 4).map {
                    Array(tracks[$0..<min($0 + 4, tracks.count)])
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(chunks.enumerated()), id: \.offset) { chunkIdx, group in
                            VStack(spacing: 4) {
                                ForEach(Array(group.enumerated()), id: \.element.id) { itemIdx, track in
                                    let absoluteIndex = chunkIdx * 4 + itemIdx
                                    TrackRowView(track: track) {
                                        player.play(tracks: tracks, startIndex: absoluteIndex)
                                    }
                                    .frame(width: UIScreen.main.bounds.width * 0.84)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        let sectionTracks = section.items.compactMap { item -> Track? in
                            if case .track(let t) = item { return t }
                            return nil
                        }
                        ForEach(section.items) { item in
                            homeItemCard(item, sectionTracks: sectionTracks)
                        }
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                }
            }
        }
    }

    @ViewBuilder
    private func homeItemCard(_ item: HomeSectionItem, sectionTracks: [Track]) -> some View {
        switch item {
        case .track(let track):
            Button {
                let idx = sectionTracks.firstIndex(where: { $0.id == track.id }) ?? 0
                player.play(tracks: sectionTracks.isEmpty ? [track] : sectionTracks, startIndex: idx)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.mochyEffectiveSurface)
                                .overlay(Image(systemName: "music.note").foregroundColor(.mochySecondary))
                        }
                    }
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochyOnBackground)
                        .lineLimit(1)

                    Text(track.artistsText)
                        .font(.system(size: 12))
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }
                .frame(width: 148)
            }
            .buttonStyle(.plain)

        case .album(let album):
            AlbumCard(album: album) {
                router.push(.album(id: album.browseId ?? album.id))
            }

        case .artist(let artist):
            ArtistCard(artist: artist) {
                router.push(.artist(id: artist.browseId ?? artist.id))
            }

        case .playlist(let playlist):
            PlaylistCard(
                title: playlist.name,
                subtitle: playlist.author,
                thumbnailURL: playlist.thumbnailURL
            ) {
                router.push(.playlist(id: playlist.id, isLocal: false))
            }
        }
    }

    private func isTrackOnlySection(_ section: HomeSection) -> Bool {
        guard !section.items.isEmpty else { return false }
        return section.items.allSatisfy {
            if case .track = $0 { return true }
            return false
        }
    }

    // MARK: - Loading & Error

    private var loadingPlaceholders: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    ShimmerRowPlaceholder()
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShimmerCardPlaceholder()
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 38))
                .foregroundColor(.mochySecondary)
            Text("Couldn't load Home feed")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
            Text(message)
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.mochyBackground)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(settings.accentColor))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
