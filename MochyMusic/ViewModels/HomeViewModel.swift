import Foundation
import SwiftUI

/// ViewModel managing the Home feed, quick picks, chips, and paginated sections.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var sections: [HomeSection] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var error: String?
    @Published var continuation: String?
    @Published var selectedMoodParam: String?

    private var hasLoadedOnce = false

    func loadHomeFeedIfNeeded() async {
        guard !hasLoadedOnce, sections.isEmpty else { return }
        await loadHomeFeed()
    }

    func loadHomeFeed(params: String? = nil) async {
        isLoading = true
        error = nil
        selectedMoodParam = params

        do {
            let result = try await InnerTubeService.shared.fetchHomeFeed(continuation: nil, params: params)
            sections = filterSections(result.sections)
            continuation = result.continuation
            hasLoadedOnce = true
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, let token = continuation, !token.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await InnerTubeService.shared.fetchHomeFeed(continuation: token, params: nil)
            let filtered = filterSections(result.sections)
            sections.append(contentsOf: filtered)
            continuation = result.continuation
        } catch {
            // Keep existing feed visible if continuation fails
        }
    }

    func refresh() async {
        await loadHomeFeed(params: selectedMoodParam)
    }

    var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Good night"
        }
    }

    private func filterSections(_ input: [HomeSection]) -> [HomeSection] {
        let hideExplicit = AppSettings.shared.hideExplicit
        let hideVideoSongs = AppSettings.shared.hideVideoSongs

        return input.compactMap { section in
            let filteredItems = section.items.filter { item in
                switch item {
                case .track(let track):
                    if hideExplicit && track.explicit { return false }
                    if hideVideoSongs && track.isVideo { return false }
                    return true
                case .album(let album):
                    if hideExplicit && album.explicit { return false }
                    return true
                case .artist, .playlist:
                    return true
                }
            }
            guard !filteredItems.isEmpty else { return nil }
            var copy = section
            copy.items = filteredItems
            return copy
        }
    }
}
