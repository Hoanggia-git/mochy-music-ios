import SwiftUI

struct ProfileScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = LibraryStore.shared
    @AppStorage("profileBio") private var profileBio: String = "Đam mê âm nhạc trên Mochy Music"

    @State private var isCardFlipped = false
    @State private var selectedEmoji: String = "🎧"
    @State private var selectedColorHex: String = "#FAB387"

    private let avatarEmojis = ["🎧", "🎵", "🎸", "🎹", "🎷", "🌙", "✨", "🦊", "🐱", "🌸", "🔥", "💿"]
    private let avatarColors: [(name: String, hex: String)] = [
        ("Peach", "#FAB387"),
        ("Mauve", "#CBA6F7"),
        ("Blue", "#89B4FA"),
        ("Green", "#A6E3A1"),
        ("Pink", "#F5C2E7"),
        ("Teal", "#94E2D5"),
        ("Red", "#F38BA8"),
        ("Mono", "#E0E0E0")
    ]

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                mochyIDCardSection

                MochySettingsCard(title: "Thông tin hồ sơ") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tên hiển thị")
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                        TextField("Nhập tên của bạn", text: $settings.username)
                            .textFieldStyle(.plain)
                            .font(.mochyBody.weight(.medium))
                            .foregroundColor(.mochyOnSurface)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))

                        Text("Tiểu sử (Bio)")
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                        TextField("Giới thiệu ngắn...", text: $profileBio)
                            .textFieldStyle(.plain)
                            .font(.mochyBody)
                            .foregroundColor(.mochyOnSurface)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))

                        Text("Mã số thẻ Mochy ID")
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                        TextField("0001", text: $settings.profileCardNumber)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.plain)
                            .font(.mochyMono)
                            .foregroundColor(settings.accentColor)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))
                    }
                    .padding(14)
                }

                MochySettingsCard(title: "Biểu tượng & Màu đại diện") {
                    VStack(alignment: .leading, spacing: 14) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(avatarEmojis, id: \.self) { emoji in
                                    let selected = selectedEmoji == emoji
                                    Button {
                                        selectedEmoji = emoji
                                        saveAvatarToken()
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 26))
                                            .frame(width: 48, height: 48)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(selected ? settings.accentColor.opacity(0.24) : Color.mochySurfaceVariant)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(selected ? settings.accentColor : Color.clear, lineWidth: 1.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(avatarColors, id: \.hex) { item in
                                    let selected = selectedColorHex == item.hex
                                    Button {
                                        selectedColorHex = item.hex
                                        saveAvatarToken()
                                    } label: {
                                        Circle()
                                            .fill(Color(hexString: item.hex))
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: selected ? 2.5 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(14)
                }

                NavigationLink {
                    RecapScreen()
                } label: {
                    MochySettingsCard {
                        MochySettingsNavRow(
                            title: "Xem Listening Recap & Thống kê",
                            subtitle: "Top bài hát, nghệ sĩ & biểu đồ 7 ngày",
                            icon: "chart.bar.fill",
                            tint: settings.accentColor
                        )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Hồ sơ Mochy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAvatarToken()
        }
    }

    // MARK: - Flippable Mochy ID Card

    private var mochyIDCardSection: some View {
        VStack(spacing: 8) {
            ZStack {
                cardFront
                    .opacity(isCardFlipped ? 0 : 1)
                    .rotation3DEffect(.degrees(isCardFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))

                cardBack
                    .opacity(isCardFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(isCardFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(height: 205)
            .onTapGesture {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                    isCardFlipped.toggle()
                }
            }

            Text("Chạm vào thẻ để lật mặt sau")
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
        }
    }

    private var cardFront: some View {
        let cardColor = Color(hexString: selectedColorHex)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("MOCHY ID CARD", systemImage: "music.note.house.fill")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(cardColor)
                Spacer()
                Text("NO. \(settings.profileCardNumber)")
                    .font(.mochyMono)
                    .foregroundColor(.mochySecondary)
            }

            HStack(spacing: 14) {
                MochyAvatarBadge(picUri: settings.profilePicUri, accent: cardColor, size: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.username.isEmpty ? "Mochy Listener" : settings.username)
                        .font(.mochyTitle)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(profileBio)
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            Spacer()

            HStack(spacing: 16) {
                statChip(value: "\(library.favorites.count)", label: "Yêu thích")
                statChip(value: "\(library.playlists.count)", label: "Playlist")
                statChip(value: formattedHours(library.listeningStats.totalListeningSeconds), label: "Đã nghe")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [cardColor.opacity(0.28), Color.mochySurface, Color.mochyBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardColor.opacity(0.5), lineWidth: 1.2)
        )
    }

    private var cardBack: some View {
        let cardColor = Color(hexString: selectedColorHex)
        let topArtist = library.listeningStats.topArtists.first?.artist.name ?? "Chưa có dữ liệu"
        let topTrack = library.listeningStats.topTracks.first?.track.title ?? "Chưa có dữ liệu"

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("THÀNH TÍCH ÂM NHẠC")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(cardColor)
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(cardColor)
            }

            Divider().background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 6) {
                Text("Nghệ sĩ nghe nhiều nhất")
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
                Text(topArtist)
                    .font(.mochyHeadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Bài hát yêu thích nhất")
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
                Text(topTrack)
                    .font(.mochyBody.weight(.semibold))
                    .foregroundColor(.mochyPrimary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<22, id: \.self) { idx in
                    Capsule()
                        .fill(cardColor.opacity(idx % 2 == 0 ? 0.7 : 0.3))
                        .frame(width: 4, height: CGFloat(8 + (idx * 7) % 18))
                }
                Spacer()
                Text("MOCHY MUSIC")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.mochySecondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.mochySurfaceVariant, Color.mochyBackground],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardColor.opacity(0.45), lineWidth: 1.2)
        )
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.mochyBody.weight(.bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.mochySecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
    }

    private func formattedHours(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(mins)m"
    }

    private func loadAvatarToken() {
        let uri = settings.profilePicUri
        if uri.hasPrefix("emoji:") {
            let parts = uri.dropFirst(6).split(separator: "|", maxSplits: 1).map(String.init)
            if let emoji = parts.first, !emoji.isEmpty { selectedEmoji = emoji }
            if parts.count > 1, !parts[1].isEmpty { selectedColorHex = parts[1] }
        }
    }

    private func saveAvatarToken() {
        settings.profilePicUri = "emoji:\(selectedEmoji)|\(selectedColorHex)"
    }
}
