import Foundation

/// A single timestamped lyric line, optionally paired with a translation.
struct LyricLine: Identifiable, Codable, Hashable {
    let id: UUID
    var time: TimeInterval // seconds from track start
    var text: String
    var translation: String?

    init(id: UUID = UUID(), time: TimeInterval, text: String, translation: String? = nil) {
        self.id = id
        self.time = time
        self.text = text
        self.translation = translation
    }
}

/// Resolved lyrics payload returned by `LyricsManager` or a provider service.
struct LyricsResult: Codable, Hashable {
    var syncedLines: [LyricLine]?
    var plainText: String?
    var source: String
    var translatedLyrics: String?
    var translationLanguage: String?

    var isSynced: Bool {
        guard let syncedLines else { return false }
        return !syncedLines.isEmpty
    }

    init(
        syncedLines: [LyricLine]? = nil,
        plainText: String? = nil,
        source: String = "Unknown",
        translatedLyrics: String? = nil,
        translationLanguage: String? = nil
    ) {
        self.syncedLines = syncedLines
        self.plainText = plainText
        self.source = source
        self.translatedLyrics = translatedLyrics
        self.translationLanguage = translationLanguage
    }
}

/// Supported lyrics providers ordered by user preference.
enum LyricsProvider: String, Codable, CaseIterable, Identifiable {
    case lrclib
    case betterLyrics
    case genius
    case musixmatch
    case kugou
    case simpMusic
    case youLyPlus
    case paxsenix
    case netEase
    case qqMusic
    case deezer
    case lrcRed
    case unison

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lrclib: return "LrcLib"
        case .betterLyrics: return "Better Lyrics"
        case .genius: return "Genius"
        case .musixmatch: return "Musixmatch"
        case .kugou: return "KuGou"
        case .simpMusic: return "SimpMusic"
        case .youLyPlus: return "YouLy+"
        case .paxsenix: return "Paxsenix"
        case .netEase: return "NetEase"
        case .qqMusic: return "QQ Music"
        case .deezer: return "Deezer"
        case .lrcRed: return "LRC Red"
        case .unison: return "Unison"
        }
    }
}
