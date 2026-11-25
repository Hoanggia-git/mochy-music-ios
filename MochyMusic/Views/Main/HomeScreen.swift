import SwiftUI
import UIKit
import CoreImage

/// Main Home feed featuring ambient HomeTopGlow, Speed Dial Hero Carousel, quick-play grid, mood chips, and 3-row HomeTrackGrid shelves.
struct HomeScreen: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var showRecognition = false
    @State private var showSpeedDialSheet = false

    private let moodChips: [(title: String, params: String?)] = [
        ("For You", nil),
        ("Energize", "ggMPOg1uX1JOQWZFeDByc2Jm"),
        ("Relax", "ggMPOg1uX1Vxa2Zna3hKMXdV"),
        ("Workout", "ggMPOg1uX1V0WW15NXl2ZUp1"),
        ("Focus", "ggMPOg1uX050eU9tQ201eHlV"),
        ("Commute", "ggMPOg1uX1ZpU21GSm5zRWdZ")
    ]

    private var speedDialTracks: [Track] {
        var seen = Set<String>()
        var merged: [Track] = []
        for track in library.recentlyPlayed.map(\.track) + library.favorites {
            if seen.insert(track.id).inserted {
                merged.append(track)
            }
            if merged.count >= 16 { break }
        }
        if merged.count < 16 {
            for section in viewModel.sections {
                for item in section.items {
                    if case .track(let track) = item, seen.insert(track.id).inserted {
                        merged.append(track)
                        if merged.count >= 16 { break }
                    }
                }
                if merged.count >= 16 { break }
            }
        }
        return merged
    }

    private var glowCoverURLs: [URL] {
        let recentURLs = library.recentlyPlayed.prefix(2).compactMap(\.track.artworkURL)
        if !recentURLs.isEmpty { return recentURLs }
        var fallback: [URL] = []
        for section in viewModel.sections {
            for item in section.items {
                switch item {
                case .track(let t): if let url = t.artworkURL { fallback.append(url) }
                case .album(let a): if let url = a.artworkURL { fallback.append(url) }
                case .playlist(let p): if let url = p.artworkURL { fallback.append(url) }
                case .artist(let a): if let url = a.artworkURL { fallback.append(url) }
                }
                if fallback.count >= 2 { return fallback }
            }
        }
        return fallback
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.mochyEffectiveBackground.ignoresSafeArea()

            HomeTopGlow(coverURLs: glowCoverURLs, accentColor: settings.accentColor)
                .ignoresSafeArea(edges: .top)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    headerView
                    quickChipsRow

                    heroCarouselSection

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
        }
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
        .sheet(isPresented: $showSpeedDialSheet) {
            SpeedDialSheet(tracks: speedDialTracks)
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(settings)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.greetingText)
                    .font(MochyTheme.titleFont(size: 26))
                    .foregroundColor(.mochyOnBackground)

                Text(settings.ytAccountName.isEmpty ? settings.username : settings.ytAccountName)
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
                    .background(Circle().fill(Color.mochyEffectiveSurface.opacity(0.85)))
            }
            .buttonStyle(.plain)

            Button {
                router.push(.explore)
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(settings.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.mochyEffectiveSurface.opacity(0.85)))
            }
            .buttonStyle(.plain)

            Button {
                router.push(.recap)
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.mochyPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.mochyEffectiveSurface.opacity(0.85)))
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
                                    .fill(isSelected ? Color.mochyPrimaryContainer : Color.mochyEffectiveSurface.opacity(0.9))
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

    // MARK: - Speed Dial Hero Carousel

    private var heroCarouselSection: some View {
        HeroCarouselView(
            speedDialTracks: speedDialTracks,
            featuredItems: featuredHeroItems,
            accentColor: settings.accentColor,
            onSummonSpeedDial: {
                showSpeedDialSheet = true
            },
            onPlayTrack: { track in
                player.play(track: track)
            },
            onOpenAlbum: { album in
                router.push(.album(id: album.browseId ?? album.id))
            },
            onOpenPlaylist: { playlist in
                router.push(.playlist(id: playlist.id, isLocal: false))
            }
        )
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    private var featuredHeroItems: [HomeSectionItem] {
        var picks: [HomeSectionItem] = []
        var seen = Set<String>()
        for section in viewModel.sections {
            for item in section.items {
                if seen.insert(item.id).inserted {
                    switch item {
                    case .album, .playlist, .track:
                        picks.append(item)
                    case .artist:
                        break
                    }
                }
                if picks.count >= 5 { return picks }
            }
        }
        return picks
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

    // MARK: - Home Section Shelf (3-row HomeTrackGrid + Cover Cards)

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
                HomeTrackGrid(tracks: tracks) { index in
                    player.play(tracks: tracks, startIndex: index)
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

// MARK: - HomeTopGlow

/// Subtle ambient dual-corner radial wash behind the Home header tinted from top album covers.
struct HomeTopGlow: View {
    let coverURLs: [URL]
    let accentColor: Color

    @State private var leftColor: Color = .clear
    @State private var rightColor: Color = .clear

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [leftColor.opacity(0.45), .clear],
                center: UnitPoint(x: 0.12, y: 0.0),
                startRadius: 10,
                endRadius: 270
            )
            RadialGradient(
                colors: [rightColor.opacity(0.4), .clear],
                center: UnitPoint(x: 0.88, y: 0.0),
                startRadius: 10,
                endRadius: 270
            )
        }
        .frame(height: 290)
        .allowsHitTesting(false)
        .task(id: coverURLs) {
            if coverURLs.isEmpty {
                withAnimation(.easeInOut(duration: 0.6)) {
                    leftColor = accentColor.opacity(0.55)
                    rightColor = Color.mochyMauve.opacity(0.45)
                }
                return
            }
            async let first = sampleGlowColor(url: coverURLs.first)
            async let second = sampleGlowColor(url: coverURLs.count > 1 ? coverURLs[1] : coverURLs.first)
            let (c1, c2) = await (first, second)
            withAnimation(.easeInOut(duration: 0.7)) {
                leftColor = c1 ?? accentColor.opacity(0.6)
                rightColor = c2 ?? c1 ?? Color.mochyMauve.opacity(0.5)
            }
        }
    }

    private func sampleGlowColor(url: URL?) async -> Color? {
        guard let url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data),
                  let ciImage = CIImage(image: uiImage) else { return nil }
            let extent = CIVector(
                x: ciImage.extent.origin.x,
                y: ciImage.extent.origin.y,
                z: ciImage.extent.size.width,
                w: ciImage.extent.size.height
            )
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: extent
            ]),
            let out = filter.outputImage else { return nil }
            var bitmap = [UInt8](repeating: 0, count: 4)
            CIContext(options: [.workingColorSpace: kCFNull as Any]).render(
                out,
                toBitmap: &bitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: nil
            )
            return Color(
                .sRGB,
                red: Double(bitmap[0]) / 255.0,
                green: Double(bitmap[1]) / 255.0,
                blue: Double(bitmap[2]) / 255.0,
                opacity: 1.0
            )
        } catch {
            return nil
        }
    }
}

