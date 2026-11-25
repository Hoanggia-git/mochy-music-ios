import SwiftUI

/// Centralized floating toast controller for non-blocking feedback banners.
@MainActor
final class MochyToastCenter: ObservableObject {
    static let shared = MochyToastCenter()

    @Published var message: String?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String, duration: TimeInterval = 2.2) {
        dismissTask?.cancel()
        withAnimation(MochyTheme.snappySpring) {
            message = text
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(MochyTheme.snappySpring) {
                self?.message = nil
            }
        }
    }
}

/// Floating AMOLED glass top toast notification banner.
struct TopToastBanner: View {
    var message: String?

    var body: some View {
        VStack {
            if let message, !message.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochyPeach)

                    Text(message)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochyOnSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .glassBackground(intensity: 0.92, tint: .mochySurfaceVariant, cornerRadius: 24, borderOpacity: 0.2)
                .shadow(color: Color.black.opacity(0.55), radius: 14, x: 0, y: 6)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .animation(MochyTheme.snappySpring, value: message)
    }
}
