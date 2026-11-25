import SwiftUI

struct AppBehaviourSettingsScreen: View {
    @ObservedObject private var settings = AppSettings.shared

    private let languages: [(code: String, name: String)] = [
        ("vi", "Tiếng Việt"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("zh", "中文")
    ]

    private let countries: [(code: String, name: String)] = [
        ("VN", "Việt Nam"),
        ("US", "United States"),
        ("JP", "Japan"),
        ("KR", "South Korea"),
        ("GB", "United Kingdom"),
        ("SG", "Singapore")
    ]

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                themeAndAccentSection
                typographyAndAnimationSection
                gesturesSection
                layoutAndRegionSection
                experimentalSection
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Giao diện & Cử chỉ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Theme & Accent

    private var themeAndAccentSection: some View {
        MochySettingsCard(title: "Giao diện & Màu sắc") {
            MochySettingsToggleRow(
                title: "AMOLED Đen thuần (#000000)",
                subtitle: "Tiết kiệm pin trên màn hình OLED với nền đen tuyệt đối",
                icon: "moon.stars.fill",
                tint: settings.accentColor,
                isOn: $settings.pureBlack
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Mini Player đen thuần",
                subtitle: "Áp dụng nền đen thuần cho thanh trình phát thu gọn",
                icon: "rectangle.bottomthird.inset.filled",
                tint: .mochySecondary,
                isOn: $settings.pureBlackMiniPlayer
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Dynamic Theme theo ảnh bìa",
                subtitle: "Tự động trích xuất tông màu chủ đạo từ bài hát đang phát",
                icon: "paintpalette.fill",
                tint: .mochyMauve,
                isOn: $settings.dynamicTheme
            )

            MochySettingsDivider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Màu nhấn (Accent Color)")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(MochyAccentPreset.allCases) { preset in
                            let selected = settings.accentPreset == preset
                            Button {
                                withAnimation(MochyTheme.snappySpring) {
                                    settings.accentPreset = preset
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 34, height: 34)
                                        if selected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.black)
                                        }
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 2 : 1)
                                    )

