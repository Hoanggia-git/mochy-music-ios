import SwiftUI

/// AMOLED album card with rounded artwork, explicit badge, and artist/year metadata.
struct AlbumCard: View {
    let album: Album
    let onTap: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    private var cardWidth: CGFloat {
        switch settings.gridItemSize {
        case "small": return 132
        case "large": return 174
        default: return 152
        }
    }

    init(album: Album, onTap: @escaping () -> Void) {
        self.album = album
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    MochyArtworkView(
                        url: album.artworkURL,
                        cornerRadius: CGFloat(settings.thumbnailCornerRadius),
                        placeholderIcon: "opticaldisc"
                    )
                    .frame(width: cardWidth, height: cardWidth)
                    .overlay(
                        RoundedRectangle(cornerRadius: CGFloat(settings.thumbnailCornerRadius), style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )

                    if album.explicit {
                        Text("E")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.mochyPrimary.opacity(0.92))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mochyOnSurface)
                        .lineLimit(1)

                    Text(subtitleText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitleText: String {
        if let year = album.year {
            return "\(album.artistsText) • \(year)"
        }
        return album.artistsText
    }
}
