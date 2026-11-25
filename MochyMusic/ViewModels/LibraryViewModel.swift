import Foundation

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case title = "Title A–Z"
    case artist = "Artist A–Z"
    case duration = "Duration"

    var id: String { rawValue }
}

/// ViewModel wrapping `LibraryStore.shared` with sorting, filtering, and folder grouping helpers.
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var sortOption: LibrarySortOption = .recent

    private let store = LibraryStore.shared

    func filteredFavorites(from tracks: [Track]) -> [Track] {
        let filtered = filterTracks(tracks)
        return sortTracks(filtered)
    }

    func filteredDownloads(from records: [DownloadedTrackRecord]) -> [DownloadedTrackRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [DownloadedTrackRecord]
        if query.isEmpty {
            base = records
        } else {
            base = records.filter {
                $0.track.title.localizedCaseInsensitiveContains(query) ||
                $0.track.artistsText.localizedCaseInsensitiveContains(query)
            }
        }

        switch sortOption {
        case .recent:
            return base.sorted { $0.downloadedAt > $1.downloadedAt }
        case .title:
            return base.sorted { $0.track.title.localizedCaseInsensitiveCompare($1.track.title) == .orderedAscending }
        case .artist:
            return base.sorted { $0.track.artistsText.localizedCaseInsensitiveCompare($1.track.artistsText) == .orderedAscending }
        case .duration:
            return base.sorted { ($0.track.durationSeconds ?? 0) > ($1.track.durationSeconds ?? 0) }
        }
    }

    func groupedHistory(_ entries: [HistoryEntry]) -> [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? entries : entries.filter {
            $0.track.title.localizedCaseInsensitiveContains(query) ||
            $0.track.artistsText.localizedCaseInsensitiveContains(query)
        }

        var today: [HistoryEntry] = []
        var yesterday: [HistoryEntry] = []
        var thisWeek: [HistoryEntry] = []
        var earlier: [HistoryEntry] = []

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        for entry in filtered {
            if calendar.isDateInToday(entry.playedAt) {
                today.append(entry)
            } else if calendar.isDateInYesterday(entry.playedAt) {
                yesterday.append(entry)
            } else if entry.playedAt >= weekAgo {
                thisWeek.append(entry)
            } else {
                earlier.append(entry)
            }
        }

        var groups: [(String, [HistoryEntry])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { groups.append(("This Week", thisWeek)) }
        if !earlier.isEmpty { groups.append(("Earlier", earlier)) }
        return groups
    }

    func groupedLocalTracksByFolder(_ tracks: [Track]) -> [(folder: String, tracks: [Track])] {
        let filtered = filterTracks(tracks)
        var map: [String: [Track]] = [:]

        for track in filtered {
            let folderName: String
            if let path = track.localFileURL {
                let url = URL(fileURLWithPath: path)
                let parent = url.deletingLastPathComponent().lastPathComponent
                folderName = parent.isEmpty ? "Documents" : parent
            } else {
                folderName = "Local Audio"
            }
            map[folderName, default: []].append(track)
        }

        return map
            .map { (folder: $0.key, tracks: sortTracks($0.value)) }
            .sorted { $0.folder.localizedCaseInsensitiveCompare($1.folder) == .orderedAscending }
    }

    func scanLocalFiles() async {
        await store.scanLocalMusic()
    }

    private func filterTracks(_ tracks: [Track]) -> [Track] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artistsText.localizedCaseInsensitiveContains(query) ||
            ($0.album?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func sortTracks(_ tracks: [Track]) -> [Track] {
        switch sortOption {
        case .recent:
            return tracks
        case .title:
            return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            return tracks.sorted { $0.artistsText.localizedCaseInsensitiveCompare($1.artistsText) == .orderedAscending }
        case .duration:
            return tracks.sorted { ($0.durationSeconds ?? 0) > ($1.durationSeconds ?? 0) }
        }
    }
}