                                    Text(preset.displayName)
                                        .font(.system(size: 10, weight: selected ? .bold : .medium))
                                        .foregroundColor(selected ? preset.color : .mochySecondary)
                                }
                                .frame(width: 56)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Typography & Animation

    private var typographyAndAnimationSection: some View {
        MochySettingsCard(title: "Cỡ chữ & Hoạt ảnh") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Kích thước chữ")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)

                Picker("Kích thước chữ", selection: $settings.fontSizePresetRaw) {
                    ForEach(AppFontSizePreset.allCases) { preset in
                        Text(fontPresetTitle(preset)).tag(preset.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            MochySettingsDivider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MochySettingsRowIcon(systemName: "speedometer", tint: .mochyTeal)
                    Text("Tốc độ hoạt ảnh")
                        .font(.mochyBody.weight(.medium))
                        .foregroundColor(.mochyOnSurface)
                    Spacer()
                    Text(String(format: "%.2fx", settings.animationSpeed))
                        .font(.mochyMono)
                        .foregroundColor(settings.accentColor)
                }
                Slider(value: $settings.animationSpeed, in: 0.5...2.0, step: 0.25)
                    .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MochySettingsRowIcon(systemName: "square.dashed", tint: .mochyBlue)
                    Text("Bo góc thẻ giao diện")
                        .font(.mochyBody.weight(.medium))
                        .foregroundColor(.mochyOnSurface)
                    Spacer()
                    Text("\(Int(settings.cornerRadius)) pt")
                        .font(.mochyMono)
                        .foregroundColor(settings.accentColor)
                }
                Slider(value: $settings.cornerRadius, in: 6...24, step: 1)
                    .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Swipe Gestures

    private var gesturesSection: some View {
        MochySettingsCard(title: "Cử chỉ vuốt (Gestures)") {
            HStack {
                MochySettingsRowIcon(systemName: "arrow.left.circle.fill", tint: .mochyPink)
                Text("Vuốt sang trái")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                Spacer()
                Picker("", selection: $settings.swipeLeftActionRaw) {
                    ForEach(SwipeAction.allCases) { action in
                        Text(action.displayName).tag(action.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            HStack {
                MochySettingsRowIcon(systemName: "arrow.right.circle.fill", tint: .mochyGreen)
                Text("Vuốt sang phải")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                Spacer()
                Picker("", selection: $settings.swipeRightActionRaw) {
                    ForEach(SwipeAction.allCases) { action in
                        Text(action.displayName).tag(action.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Vuốt ảnh bìa để chuyển bài",
                subtitle: "Vuốt ngang trên ảnh bìa ở màn hình Now Playing",
                icon: "hand.draw.fill",
                tint: .mochyPeach,
                isOn: $settings.swipeToSong
            )
        }
    }

    // MARK: - Layout & Region

    private var layoutAndRegionSection: some View {
        MochySettingsCard(title: "Bố cục & Khu vực nội dung") {
            HStack {
                MochySettingsRowIcon(systemName: "globe", tint: .mochySapphire)
                Text("Ngôn ngữ nội dung")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                Spacer()
                Picker("", selection: $settings.contentLanguage) {
                    ForEach(languages, id: \.code) { item in
                        Text(item.name).tag(item.code)
                    }
                }
                .pickerStyle(.menu)
                .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            HStack {
                MochySettingsRowIcon(systemName: "mappin.and.ellipse", tint: .mochyYellow)
                Text("Quốc gia bảng xếp hạng")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                Spacer()
                Picker("", selection: $settings.contentCountry) {
                    ForEach(countries, id: \.code) { item in
                        Text(item.name).tag(item.code)
                    }
                }
                .pickerStyle(.menu)
                .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            HStack {
                MochySettingsRowIcon(systemName: "rectangle.3.group.fill", tint: .mochyLavender)
                Text("Kiểu Trang chủ")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                Spacer()
                Picker("", selection: $settings.homeStyleRaw) {
                    ForEach(HomeStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Ẩn mô tả phụ trong Cài đặt",
                subtitle: "Giao diện danh sách gọn gàng hơn",
                icon: "eye.slash.fill",
                tint: .mochySecondary,
                isOn: $settings.hideSettingsDescriptions
            )
        }
    }

    // MARK: - Experimental Flags

    private var experimentalSection: some View {
        MochySettingsCard(title: "Tính năng thử nghiệm (Experimental)") {
            MochySettingsToggleRow(
                title: "Hàng chờ vô tận (Infinite Queue)",
                subtitle: "Liên tục thêm bài hát liên quan không giới hạn",
                icon: "infinity.circle.fill",
                tint: .mochyMauve,
                isOn: $settings.infiniteQueue
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Không tự bỏ qua khi lỗi stream",
                subtitle: "Giữ nguyên vị trí và hiển thị lỗi thay vì chuyển bài",
                icon: "exclamationmark.triangle.fill",
                tint: .mochyYellow,
                isOn: $settings.dontSkipOnFailure
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Tối ưu phần cứng âm thanh (Audio Offload)",
                subtitle: "Giảm tiêu thụ CPU khi phát nhạc nền dài",
                icon: "cpu.fill",
                tint: .mochyTeal,
                isOn: $settings.audioOffload
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Ẩn huy hiệu chất lượng âm thanh",
                subtitle: "Ẩn nhãn AAC / Lossless / Hi-Res trên trình phát",
                icon: "tag.slash.fill",
                tint: .mochyRed,
                isOn: $settings.hideAudioQualityBadge
            )
        }
    }

    private func fontPresetTitle(_ preset: AppFontSizePreset) -> String {
        switch preset {
        case .compact: return "Nhỏ gọn"
        case .normal: return "Chuẩn"
        case .large: return "Lớn"
        }
    }
}
