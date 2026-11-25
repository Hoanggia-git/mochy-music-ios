import SwiftUI

struct RecognitionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recognition = RecognitionService.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var router = NavigationRouter.shared

    @State private var pulsePhase: CGFloat = 0

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 10)

                radarOrbView

                statusSection

                if let title = recognition.matchedTitle {
                    matchedResultCard(
                        title: title,
                        artist: recognition.matchedArtist ?? "Unknown Artist",
                        artworkURL: recognition.matchedArtworkURL
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let error = recognition.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.mochyYellow)
                        Text(error)
                            .font(.mochyCaption)
                            .foregroundColor(.mochyOnSurface)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusMedium, style: .continuous)
                            .fill(Color.mochyYellow.opacity(0.14))
                    )
                }

                Spacer()

                controlButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .navigationTitle("Nhận diện nhạc (ShazamKit)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        recognition.stopListening()
                        dismiss()
                    }
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulsePhase = 1.0
                }
            }
            .onDisappear {
                if recognition.isListening {
                    recognition.stopListening()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Concentric Pulsing Radar

    private var radarOrbView: some View {
        let level = CGFloat(recognition.audioLevel)
        let activeScale = recognition.isListening ? (1.0 + level * 0.45) : 1.0

        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                let baseSize = CGFloat(140 + index * 46)
                let ringScale = recognition.isListening
                    ? (1.0 + level * CGFloat(0.25 + Double(index) * 0.12) + pulsePhase * 0.06)
                    : 1.0

                Circle()
                    .stroke(
                        settings.accentColor.opacity(recognition.isListening ? (0.38 - Double(index) * 0.1) : 0.1),
                        lineWidth: 2
                    )
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(ringScale)
                    .animation(.easeOut(duration: 0.14), value: recognition.audioLevel)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            settings.accentColor.opacity(recognition.isListening ? 0.95 : 0.45),
                            settings.accentColor.opacity(0.2)
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 68
                    )
                )
                .frame(width: 118, height: 118)
                .scaleEffect(activeScale)
                .shadow(color: settings.accentColor.opacity(recognition.isListening ? 0.55 : 0.15), radius: 24)
                .animation(.easeOut(duration: 0.12), value: recognition.audioLevel)

            Image(systemName: recognition.isListening ? "waveform" : "shazam.logo.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.black)
        }
        .frame(height: 245)
        .onTapGesture {
            if recognition.isListening {
                recognition.stopListening()
            } else {
                recognition.startListening()
            }
        }
    }

    // MARK: - Status Label

    private var statusSection: some View {
        VStack(spacing: 6) {
            Text(recognition.isListening
                 ? "Đang lắng nghe âm thanh xung quanh..."
                 : (recognition.matchedTitle != nil ? "Đã tìm thấy bài hát!" : "Nhấn để nhận diện bài hát"))
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnSurface)
                .multilineTextAlignment(.center)

            Text(recognition.isListening
                 ? "Đưa micro lại gần nguồn phát nhạc (tối đa 18 giây)"
                 : "Sử dụng ShazamKit & tự động khớp với InnerTube")
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Matched Result Card

    private func matchedResultCard(title: String, artist: String, artworkURL: URL?) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                AsyncImage(url: artworkURL ?? recognition.matchedTrack?.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color.mochySurfaceVariant
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundColor(settings.accentColor)
                        }
                    }
                }
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.mochyHeadline)
                        .foregroundColor(.mochyOnSurface)
                        .lineLimit(2)
                    Text(artist)
                        .font(.mochyBody)
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    if let track = recognition.matchedTrack {
                        AudioPlayerManager.shared.play(track: track)
                        dismiss()
                    }
                } label: {
                    Label("Phát ngay", systemImage: "play.fill")
                        .font(.mochyBody.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(settings.accentColor))
                }
                .disabled(recognition.matchedTrack == nil)
                .opacity(recognition.matchedTrack == nil ? 0.5 : 1.0)

                Button {
                    let query = "\(artist) \(title)"
                    LibraryStore.shared.addSearchQuery(query)
                    dismiss()
                    router.push(.search)
                } label: {
                    Label("Tìm trong Mochy", systemImage: "magnifyingglass")
                        .font(.mochyBody.weight(.semibold))
                        .foregroundColor(.mochyOnSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.mochySurfaceVariant)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                .fill(settings.pureBlack ? Color.mochySurface : Color.mochySurface0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                .stroke(settings.accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Primary Control Button

    private var controlButton: some View {
        Button {
            if recognition.isListening {
                recognition.stopListening()
            } else {
                recognition.startListening()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recognition.isListening ? "stop.fill" : "mic.fill")
                Text(recognition.isListening ? "Dừng lắng nghe" : "Bắt đầu nhận diện")
            }
            .font(.mochyHeadline)
            .foregroundColor(recognition.isListening ? .white : .black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(recognition.isListening ? Color.mochyRed : settings.accentColor)
            )
        }
        .buttonStyle(.plain)
    }
}
