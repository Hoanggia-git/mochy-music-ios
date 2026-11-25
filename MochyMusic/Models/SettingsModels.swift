import SwiftUI

enum AppThemeMode: String, Codable, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Theo hệ thống"
        case .dark: return "Tối"
        case .light: return "Sáng"
        }
    }
}

enum MochyAccentPreset: String, Codable, CaseIterable, Identifiable {
    case peach
    case mauve
    case blue
    case green
    case pink
    case teal
    case lavender
    case red
    case yellow
    case monochrome

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .peach: return "Peach"
        case .mauve: return "Mauve"
        case .blue: return "Blue"
        case .green: return "Green"
        case .pink: return "Pink"
        case .teal: return "Teal"
        case .lavender: return "Lavender"
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .monochrome: return "Monochrome"
        }
    }

    var color: Color {
        switch self {
        case .peach: return .mochyPeach
        case .mauve: return .mochyMauve
        case .blue: return .mochyBlue
        case .green: return .mochyGreen
        case .pink: return .mochyPink
        case .teal: return .mochyTeal
        case .lavender: return .mochyLavender
        case .red: return .mochyRed
        case .yellow: return .mochyYellow
        case .monochrome: return .mochyPrimary
        }
    }
}

enum HomeStyle: String, Codable, CaseIterable, Identifiable {
    case mochyy
    case listenNow
    case hopIn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mochyy: return "Mochyy"
        case .listenNow: return "Listen Now"
        case .hopIn: return "Hop In"
        }
    }
}

enum PlaylistHeaderStyle: String, Codable, CaseIterable, Identifiable {
    case flow
    case classic
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flow: return "Flow"
        case .classic: return "Classic"
        case .minimal: return "Minimal"
        }
    }
}

enum DownloadQuality: String, Codable, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: return "Cao (~160 kbps)"
        case .medium: return "Trung bình (~128 kbps)"
        case .low: return "Thấp (~50–70 kbps)"
        }
    }
}

enum CrossmixMode: String, Codable, CaseIterable, Identifiable {
    case autoCrossfade
    case off
    case manualCrossfade
    case crossmix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .autoCrossfade: return "Tự động"
        case .off: return "Tắt"
        case .manualCrossfade: return "Thủ công"
        case .crossmix: return "Crossmix"
        }
    }
}

enum CrossmixLength: String, Codable, CaseIterable {
    case short
    case medium
    case long
}

enum CrossmixTempoMatch: String, Codable, CaseIterable {
    case off
    case gentle
    case full
}

enum IpodTheme: String, Codable, CaseIterable {
    case silver
    case black
    case u2
    case trueDark
}

enum IpodWheelColor: String, Codable, CaseIterable {
    case theme
    case white
    case black
    case red
}

enum PlayerEndTimestamp: String, Codable, CaseIterable {
    case endTime
    case timeLeft
}

enum AppFontSizePreset: String, Codable, CaseIterable, Identifiable {
    case compact
    case normal
    case large

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .compact: return 0.9
        case .normal: return 1.0
        case .large: return 1.12
        }
    }
}

