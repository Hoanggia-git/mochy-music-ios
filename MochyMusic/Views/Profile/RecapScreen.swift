import SwiftUI

struct RecapScreen: View {
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var router = NavigationRouter.shared

    @State private var selectedDayKey: String?

    init() {}

    private var stats: ListeningStats {
        library.listeningStats
    }

    private var totalTracksPlayed: Int {
        stats.trackPlayCounts.values.reduce(0, +)
    }

    private var last7Days: [(date: String, seconds: TimeInterval)] {
        library.listeningSecondsForLastDays(7)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryHeroCard
                weeklyBarChartCard
                topTracksCard
                topArtistsCard
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Listening Recap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: shareSummaryText) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(settings.accentColor)
                }
            }
        }
    }

    // MARK: - Shareable Recap Hero Card

    private var summaryHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MOCHY MUSIC RECAP")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(settings.accentColor)
                    Text(settings.username)
                        .font(.mochyTitle)
                        .foregroundColor(.white)
                }
                Spacer()
                MochyAvatarBadge(picUri: settings.profilePicUri, accent: settings.accentColor, size: 48)
            }

            HStack(spacing: 10) {
                metricBox(
                    value: formattedDuration(stats.totalListeningSeconds),
                    label: "Thời gian nghe",
                    icon: "clock.fill",
                    tint: settings.accentColor
                )
                metricBox(
                    value: "\(totalTracksPlayed)",
                    label: "Lượt phát",
                    icon: "play.circle.fill",
                    tint: .mochyBlue
                )
                metricBox(
                    value: "\(stats.artistPlayCounts.count)",
                    label: "Nghệ sĩ",
                    icon: "music.mic",
                    tint: .mochyMauve
                )
            }

            ShareLink(item: shareSummaryText) {
                Label("Chia sẻ thẻ Recap của bạn", systemImage: "sparkles")
                    .font(.mochyBody.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(settings.accentColor))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [settings.accentColor.opacity(0.22), Color.mochySurface, Color.mochyBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                .stroke(settings.accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    private func metricBox(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
            Text(value)
                .font(.mochyHeadline)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.mochySecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    // MARK: - 7-Day Bar Chart (Pure SwiftUI iOS 16)

    private var weeklyBarChartCard: some View {
        let maxSeconds = max(60, last7Days.map(\.seconds).max() ?? 60)

        return MochySettingsCard(title: "Biểu đồ 7 ngày gần đây") {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedKey = selectedDayKey,
                   let match = last7Days.first(where: { $0.date == selectedKey }) {
                    Text("\(shortDayLabel(match.date)): \(formattedDuration(match.seconds))")
                        .font(.mochyCaption.weight(.semibold))
                        .foregroundColor(settings.accentColor)
                } else {
                    Text("Chạm vào cột để xem chi tiết từng ngày")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(last7Days, id: \.date) { day in
                        let ratio = max(0.08, day.seconds / maxSeconds)
                        let isSelected = selectedDayKey == day.date

                        Button {
                            withAnimation(MochyTheme.snappySpring) {
                                selectedDayKey = (selectedDayKey == day.date) ? nil : day.date
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text("\(Int(day.seconds / 60))p")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(isSelected ? settings.accentColor : .mochySecondary)

                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                isSelected ? settings.accentColor : settings.accentColor.opacity(0.75),
                                                settings.accentColor.opacity(0.25)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: CGFloat(120.0 * ratio))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                                    )

                                Text(shortDayLabel(day.date))
                                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                    .foregroundColor(isSelected ? .white : .mochySecondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 165, alignment: .bottom)
            }
            .padding(16)
        }
    }

    // MARK: - Top Tracks

    private var topTracksCard: some View {
        let top = Array(stats.topTracks.prefix(10))

        return MochySettingsCard(title: "Top bài hát nghe nhiều nhất") {
            if top.isEmpty {
                emptyStatsPlaceholder("Hãy phát nhạc để thống kê bài hát yêu thích của bạn")
            } else {
                ForEach(Array(top.enumerated()), id: \.element.track.id) { index, item in
                    Button {
                        AudioPlayerManager.shared.play(track: item.track)
                    } label: {
                        HStack(spacing: 12) {
                            Text("#\(index + 1)")
                                .font(.mochyMono)
                                .foregroundColor(index < 3 ? settings.accentColor : .mochySecondary)
                                .frame(width: 28, alignment: .leading)

                            AsyncImage(url: item.track.artworkURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Color.mochySurfaceVariant
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.track.title)
                                    .font(.mochyBody.weight(.semibold))
                                    .foregroundColor(.mochyOnSurface)
                                    .lineLimit(1)
                                Text(item.track.artistsText)
                                    .font(.mochyCaption)
                                    .foregroundColor(.mochySecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text("\(item.count) lượt")
                                .font(.mochyCaption.weight(.semibold))
                                .foregroundColor(settings.accentColor)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if index < top.count - 1 {
                        MochySettingsDivider()
                    }
                }
            }
        }
    }

    // MARK: - Top Artists

    private var topArtistsCard: some View {
        let top = Array(stats.topArtists.prefix(10))

        return MochySettingsCard(title: "Top nghệ sĩ") {
            if top.isEmpty {
                emptyStatsPlaceholder("Chưa có dữ liệu nghệ sĩ")
            } else {
                ForEach(Array(top.enumerated()), id: \.element.artist.id) { index, item in
                    Button {
                        if !item.artist.isLocal {
                            router.push(.artist(id: item.artist.id))
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("#\(index + 1)")
                                .font(.mochyMono)
                                .foregroundColor(index < 3 ? settings.accentColor : .mochySecondary)
                                .frame(width: 28, alignment: .leading)

                            AsyncImage(url: item.artist.artworkURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    ZStack {
                                        Color.mochySurfaceVariant
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.mochySecondary)
                                    }
                                }
                            }
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())

                            Text(item.artist.name)
                                .font(.mochyBody.weight(.semibold))
                                .foregroundColor(.mochyOnSurface)
                                .lineLimit(1)

                            Spacer()

                            Text("\(item.count) lượt")
                                .font(.mochyCaption)
                                .foregroundColor(.mochySecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if index < top.count - 1 {
                        MochySettingsDivider()
                    }
                }
            }
        }
    }

    private func emptyStatsPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.mochyCaption)
            .foregroundColor(.mochySecondary)
            .frame(maxWidth: .infinity)
            .padding(22)
    }

    // MARK: - Helpers

    private var shareSummaryText: String {
        let topTrack = stats.topTracks.first?.track.title ?? "N/A"
        let topArtist = stats.topArtists.first?.artist.name ?? "N/A"
        return """
        🎧 Mochy Music Recap — \(settings.username)
        ⏱ Thời gian nghe: \(formattedDuration(stats.totalListeningSeconds))
        ▶️ Tổng lượt phát: \(totalTracksPlayed)
        🏆 Bài hát #1: \(topTrack)
        ⭐️ Nghệ sĩ #1: \(topArtist)
        """
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMins = Int(seconds / 60)
        let hours = totalMins / 60
        let mins = totalMins % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins) phút"
    }

    private func shortDayLabel(_ dateKey: String) -> String {
        let parts = dateKey.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[2])/\(parts[1])"
        }
        return dateKey
    }
}
