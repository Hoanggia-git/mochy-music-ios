import SwiftUI

/// Skeleton loading card placeholder matching Mochy Music's AMOLED dark theme.
struct ShimmerCardPlaceholder: View {
    var width: CGFloat = 152

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.mochySurfaceVariant)
                .frame(width: width, height: width)
                .mochyShimmer()

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.mochySurfaceVariant)
                .frame(width: width * 0.82, height: 13)
                .mochyShimmer()

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.mochySurfaceVariant)
                .frame(width: width * 0.56, height: 11)
                .mochyShimmer()
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Skeleton loading track row placeholder matching `TrackRowView` layout.
struct ShimmerRowPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.mochySurfaceVariant)
                .frame(width: 52, height: 52)
                .mochyShimmer()

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.mochySurfaceVariant)
                    .frame(width: 170, height: 14)
                    .mochyShimmer()

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.mochySurfaceVariant)
                    .frame(width: 115, height: 11)
                    .mochyShimmer()
            }

            Spacer()

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.mochySurfaceVariant)
                .frame(width: 34, height: 12)
                .mochyShimmer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}
