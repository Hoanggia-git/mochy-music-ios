import SwiftUI

struct PlaybackSettingsScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var router = NavigationRouter.shared
    @ObservedObject private var eq = EqualizerService.shared

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MochySettingsCard(title: "Chất lượng âm thanh") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            MochySettingsRowIcon(systemName: "hifispeaker.fill", tint: settings.accentColor)
                            Text("Chất lượng phát trực tuyến")
                                .font(.mochyBody.weight(.medium))
                                .foregroundColor(.mochyOnSurface)
                            Spacer()
                            Picker("", selection: $settings.audioQualityRaw) {
                                ForEach(StreamQuality.allCases) { quality in
                                    Text(quality.displayName).tag(quality.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(settings.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    MochySettingsDivider()

                    HStack {
                        MochySettingsRowIcon(systemName: "arrow.down.circle.fill", tint: .mochyGreen)
                        Text("Chất lượng tải xuống")
                            .font(.mochyBody.weight(.medium))
                            .foregroundColor(.mochyOnSurface)
                        Spacer()
                        Picker("", selection: $settings.downloadQualityRaw) {
                            ForEach(DownloadQuality.allCases) { quality in
                                Text(quality.displayName).tag(quality.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(settings.accentColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    MochySettingsDivider()

                    MochySettingsToggleRow(
                        title: "Tự động tải khi Thích",
                        subtitle: "Tải bài hát về máy ngay khi bạn nhấn Yêu thích",
                        icon: "heart.circle.fill",
                        tint: .mochyRed,
                        isOn: $settings.autoDownloadOnLike
                    )
                }

                MochySettingsCard(title: "Crossfade & Crossmix") {
                    MochySettingsToggleRow(
                        title: "Bật Crossfade",
                        subtitle: "Hòa âm mượt mà khi chuyển giữa hai bài hát",
                        icon: "waveform.path",
                        tint: .mochyMauve,
                        isOn: $settings.crossfadeEnabled
                    )

                    if settings.crossfadeEnabled {
                        MochySettingsDivider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Thời lượng Crossfade")
                                    .font(.mochyBody.weight(.medium))
                                    .foregroundColor(.mochyOnSurface)
                                Spacer()
                                Text(String(format: "%.1f giây", settings.crossfadeDuration))
                                    .font(.mochyMono)
                                    .foregroundColor(settings.accentColor)
                            }
                            Slider(value: $settings.crossfadeDuration, in: 1...12, step: 0.5)
                                .tint(settings.accentColor)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    MochySettingsDivider()

                    HStack {
                        MochySettingsRowIcon(systemName: "dial.medium.fill", tint: .mochyTeal)
                        Text("Chế độ Crossmix")
                            .font(.mochyBody.weight(.medium))
                            .foregroundColor(.mochyOnSurface)
                        Spacer()
                        Picker("", selection: $settings.crossmixModeRaw) {
                            ForEach(CrossmixMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(settings.accentColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    MochySettingsDivider()

                    HStack {
                        MochySettingsRowIcon(systemName: "sparkles.tv", tint: .mochyPeach)
                        Text("Hiệu ứng chuyển bài")
                            .font(.mochyBody.weight(.medium))
                            .foregroundColor(.mochyOnSurface)
                        Spacer()
                        Picker("", selection: $settings.transportEffectRaw) {
                            ForEach(TransportEffect.allCases) { effect in
                                Text(effect.displayName).tag(effect.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(settings.accentColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    MochySettingsDivider()

                    MochySettingsToggleRow(
                        title: "Phát không khoảng lặng (Gapless)",
                        subtitle: "Giảm tối đa khoảng ngắt giữa các bài trong album",
                        icon: "infinity",
                        tint: .mochyBlue,
                        isOn: $settings.crossfadeGapless
                    )
                }

                MochySettingsCard(title: "Xử lý âm thanh & Hàng chờ") {
                    MochySettingsToggleRow(
                        title: "Chuẩn hóa âm lượng",
                        subtitle: "Cân bằng mức âm lượng theo Loudness dB của track",
                        icon: "speaker.wave.3.fill",
                        tint: .mochyYellow,
                        isOn: $settings.normalization
                    )

                    MochySettingsDivider()

                    MochySettingsToggleRow(
                        title: "Bỏ qua khoảng lặng",
                        subtitle: "Tự động rút ngắn đoạn mở/kết im lặng",
                        icon: "forward.end.fill",
                        tint: .mochySapphire,
                        isOn: $settings.skipSilence
                    )

                    MochySettingsDivider()

                    MochySettingsToggleRow(
                        title: "Lưu hàng chờ phát",
                        subtitle: "Khôi phục danh sách phát dở khi mở lại ứng dụng",
                        icon: "list.bullet.rectangle.fill",
                        tint: .mochyLavender,
                        isOn: $settings.persistentQueue
                    )

                    MochySettingsDivider()

                    MochySettingsToggleRow(
                        title: "Tự động tải thêm gợi ý",
                        subtitle: "Tiếp tục phát Radio tương tự khi hết hàng chờ",
                        icon: "radio.fill",
                        tint: .mochyPink,
                        isOn: $settings.autoLoadMore
                    )

                    MochySettingsDivider()

                    MochySettingsToggleRow(
                        title: "Hòa âm với ứng dụng khác",
                        subtitle: "Không ngắt nhạc khi ứng dụng khác phát âm thanh",
                        icon: "square.stack.3d.up.fill",
                        tint: .mochySecondary,
                        isOn: $settings.mixWithOtherApps
                    )
                }

                MochySettingsCard(title: "AudioLab & DSP") {
                    Button {
                        router.push(.equalizer)
                    } label: {
                        MochySettingsNavRow(
                            title: "Mở AudioLab Equalizer",
                            subtitle: "Preset hiện tại: \(eq.currentPreset.name)",
                            icon: "slider.horizontal.3",
                            tint: settings.accentColor,
                            trailingValue: eq.isEnabled ? "Đang bật" : "Đang tắt"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Phát nhạc & Âm thanh")
        .navigationBarTitleDisplayMode(.inline)
    }
}
