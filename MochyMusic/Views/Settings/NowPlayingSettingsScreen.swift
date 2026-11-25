import SwiftUI

struct NowPlayingSettingsScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showLyricsOrderSheet = false

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                playerStyleGallerySection
                sliderStyleSection
                artworkAndBlurSection
                lyricsAndBackgroundSection
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Now Playing & Styles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLyricsOrderSheet) {
            LyricsProviderSortSheet()
        }
    }

    // MARK: - Player Style Interactive Gallery

    private var playerStyleGallerySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KIỂU TRÌNH PHÁT (PLAYER STYLE)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundColor(.mochySecondary)
                .padding(.horizontal, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PlayerStyle.allCases) { style in
                        let isSelected = settings.playerStyle == style
                        Button {
                            withAnimation(MochyTheme.snappySpring) {
                                settings.playerStyle = style
                            }
                        } label: {
                            VStack(spacing: 10) {
                                playerStyleMiniPreview(for: style, isSelected: isSelected)

                                Text(style.displayName)
                                    .font(.mochyCaption.weight(.semibold))
                                    .foregroundColor(isSelected ? settings.accentColor : .mochyOnSurface)
                                    .lineLimit(1)
                            }
                            .frame(width: 116)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                                    .fill(settings.pureBlack ? Color.mochySurface : Color.mochySurface0)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                                    .stroke(
                                        isSelected ? settings.accentColor : Color.white.opacity(0.08),
                                        lineWidth: isSelected ? 2 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func playerStyleMiniPreview(for style: PlayerStyle, isSelected: Bool) -> some View {
        let accent = isSelected ? settings.accentColor : Color.mochySecondary
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.mochyBackground)
                .frame(height: 112)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            switch style {
            case .flagship, .compact:
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.28))
                        .frame(width: 54, height: 54)
                        .overlay(Image(systemName: "music.note").foregroundColor(accent))
                    Capsule().fill(Color.white.opacity(0.6)).frame(width: 58, height: 4)
                    Capsule().fill(accent).frame(width: 72, height: 3)
                }
            case .turntable:
                VStack(spacing: 8) {
                    Circle()
                        .fill(Color.mochySurfaceVariant)
                        .frame(width: 58, height: 58)
                        .overlay(Circle().stroke(accent, lineWidth: 2))
                        .overlay(Circle().fill(accent).frame(width: 12, height: 12))
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 60, height: 4)
                }
            case .ipod:
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accent.opacity(0.25))
                        .frame(width: 54, height: 34)
                    Circle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 7)
                        .frame(width: 34, height: 34)
                }
            case .video, .poster:
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.4), Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(6)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color.white).frame(width: 48, height: 4)
                        Capsule().fill(accent).frame(width: 64, height: 3)
                    }
                    .padding(12)
                }
            case .lyrics:
                VStack(spacing: 5) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(width: 66, height: 4)
                    Capsule().fill(accent).frame(width: 74, height: 5)
                    Capsule().fill(Color.white.opacity(0.25)).frame(width: 56, height: 4)
                }
            case .timeline:
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.35)).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(Color.white).frame(width: 38, height: 4)
                            Capsule().fill(Color.white.opacity(0.4)).frame(width: 26, height: 3)
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<10, id: \.self) { idx in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(idx < 5 ? accent : Color.white.opacity(0.25))
                                .frame(width: 4, height: CGFloat((idx % 3 + 1) * 5))
                        }
                    }
                }
            case .bedside, .bedsideTiles:
                VStack(spacing: 6) {
                    Text("09:41")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(accent)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 22, height: 22)
                        RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.3)).frame(width: 40, height: 22)
                    }
                }
            }
        }
    }

    // MARK: - Slider Style Picker

    private var sliderStyleSection: some View {
        MochySettingsCard(title: "Thanh tua nhạc (Seekbar)") {
            VStack(spacing: 10) {
                ForEach(SliderStyle.allCases) { style in
                    let selected = settings.sliderStyle == style
                    Button {
                        withAnimation(MochyTheme.snappySpring) {
                            settings.sliderStyle = style
                        }
                    } label: {
                        HStack {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected ? settings.accentColor : .mochySecondary)
                            Text(style.displayName)
                                .font(.mochyBody.weight(.medium))
                                .foregroundColor(.mochyOnSurface)
                            Spacer()
                            sliderPreview(style: style)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if style != SliderStyle.allCases.last {
                        MochySettingsDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sliderPreview(style: SliderStyle) -> some View {
        switch style {
        case .defaultStyle:
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 84, height: 4)
                Capsule().fill(settings.accentColor).frame(width: 50, height: 4)
            }
        case .wavy:
            HStack(spacing: 2) {
                ForEach(0..<14, id: \.self) { i in
                    Capsule()
                        .fill(i < 9 ? settings.accentColor : Color.white.opacity(0.22))
                        .frame(width: 3, height: i % 2 == 0 ? 10 : 5)
                }
            }
        case .slim:
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 84, height: 2)
                Capsule().fill(settings.accentColor).frame(width: 56, height: 2)
            }
        }
    }

    // MARK: - Cover Corner Radius & Blur

    private var artworkAndBlurSection: some View {
        MochySettingsCard(title: "Ảnh bìa & Hiệu ứng nền") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MochySettingsRowIcon(systemName: "square.on.square.squircle.dashed", tint: settings.accentColor)
                    Text("Bo góc ảnh bìa")
                        .font(.mochyBody.weight(.medium))
                        .foregroundColor(.mochyOnSurface)
                    Spacer()
                    Text("\(Int(settings.thumbnailCornerRadius)) pt")
                        .font(.mochyMono)
                        .foregroundColor(settings.accentColor)
                }
                Slider(value: $settings.thumbnailCornerRadius, in: 0...32, step: 1)
                    .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Bật hiệu ứng mờ (Glass Blur)",
                subtitle: "Làm mờ hậu cảnh trình phát và thanh mini player",
                icon: "drop.fill",
                tint: .mochySky,
                isOn: Binding(
                    get: { settings.blurEnabled },
                    set: { settings.blurEnabled = $0 }
                )
            )

            if settings.blurEnabled {
                MochySettingsDivider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cường độ mờ")
                            .font(.mochyBody.weight(.medium))
                            .foregroundColor(.mochyOnSurface)
                        Spacer()
                        Text("\(Int(settings.blurIntensity)) px")
                            .font(.mochyMono)
                            .foregroundColor(settings.accentColor)
                    }
                    Slider(value: $settings.blurIntensity, in: 5...50, step: 1)
                        .tint(settings.accentColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Cắt vuông ảnh bìa (Crop Art)",
                subtitle: "Tự động cắt viền đen cho video/ảnh bìa tỷ lệ 16:9",
                icon: "crop",
                tint: .mochyMauve,
                isOn: $settings.cropAlbumArt
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Giữ màn hình luôn sáng",
                subtitle: "Không tắt màn hình khi đang mở giao diện Now Playing",
                icon: "sun.max.fill",
                tint: .mochyYellow,
                isOn: $settings.keepScreenOn
            )
        }
    }

    // MARK: - Lyrics & Canvas Video Background

    private var lyricsAndBackgroundSection: some View {
        MochySettingsCard(title: "Lời bài hát & Canvas") {
            Button {
                showLyricsOrderSheet = true
            } label: {
                MochySettingsNavRow(
                    title: "Thứ tự nguồn Lời bài hát",
                    subtitle: "Kéo thả để sắp xếp ưu tiên & bật/tắt nhà cung cấp",
                    icon: "list.number",
                    tint: .mochyTeal,
                    trailingValue: settings.lyricsProviderOrder.first?.displayName
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Nền Canvas / Video động",
                subtitle: "Phát video lặp nghệ sĩ (Canvas / YouTube Studio) phía sau",
                icon: "film.fill",
                tint: .mochyPeach,
                isOn: $settings.studioForVideos
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Rung theo nhạc (Music Haptics)",
                subtitle: "Phản hồi xúc giác nhẹ theo nhịp khi thao tác trình phát",
                icon: "iphone.radiowaves.left.and.right",
                tint: .mochyPink,
                isOn: $settings.musicHapticsEnabled
            )
        }
    }
}
