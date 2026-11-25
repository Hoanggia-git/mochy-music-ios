import SwiftUI

/// "Show All" view for any HomeSection with sorting and continuation loading.
struct SectionDetailScreen: View {
    let title: String
    let browseId: String?
    let params: String?
    let initialItems: [HomeSectionItem]

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var items: [HomeSectionItem] = []
    @State private var continuation: String?
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var sortOrder: SectionSortOrder = .original

    enum SectionSortOrder: String, CaseIterable, Identifiable {
        case original = "Default"
        case aToZ = "A–Z"
        case zToA = "Z–A"
        var id: String { rawValue }
    }

    init(
        title: String,
        browseId: String? = nil,
        params: String? = nil,
        initialItems: [HomeSectionItem] = []
    ) {
        self.title = title
        self.browseId = browseId
        self.params = params
        self.initialItems = initialItems
    }

    private let twoColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var sortedItems: [HomeSectionItem] {
        switch sortOrder {
        case .original:
            return items
        case .aToZ:
            return items.sorted { itemTitle($0).localizedCaseInsensitiveCompare(itemTitle($1)) == .orderedAscending }
        case .zToA:
            return items.sorted { itemTitle($0).localizedCaseInsensitiveCompare(itemTitle($1)) == .orderedDescending }
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SectionSortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

                if isLoading && items.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(0..<8, id: \.self) { _ in
                            ShimmerRowPlaceholder()
                        }
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                } else {
                    let tracks = sortedItems.compactMap { item -> Track? in
                        if case .track(let track) = item { return track }
                        return nil
                    }
                    let cards = sortedItems.filter {
                        if case .track = $0 { return false }
                        return true
                    }

                    if !tracks.isEmpty {
                        VStack(spacing: 2) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                                TrackRowView(track: track) {
                                    player.play(tracks: tracks, startIndex: idx)
                                }
                            }
                        }
                        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                    }

                    if !cards.isEmpty {
                        LazyVGrid(columns: twoColumns, spacing: 14) {
                            ForEach(cards) { item in
                                switch item {
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
                                case .track:
                                    EmptyView()
                                }
                            }
                        }
                        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                    }

                    if continuation != nil {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView().tint(settings.accentColor)
                            } else {
                                Color.clear
                                    .frame(height: 24)
                                    .onAppear {
                                        Task { await loadMore() }
                                    }
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            if items.isEmpty {
                items = initialItems
                if let browseId, !browseId.isEmpty {
                    await loadRemote(browseId: browseId)
                }
            }
        }
    }

    private func loadRemote(browseId: String) async {
        isLoading = true
        do {
            let result = try await InnerTubeService.shared.fetchBrowse(browseId: browseId, params: params, continuation: nil)
            let remoteItems = result.sections.flatMap(\.items)
            if !remoteItems.isEmpty {
                items = remoteItems
            }
            continuation = result.continuation
        } catch {
            // Fall back to initialItems if remote fetch fails
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, let browseId, let token = continuation, !token.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await InnerTubeService.shared.fetchBrowse(browseId: browseId, params: params, continuation: token)
            let existing = Set(items.map(\.id))
            let newItems = result.sections.flatMap(\.items).filter { !existing.contains($0.id) }
            items.append(contentsOf: newItems)
            continuation = result.continuation
        } catch {
            // Preserve existing items
        }
    }

    private func itemTitle(_ item: HomeSectionItem) -> String {
        switch item {
        case .track(let track): return track.title
        case .album(let album): return album.name
        case .artist(let artist): return artist.name
        case .playlist(let playlist): return playlist.name
        }
    }
}
