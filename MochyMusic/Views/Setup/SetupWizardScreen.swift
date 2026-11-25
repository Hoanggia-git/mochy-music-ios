import SwiftUI

struct SetupWizardScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var importService = ImportService.shared

    let onFinish: () -> Void

    @State private var currentStep = 0
    @State private var selectedEmoji = "🎧"
    @State private var importMessage: String?

    private let totalSteps = 5
    private let emojis = ["🎧", "🎵", "🎸", "🌙", "✨", "🔥", "💿", "🐱"]

    init(onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            topProgressHeader

            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                themeAndPlayerStyleStep.tag(1)
                importMusicStep.tag(2)
                profileIDStep.tag(3)
                readyStep.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(MochyTheme.springAnimation, value: currentStep)

            bottomNavigationBar
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Header

    private var topProgressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Bước \(currentStep + 1)/\(totalSteps)")
                    .font(.mochyMono)
                    .foregroundColor(settings.accentColor)
                Spacer()
                if currentStep < totalSteps - 1 {
                    Button("Bỏ qua") {
                        completeSetup()
                    }
                    .font(.mochyCaption.weight(.semibold))
                    .foregroundColor(.mochySecondary)
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? settings.accentColor : Color.white.opacity(0.14))
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(settings.accentColor.opacity(0.18))
                    .frame(width: 124, height: 124)
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(settings.accentColor)
            }

            VStack(spacing: 8) {
                Text("Chào mừng đến với Mochy Music")
                    .font(.mochyTitle)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Trình phát nhạc AMOLED tối giản, mạnh mẽ với InnerTube, lời bài hát đồng bộ & AudioLab Equalizer.")
                    .font(.mochyBody)
                    .foregroundColor(.mochySecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            VStack(spacing: 10) {
                featureRow(icon: "moon.stars.fill", text: "Thiết kế AMOLED Đen thuần tiết kiệm pin", tint: settings.accentColor)
                featureRow(icon: "text.quote", text: "Lời bài hát đa nguồn: LRCLIB, BetterLyrics, Genius", tint: .mochyTeal)
                featureRow(icon: "slider.vertical.3", text: "AudioLab EQ 10 băng tần & Crossmix mượt mà", tint: .mochyMauve)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private func featureRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            MochySettingsRowIcon(systemName: icon, tint: tint)
            Text(text)
                .font(.mochyCaption.weight(.medium))
                .foregroundColor(.mochyOnSurface)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.mochySurface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Step 2: Theme & Player Style

    private var themeAndPlayerStyleStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Giao diện & Trình phát")
                    .font(.mochyTitle)
                    .foregroundColor(.white)

                MochySettingsCard(title: "Nền & Màu nhấn") {
                    MochySettingsToggleRow(
                        title: "AMOLED Đen thuần",
                        subtitle: "Nền đen #000000 tối đa độ tương phản",
                        icon: "moon.fill",
                        tint: settings.accentColor,
                        isOn: $settings.pureBlack
                    )
                    MochySettingsDivider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(MochyAccentPreset.allCases) { preset in
                                Button {
                                    settings.accentPreset = preset
                                } label: {
                                    Circle()
                                        .fill(preset.color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle().stroke(Color.white, lineWidth: settings.accentPreset == preset ? 2.5 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                    }
                }

                MochySettingsCard(title: "Kiểu màn hình Now Playing") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach([PlayerStyle.flagship, .turntable, .ipod, .poster, .lyrics, .bedside]) { style in
                            let selected = settings.playerStyle == style
                            Button {
                                settings.playerStyle = style
                            } label: {
                                HStack {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selected ? settings.accentColor : .mochySecondary)
                                    Text(style.displayName)
                                        .font(.mochyCaption.weight(.semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selected ? settings.accentColor.opacity(0.18) : Color.mochySurfaceVariant)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    // MARK: - Step 3: Import Music

    private var importMusicStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 52))
                .foregroundColor(settings.accentColor)

            Text("Mang nhạc của bạn theo")
                .font(.mochyTitle)
                .foregroundColor(.white)

            Text("Bạn có thể nhập ngay playlist từ Apple Music hoặc bỏ qua để thiết lập Spotify / TIDAL / CSV sau trong Cài đặt.")
                .font(.mochyBody)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    do {
                        let playlists = try await importService.importFromAppleMusic()
                        importMessage = "Đã nhập \(playlists.count) playlist từ Apple Music!"
                    } catch {
                        importMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "music.note.list")
                    Text(importService.isImporting ? "Đang nhập..." : "Nhập từ Apple Music")
                }
                .font(.mochyBody.weight(.semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(settings.accentColor))
            }
            .disabled(importService.isImporting)

            if let importMessage {
                Text(importMessage)
                    .font(.mochyCaption)
                    .foregroundColor(settings.accentColor)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 4: Profile ID Card

    private var profileIDStep: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("Thẻ Mochy ID của bạn")
                .font(.mochyTitle)
                .foregroundColor(.white)

            VStack(spacing: 14) {
                MochyAvatarBadge(picUri: settings.profilePicUri, accent: settings.accentColor, size: 74)

                Text(settings.username.isEmpty ? "Mochy Listener" : settings.username)
                    .font(.mochyHeadline)
                    .foregroundColor(.white)

                Text("NO. \(settings.profileCardNumber)")
                    .font(.mochyMono)
                    .foregroundColor(settings.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [settings.accentColor.opacity(0.24), Color.mochySurface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(settings.accentColor.opacity(0.4), lineWidth: 1)
            )

            TextField("Tên hiển thị của bạn", text: $settings.username)
                .textFieldStyle(.plain)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.mochySurfaceVariant))
                .foregroundColor(.white)

            HStack(spacing: 10) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                        settings.profilePicUri = "emoji:\(emoji)|#FAB387"
                    } label: {
                        Text(emoji)
                            .font(.system(size: 24))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(selectedEmoji == emoji ? settings.accentColor.opacity(0.25) : Color.mochySurfaceVariant)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Step 5: Ready

    private var readyStep: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.mochyGreen.opacity(0.18))
                    .frame(width: 112, height: 112)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.mochyGreen)
            }

            Text("Mọi thứ đã sẵn sàng!")
                .font(.mochyTitle)
                .foregroundColor(.white)

            Text("Chúc bạn có những giờ phút thư giãn tuyệt vời cùng Mochy Music.")
                .font(.mochyBody)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Bottom Bar

    private var bottomNavigationBar: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Text("Quay lại")
                        .font(.mochyBody.weight(.semibold))
                        .foregroundColor(.mochyOnSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.mochySurfaceVariant))
                }
            }

            Button {
                if currentStep < totalSteps - 1 {
                    withAnimation { currentStep += 1 }
                } else {
                    completeSetup()
                }
            } label: {
                Text(currentStep < totalSteps - 1 ? "Tiếp tục" : "Bắt đầu nghe nhạc")
                    .font(.mochyBody.weight(.bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 14).fill(settings.accentColor))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func completeSetup() {
        settings.setupCompleted = true
        onFinish()
        dismiss()
    }
}