/// Centralized persistent user preferences backed by `UserDefaults` / `@AppStorage`.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Appearance & Theme
    @AppStorage("themeMode") var themeModeRaw: String = AppThemeMode.dark.rawValue
    @AppStorage("accentColorPreset") var accentPresetRaw: String = MochyAccentPreset.peach.rawValue
    @AppStorage("dynamicTheme") var dynamicTheme: Bool = false
    @AppStorage("selectedThemeColor") var selectedThemeColor: Int = 0
    @AppStorage("pureBlack") var pureBlack: Bool = true
    @AppStorage("pureBlackMiniPlayer") var pureBlackMiniPlayer: Bool = false
    @AppStorage("appleMusicDarkChrome") var appleMusicDarkChrome: Bool = false

    // MARK: - Blur & Animations
    @AppStorage("disableBlur") var blurDisabled: Bool = false
    @AppStorage("blurQuality") var blurQuality: String = "HIGH"
    @AppStorage("enableProgressiveBlur") var progressiveBlurEnabled: Bool = true
    @AppStorage("enableElementBlurAnimator") var animationsEnabled: Bool = true
    @AppStorage("blurStrengthPx") var blurIntensity: Double = 25.0
    @AppStorage("elementBlur") var elementBlur: Bool = true
    @AppStorage("animationSpeed") var animationSpeed: Double = 1.0

    // MARK: - Layout & Typography
    @AppStorage("cornerRadius") var cornerRadius: Double = 14.0
    @AppStorage("fontSizePreset") var fontSizePresetRaw: String = AppFontSizePreset.normal.rawValue
    @AppStorage("densityScale") var densityScale: Double = 1.0
    @AppStorage("appFontMode") var appFontMode: String = "system"
    @AppStorage("homeStyle") var homeStyleRaw: String = HomeStyle.mochyy.rawValue
    @AppStorage("playlistStyle") var playlistStyleRaw: String = PlaylistHeaderStyle.flow.rawValue
    @AppStorage("defaultOpenTab") var defaultOpenTab: String = "home"
    @AppStorage("slimNavBar") var slimNavBar: Bool = false
    @AppStorage("gridItemSize") var gridItemSize: String = "medium"
    @AppStorage("hideSettingsDescriptions") var hideSettingsDescriptions: Bool = false

    // MARK: - Player UI & Gestures
    @AppStorage("playerStyle") var playerStyleRaw: String = PlayerStyle.flagship.rawValue
    @AppStorage("sliderStyle") var sliderStyleRaw: String = SliderStyle.defaultStyle.rawValue
    @AppStorage("thumbnailCornerRadius") var thumbnailCornerRadius: Double = 14.0
    @AppStorage("cropAlbumArt") var cropAlbumArt: Bool = false
    @AppStorage("hidePlayerThumbnail") var hidePlayerThumbnail: Bool = false
    @AppStorage("playerSwipeDownAnywhere") var playerSwipeDownAnywhere: Bool = true
    @AppStorage("playerSwipeUpFollows") var playerSwipeUpFollows: Bool = true
    @AppStorage("playerStatusBar") var playerStatusBar: Bool = false
    @AppStorage("swipeToSong") var swipeToSong: Bool = true
    @AppStorage("swipeRightAction") var swipeRightActionRaw: String = SwipeAction.addToQueue.rawValue
    @AppStorage("swipeLeftAction") var swipeLeftActionRaw: String = SwipeAction.like.rawValue
    @AppStorage("ipodTheme") var ipodThemeRaw: String = IpodTheme.trueDark.rawValue
    @AppStorage("ipodWheelColor") var ipodWheelColorRaw: String = IpodWheelColor.theme.rawValue
    @AppStorage("playerEndTimestamp") var playerEndTimestampRaw: String = PlayerEndTimestamp.timeLeft.rawValue
    @AppStorage("seekExtraSeconds") var seekExtraSeconds: Bool = false
    @AppStorage("keepScreenOn") var keepScreenOn: Bool = false

    // MARK: - Audio & Playback
    @AppStorage("audioQuality") var audioQualityRaw: String = StreamQuality.auto.rawValue
    @AppStorage("audioNormalization") var normalization: Bool = true
    @AppStorage("skipSilence") var skipSilence: Bool = false
    @AppStorage("persistentQueue") var persistentQueue: Bool = true
    @AppStorage("rememberShuffleAndRepeat") var rememberShuffleAndRepeat: Bool = true
    @AppStorage("shuffleMode") var shuffleMode: Bool = false
    @AppStorage("autoLoadMore") var autoLoadMore: Bool = true
    @AppStorage("infiniteQueue") var infiniteQueue: Bool = false
    @AppStorage("pauseOnMute") var pauseOnMute: Bool = false
    @AppStorage("mixWithOtherApps") var mixWithOtherApps: Bool = false
    @AppStorage("audioOffload") var audioOffload: Bool = false
    @AppStorage("dontSkipOnFailure") var dontSkipOnFailure: Bool = false
    @AppStorage("streamFailureTimeout") var streamFailureTimeout: Int = 10
    @AppStorage("studioForVideos") var studioForVideos: Bool = false

    // MARK: - Crossfade & Crossmix
    @AppStorage("crossfadeEnabled") var crossfadeEnabled: Bool = false
    @AppStorage("crossfadeDuration") var crossfadeDuration: Double = 5.0
    @AppStorage("crossfadeGapless") var crossfadeGapless: Bool = true
    @AppStorage("crossmixMode") var crossmixModeRaw: String = CrossmixMode.crossmix.rawValue
    @AppStorage("crossmixLength") var crossmixLengthRaw: String = CrossmixLength.medium.rawValue
    @AppStorage("crossmixTempoMatch") var crossmixTempoMatchRaw: String = CrossmixTempoMatch.gentle.rawValue
    @AppStorage("transportFadeEnabled") var transportFadeEnabled: Bool = true
    @AppStorage("transportFadeSeconds") var transportFadeSeconds: Double = 2.0
    @AppStorage("transportEffect") var transportEffectRaw: String = TransportEffect.off.rawValue
    @AppStorage("skipBlend") var skipBlend: Bool = false

    // MARK: - Downloads
    @AppStorage("downloadQuality") var downloadQualityRaw: String = DownloadQuality.high.rawValue
    @AppStorage("autoDownloadOnLike") var autoDownloadOnLike: Bool = false

    // MARK: - Lyrics & Providers
    @AppStorage("lyricsProviderOrder") var lyricsProviderOrderRaw: String = LyricsProvider.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage("enableLrclib") var enableLrcLib: Bool = true
    @AppStorage("enableBetterLyrics") var enableBetterLyrics: Bool = true
    @AppStorage("enableGenius") var enableGenius: Bool = true
    @AppStorage("enableMusixmatch") var enableMusixmatch: Bool = true
    @AppStorage("enableKugou") var enableKugou: Bool = true
    @AppStorage("enableSimpMusic") var enableSimpMusic: Bool = true
    @AppStorage("enableYouLyPlus") var enableYouLyPlus: Bool = true
    @AppStorage("enablePaxsenix") var enablePaxsenix: Bool = true
    @AppStorage("enableNetEase") var enableNetEase: Bool = false
    @AppStorage("enableQQMusic") var enableQQMusic: Bool = false
    @AppStorage("enableDeezer") var enableDeezer: Bool = false
    @AppStorage("enableLrcRed") var enableLrcRed: Bool = false
    @AppStorage("enableUnison") var enableUnison: Bool = false

    // MARK: - Content & Region
    @AppStorage("hideExplicit") var hideExplicit: Bool = false
    @AppStorage("hideVideoSongs") var hideVideoSongs: Bool = false
    @AppStorage("hideYoutubeShorts") var hideYoutubeShorts: Bool = true
    @AppStorage("contentLanguage") var contentLanguage: String = "vi"
    @AppStorage("contentCountry") var contentCountry: String = "VN"
    @AppStorage("showArtistSubscriberCount") var showArtistSubscriberCount: Bool = true

    // MARK: - Privacy
    @AppStorage("pauseListenHistory") var pauseListenHistory: Bool = false
    @AppStorage("pauseSearchHistory") var pauseSearchHistory: Bool = false

    // MARK: - Last.fm Scrobbling
    @AppStorage("lastfmScrobblingEnable") var lastFmEnabled: Bool = false
    @AppStorage("lastfmApiKey") var lastFmApiKey: String = ""
    @AppStorage("lastfmApiSecret") var lastFmApiSecret: String = ""
    @AppStorage("lastfmSession") var lastFmSession: String = ""
    @AppStorage("lastfmUsername") var lastFmUsername: String = ""
    @AppStorage("lastfmUseNowPlaying") var lastFmNowPlaying: Bool = true
    @AppStorage("lastfmUseSendLikes") var lastFmSendLikes: Bool = false
    @AppStorage("scrobbleDelayPercent") var scrobbleDelayPercent: Double = 0.5
    @AppStorage("scrobbleMinSongDuration") var scrobbleMinSongDuration: Int = 30

    // MARK: - Discord Rich Presence
    @AppStorage("discordRPCEnable") var discordRPCEnabled: Bool = false
    @AppStorage("discordPresenceClearOnPause") var discordClearOnPause: Bool = true
    @AppStorage("discordActivityType") var discordActivityType: String = "LISTENING"
    @AppStorage("discordToken") var discordToken: String = ""
    @AppStorage("discordUsername") var discordUsername: String = ""
    @AppStorage("discordShowButtons") var discordShowButtons: Bool = true
    @AppStorage("discordShowArtwork") var discordShowArtwork: Bool = true

    // MARK: - Audio Source Modules (InnerTube / Monochrome FLAC / JioSaavn)
    @AppStorage("preferredAudioSource") var preferredAudioSource: String = "innertube"
    @AppStorage("monochromeEnabled") var monochromeEnabled: Bool = true
    @AppStorage("jiosaavnEnabled") var jiosaavnEnabled: Bool = false
    @AppStorage("jiosaavnQuality") var jiosaavnQuality: String = "320"
    @AppStorage("monochromeCustomServers") var monochromeCustomServersJSON: String = "[]"

    // MARK: - YouTube Music Account Session
    @AppStorage("ytInnerTubeCookie") var ytInnerTubeCookie: String = ""
    @AppStorage("ytVisitorData") var ytVisitorData: String = ""
    @AppStorage("ytDataSyncId") var ytDataSyncId: String = ""
    @AppStorage("ytAccountName") var ytAccountName: String = ""
    @AppStorage("ytAccountEmail") var ytAccountEmail: String = ""
    @AppStorage("ytAccountHandle") var ytAccountHandle: String = ""

    // MARK: - Haptics & Audio Badges
    @AppStorage("musicHapticsEnabled") var musicHapticsEnabled: Bool = false
    @AppStorage("hideAudioQualityBadge") var hideAudioQualityBadge: Bool = false

    // MARK: - Recap, Data Saver & Cache
    @AppStorage("enable26Recap") var recapEnabled: Bool = true
    @AppStorage("dataSaver") var dataSaver: Bool = false
    @AppStorage("dataSaverMobileOnly") var dataSaverMobileOnly: Bool = true
    @AppStorage("maxImageCacheSize") var maxImageCacheSize: Int = 512
    @AppStorage("maxSongCacheSize") var maxSongCacheSize: Int = 1024
    @AppStorage("offlineMode") var offlineMode: Bool = false

    // MARK: - Profile & Setup
    @AppStorage("setupCompleted") var setupCompleted: Bool = false
    @AppStorage("username") var username: String = "Mochy Listener"
    @AppStorage("profilePicUri") var profilePicUri: String = ""
    @AppStorage("profileCardNumber") var profileCardNumber: String = "0001"

    // MARK: - YouTube Sync
    @AppStorage("ytmSync") var ytmSync: Bool = false
    @AppStorage("ytSyncLikedSongs") var ytSyncLikedSongs: Bool = true
    @AppStorage("ytExcludeImports") var ytExcludeImports: Bool = true
    @AppStorage("ytReportPlays") var ytReportPlays: Bool = false

    // MARK: - Backup
    @AppStorage("cloudBackupAuto") var cloudBackupAuto: Bool = false
    @AppStorage("cloudBackupEveryMinutes") var cloudBackupEveryMinutes: Int = 60

    // MARK: - Typed Convenience Accessors

    var blurEnabled: Bool {
        get { !blurDisabled }
        set { blurDisabled = !newValue }
    }

    var themeMode: AppThemeMode {
        get { AppThemeMode(rawValue: themeModeRaw) ?? .dark }
        set { themeModeRaw = newValue.rawValue }
    }

    var accentPreset: MochyAccentPreset {
        get { MochyAccentPreset(rawValue: accentPresetRaw) ?? .peach }
        set { accentPresetRaw = newValue.rawValue }
    }

    var accentColor: Color {
        accentPreset.color
    }

    var playerStyle: PlayerStyle {
        get { PlayerStyle(rawValue: playerStyleRaw) ?? .flagship }
        set { playerStyleRaw = newValue.rawValue }
    }

    var sliderStyle: SliderStyle {
        get { SliderStyle(rawValue: sliderStyleRaw) ?? .defaultStyle }
        set { sliderStyleRaw = newValue.rawValue }
    }

    var audioQuality: StreamQuality {
        get { StreamQuality(rawValue: audioQualityRaw) ?? .auto }
        set { audioQualityRaw = newValue.rawValue }
    }

    var downloadQuality: DownloadQuality {
        get { DownloadQuality(rawValue: downloadQualityRaw) ?? .high }
        set { downloadQualityRaw = newValue.rawValue }
    }

    var crossmixMode: CrossmixMode {
        get { CrossmixMode(rawValue: crossmixModeRaw) ?? .crossmix }
        set { crossmixModeRaw = newValue.rawValue }
    }

    var homeStyle: HomeStyle {
        get { HomeStyle(rawValue: homeStyleRaw) ?? .mochyy }
        set { homeStyleRaw = newValue.rawValue }
    }

    var playlistStyle: PlaylistHeaderStyle {
        get { PlaylistHeaderStyle(rawValue: playlistStyleRaw) ?? .flow }
        set { playlistStyleRaw = newValue.rawValue }
    }

    var fontSizePreset: AppFontSizePreset {
        get { AppFontSizePreset(rawValue: fontSizePresetRaw) ?? .normal }
        set { fontSizePresetRaw = newValue.rawValue }
    }

    var swipeRightAction: SwipeAction {
        get { SwipeAction(rawValue: swipeRightActionRaw) ?? .addToQueue }
        set { swipeRightActionRaw = newValue.rawValue }
    }

    var swipeLeftAction: SwipeAction {
        get { SwipeAction(rawValue: swipeLeftActionRaw) ?? .like }
        set { swipeLeftActionRaw = newValue.rawValue }
    }

    var lyricsProviderOrder: [LyricsProvider] {
        get {
            let parsed = lyricsProviderOrderRaw
                .split(separator: ",")
                .compactMap { LyricsProvider(rawValue: String($0)) }
            return parsed.isEmpty ? LyricsProvider.allCases : parsed
        }
        set {
            lyricsProviderOrderRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    var colorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    private init() {}
}
