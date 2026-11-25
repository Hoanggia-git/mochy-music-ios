import Foundation

/// ViewModel managing YouTube Music search queries, live suggestions, filter tabs, and pagination.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var submittedQuery: String = ""
    @Published var suggestions: [SearchSuggestion] = []
    @Published var allSections: [HomeSection] = []
    @Published var filteredItems: [SearchResultItem] = []
    @Published var selectedFilter: SearchFilter? = nil // nil represents "All"
    @Published var continuation: String?
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var isLoadingSuggestions: Bool = false
    @Published var error: String?

    private var suggestionTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    var hasResults: Bool {
        selectedFilter == nil ? !allSections.isEmpty : !filteredItems.isEmpty
    }

    func onQueryChanged(_ newValue: String) {
        suggestionTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = []
            return
        }

        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await loadSuggestions(for: trimmed)
        }
    }

    func loadSuggestions(for text: String? = nil) async {
        let target = (text ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            suggestions = []
            return
        }

        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        do {
            let remote = try await InnerTubeService.shared.searchSuggestions(query: target)
            let historyMatches = LibraryStore.shared.searchHistory
                .filter { $0.localizedCaseInsensitiveContains(target) }
                .prefix(3)
                .map { SearchSuggestion(text: $0, isHistory: true) }

            var merged = historyMatches
            for item in remote where !merged.contains(where: { $0.text.caseInsensitiveCompare(item.text) == .orderedSame }) {
                merged.append(item)
            }
            suggestions = merged
        } catch {
            suggestions = LibraryStore.shared.searchHistory
                .filter { $0.localizedCaseInsensitiveContains(target) }
                .map { SearchSuggestion(text: $0, isHistory: true) }
        }
    }

    func search(overrideQuery: String? = nil) async {
        if let overrideQuery {
            query = overrideQuery
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchTask?.cancel()
        submittedQuery = trimmed
        suggestions = []
        LibraryStore.shared.addSearchQuery(trimmed)

        isLoading = true
        error = nil
        continuation = nil

        do {
            if let filter = selectedFilter {
                let result = try await InnerTubeService.shared.search(query: trimmed, filter: filter, continuation: nil)
                filteredItems = filterSearchItems(result.items)
                continuation = result.continuation
                allSections = []
            } else {
                let sections = try await InnerTubeService.shared.searchAll(query: trimmed)
                allSections = filterSections(sections)
                filteredItems = []
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func selectFilter(_ filter: SearchFilter?) async {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        let target = submittedQuery.isEmpty ? query.trimmingCharacters(in: .whitespacesAndNewlines) : submittedQuery
        if !target.isEmpty {
            await search(overrideQuery: target)
        }
    }

    func loadMore() async {
        guard !isLoadingMore,
              let filter = selectedFilter,
              let token = continuation,
              !token.isEmpty else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await InnerTubeService.shared.search(query: submittedQuery, filter: filter, continuation: token)
            let existingIds = Set(filteredItems.map(\.id))
            let additions = filterSearchItems(result.items).filter { !existingIds.contains($0.id) }
            filteredItems.append(contentsOf: additions)
            continuation = result.continuation
        } catch {
            // Keep existing results on pagination error
        }
    }

    func clearSearch() {
        query = ""
        submittedQuery = ""
        suggestions = []
        allSections = []
        filteredItems = []
        continuation = nil
        error = nil
    }

    private func filterSearchItems(_ items: [SearchResultItem]) -> [SearchResultItem] {
        let hideExplicit = AppSettings.shared.hideExplicit
        let hideVideoSongs = AppSettings.shared.hideVideoSongs
        return items.filter { item in
            switch item {
            case .track(let track):
                if hideExplicit && track.explicit { return false }
                if hideVideoSongs && track.isVideo { return false }
                return true
            case .album(let album):
                return !(hideExplicit && album.explicit)
            case .artist, .playlist:
                return true
            }
        }
    }

    private func filterSections(_ sections: [HomeSection]) -> [HomeSection] {
        let hideExplicit = AppSettings.shared.hideExplicit
        let hideVideoSongs = AppSettings.shared.hideVideoSongs
        return sections.compactMap { section in
            let items = section.items.filter { item in
                switch item {
                case .track(let track):
                    if hideExplicit && track.explicit { return false }
                    if hideVideoSongs && track.isVideo { return false }
                    return true
                case .album(let album):
                    return !(hideExplicit && album.explicit)
                case .artist, .playlist:
                    return true
                }
            }
            guard !items.isEmpty else { return nil }
            var copy = section
            copy.items = items
            return copy
        }
    }
}