// MARK: - HomeTrackGrid (3-Row Horizontal Shelf)

/// Mochy Music's 3-row horizontal track shelf grid for Quick Picks and Song Shelves.
struct HomeTrackGrid: View {
    let tracks: [Track]
    let onTapTrack: (Int) -> Void

    private var columns: [[(offset: Int, element: Track)]] {
        let enumerated = Array(tracks.enumerated())
        return stride(from: 0, to: enumerated.count, by: 3).map {
            Array(enumerated[$0..<min($0 + 3, enumerated.count)])
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, group in
                    VStack(spacing: 4) {
                        ForEach(group, id: \.element.id) { pair in
                            TrackRowView(track: pair.element) {
                                onTapTrack(pair.offset)
                            }
                            .frame(width: UIScreen.main.bounds.width * 0.84)
                        }
                    }
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }
}

// MARK: - HeroCarouselView & Speed Dial Hero Card

/// Horizontal paging Hero Carousel featuring Mochy's signature tilted Speed Dial card and featured highlights.
struct HeroCarouselView: View {
    let speedDialTracks: [Track]
    let featuredItems: [HomeSectionItem]
    let accentColor: Color
    let onSummonSpeedDial: () -> Void
    let onPlayTrack: (Track) -> Void
    let onOpenAlbum: (Album) -> Void
    let onOpenPlaylist: (YouTubePlaylist) -> Void

