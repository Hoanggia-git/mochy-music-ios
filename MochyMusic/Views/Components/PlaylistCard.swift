import SwiftUI

/// AMOLED playlist card supporting remote artwork or a 2x2 mosaic cover for local playlists.
struct PlaylistCard: View {
    let title: String
    let subtitle: String?
    let thumbnailURL: String?
    let localTracks: [Track]?
    let onTap: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    private var cardWidth: CGFloat {
        switch settings.gridItemSize {
        case "small": return 132
        case "large": return 174
        default: return 152
        }
    }

    init(
        title: String,
        subtitle: String?,
        thumbnailURL: String?,
        localTracks: [Track]? = nil,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.thumbnailURL = thumbnailURL
        self.localTracks = localTracks
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                coverArt
                    .frame(width: cardWidth, height: cardWidth)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(settings.thumbnailCornerRadius), style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: CGFloat(settings.thumbnailCornerRadius), style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mochyOnSurface)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.mochySecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: cardWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var coverArt: some View {
        let mosaicURLs = (localTracks ?? [])
            .compactMap(\.artworkURL)
            .reduce(into: [URL]()) { result, url in
                if !result.contains(url) {
                    result.append(url)
                }
            }

        if mosaicURLs.count >= 4 {
            let half = cardWidth / 2
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    MochyArtworkView(url: mosaicURLs[0], cornerRadius: 0)
                        .frame(width: half, height: half)
                    MochyArtworkView(url: mosaicURLs[1], cornerRadius: 0)
                        .frame(width: half, height: half)
                }
                HStack(spacing: 1) {
                    MochyArtworkView(url: mosaicURLs[2], cornerRadius: 0)
                        .frame(width: half, height: half)
                    MochyArtworkView(url: mosaicURLs[3], cornerRadius: 0)
                        .frame(width: half, height: half)
                }
            }
        } else if let urlString = thumbnailURL, let url = URL(string: urlString) {
            MochyArtworkView(
                url: url,
                cornerRadius: CGFloat(settings.thumbnailCornerRadius),
                placeholderIcon: "music.note.list"
            )
        } else if let firstArtwork = mosaicURLs.first {
            MochyArtworkView(
                url: firstArtwork,
                cornerRadius: CGFloat(settings.thumbnailCornerRadius),
                placeholderIcon: "music.note.list"
            )
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.mochySurfaceVariant, Color.mochySurface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note.list")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.mochySecondary)
            }
        }
    }
}
