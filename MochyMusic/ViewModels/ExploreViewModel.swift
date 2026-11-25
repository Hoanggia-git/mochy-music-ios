import Foundation

/// ViewModel driving the Explore / Discover feed (New Releases, Charts, Moods & Genres, Trending).
@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var newReleases: [Album] = []
    @Published var chartsSections: [HomeSection] = []
    @Published var moodsAndGenres: [MoodAndGenreItem] = []
    @Published var trendingTracks: [Track] = []
    @Published var exploreSections: [HomeSection] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var hasLoadedOnce = false

    func loadExploreFeedIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await loadExploreFeed()
    }

    func loadExploreFeed() async {
        isLoading = true
        error = nil

        async let exploreTask = fetchExploreSafely()
        async let chartsTask = fetchChartsSafely()
        async let moodsTask = fetchMoodsSafely()
        async let releasesTask = fetchNewReleasesSafely()

        let (exploreResult, chartsResult, moods, releases) = await (
            exploreTask,
            chartsTask,
            moodsTask,
            releasesTask
        )

        if let exploreResult {
            exploreSections = exploreResult.sections
        }

        if let chartsResult {
            chartsSections = chartsResult.sections
            trendingTracks = extractTracks(from: chartsResult.sections)
        } else if let exploreResult {
            trendingTracks = extractTracks(from: exploreResult.sections)
        }

        moodsAndGenres = moods

        if !releases.isEmpty {
            newReleases = releases
        } else if let exploreResult {
            newReleases = extractAlbums(from: exploreResult.sections)
        }

        if exploreSections.isEmpty && chartsSections.isEmpty && moodsAndGenres.isEmpty && newReleases.isEmpty {
            error = "Unable to load Explore feed. Check your connection and pull to retry."
        } else {
            hasLoadedOnce = true
        }

        isLoading = false
    }

    private func fetchExploreSafely() async -> BrowseResult? {
        try? await InnerTubeService.shared.fetchExploreFeed()
    }

    private func fetchChartsSafely() async -> BrowseResult? {
        try? await InnerTubeService.shared.fetchCharts()
    }

    private func fetchMoodsSafely() async -> [MoodAndGenreItem] {
        (try? await InnerTubeService.shared.fetchMoodsAndGenres()) ?? []
    }

    private func fetchNewReleasesSafely() async -> [Album] {
        (try? await InnerTubeService.shared.fetchNewReleases()) ?? []
    }

    private func extractTracks(from sections: [HomeSection]) -> [Track] {
        var collected: [Track] = []
        for section in sections {
            for item in section.items {
                if case .track(let track) = item {
                    if !collected.contains(where: { $0.id == track.id }) {
                        collected.append(track)
                    }
                }
            }
        }
        return collected
    }

    private func extractAlbums(from sections: [HomeSection]) -> [Album] {
        var collected: [Album] = []
        for section in sections {
            for item in section.items {
                if case .album(let album) = item {
                    if !collected.contains(where: { $0.id == album.id }) {
                        collected.append(album)
                    }
                }
            }
        }
        return collected
    }
}