    @State private var selectedPage: Int = 0

    var body: some View {
        TabView(selection: $selectedPage) {
            speedDialHeroCard
                .tag(0)

            ForEach(Array(featuredItems.enumerated()), id: \.element.id) { index, item in
                featuredHeroCard(item)
                    .tag(index + 1)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var speedDialHeroCard: some View {
        Button(action: onSummonSpeedDial) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.32),
                        Color.mochyMauve.opacity(0.26),
                        Color.mochySurfaceVariant
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Tilted -17° 4x4 grid of covers (SpeedDialHero.kt)
                let tiles = Array(speedDialTracks.prefix(16))
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(42), spacing: 6), count: 4),
                    spacing: 6
                ) {
                    ForEach(0..<16, id: \.self) { idx in
                        if idx < tiles.count, let url = tiles[idx].artworkURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Color.white.opacity(0.18)
                                }
                            }
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 42, height: 42)
                        }
                    }
                }
                .rotationEffect(.degrees(-17))
                .offset(x: 86, y: -22)
                .opacity(0.92)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.05),
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Speed Dial")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.mochyBackground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accentColor))

                    HStack(alignment: .bottom) {
                        Text("Summon speed dial")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        Spacer()

                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func featuredHeroCard(_ item: HomeSectionItem) -> some View {
        let info: (badge: String, title: String, subtitle: String, artwork: URL?, action: () -> Void) = {
            switch item {
            case .track(let track):
                return ("Featured Song", track.title, track.artistsText, track.artworkURL, { onPlayTrack(track) })
            case .album(let album):
                return ("Featured Album", album.name, album.artistsText, album.artworkURL, { onOpenAlbum(album) })
            case .playlist(let playlist):
                return ("Featured Playlist", playlist.name, playlist.author ?? "YouTube Music", playlist.artworkURL, { onOpenPlaylist(playlist) })
            case .artist(let artist):
                return ("Artist", artist.name, artist.subscriberCount ?? "", artist.artworkURL, {})
            }
        }()

        Button(action: info.action) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: info.artwork) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.mochySurfaceVariant
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.15), Color.black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(info.badge.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.55)))

                        Text(info.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        if !info.subtitle.isEmpty {
                            Text(info.subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SpeedDialSheet

/// 3-column quick-tap Speed Dial sheet mirroring Mochy Music's SpeedDialSheet.
struct SpeedDialSheet: View {
    let tracks: [Track]

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                if tracks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.mochySecondary)
                        Text("Play or favorite some songs to populate Speed Dial.")
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            let isCurrent = player.currentTrack?.id == track.id
                            Button {
                                player.play(tracks: tracks, startIndex: index)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack(alignment: .bottomTrailing) {
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
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(isCurrent ? settings.accentColor : Color.white.opacity(0.08), lineWidth: isCurrent ? 2 : 1)
                                        )

                                        Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(isCurrent ? settings.accentColor : .white.opacity(0.9))
                                            .shadow(radius: 4)
                                            .padding(6)
                                    }

                                    Text(track.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(isCurrent ? settings.accentColor : .mochyOnBackground)
                                        .lineLimit(1)

                                    Text(track.artistsText)
                                        .font(.system(size: 10))
                                        .foregroundColor(.mochySecondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .navigationTitle("Speed Dial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !tracks.isEmpty {
                        Button {
                            player.play(tracks: tracks.shuffled(), startIndex: 0)
                            dismiss()
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(settings.accentColor)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.mochyOnBackground)
                }
            }
        }
    }
}
