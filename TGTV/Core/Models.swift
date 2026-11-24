import Foundation

// Wire-compatible models. Property names intentionally match the Kotlin models in TGTVMobile
// so backup files produced by the Android, TV and iOS apps can be shared verbatim.

struct VideoItem: Codable, Hashable, Identifiable {
    var messageId: Int64
    var chatId: Int64
    var chatTitle: String
    var title: String
    var fileId: Int
    var remoteFileId: String
    var fileSize: Int64
    var durationSeconds: Int
    var mimeType: String
    var fileName: String
    var thumbnailFileId: Int?
    var fileKind: String

    var id: String { "\(chatId):\(messageId):\(fileId)" }

    var isSeries: Bool {
        TitleParser.seasonEpisode(fileName) != nil || TitleParser.seasonEpisode(title) != nil
    }

    var prettySize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var prettyDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var remoteId: Int64? { Int64(remoteFileId) }
}

struct WatchProgressEntry: Codable, Hashable {
    var p: Int64   // position, ms
    var d: Int64   // duration, ms
    var u: Int64   // updated, epoch ms

    var resumable: Bool { p > 20_000 && d > 0 && p < d * 97 / 100 }

    static func key(chatId: Int64, messageId: Int64) -> String { "\(chatId):\(messageId)" }
}

struct FavouriteList: Codable, Hashable, Identifiable {
    var name: String
    var items: [VideoItem]
    var id: String { name }
}

struct BackupDocument: Codable {
    var app: String = "TGTV"
    var v: Int = 1
    var at: Int64
    var favLists: [FavouriteList]
    var watchlist: [VideoItem]
    var progress: [String: WatchProgressEntry]
    var pinnedChats: [String]
    var subsEnabled: Bool
    var subsTextSize: Int
    var subsLanguages: String
    var tmdbDisabled: Bool
}

struct SeriesEntry: Identifiable, Hashable {
    var title: String
    var items: [VideoItem]
    var id: String { title }

    static func group(_ items: [VideoItem]) -> [SeriesEntry] {
        var buckets: [String: [VideoItem]] = [:]
        for item in items {
            let clean = TitleParser.canonical(item.title.isEmpty ? item.fileName : item.title)
            buckets[clean, default: []].append(item)
        }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { SeriesEntry(title: $0.key, items: $0.value.sorted { $0.fileName < $1.fileName }) }
            .sorted { $0.title < $1.title }
    }
}

enum TitleParser {
    private static let releaseTokens: [String] = [
        "1080p", "720p", "2160p", "4k", "bluray", "brrip", "webrip", "webdl", "web-dl",
        "h264", "h265", "x264", "x265", "hevc", "aac", "ac3", "dts", "dd5", "10bit",
        "hdr", "dvdrip", "camrip", "remux", "proper", "repack", "extended", "unrated"
    ]

    static func canonical(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        for token in releaseTokens {
            s = s.replacingOccurrences(of: token, with: " ", options: .caseInsensitive)
        }
        if let ep = seasonEpisode(s) {
            s = s.replacingOccurrences(of: ep.original, with: " ")
        }
        s = s.replacingOccurrences(of: "(?<=[a-z])(?=[A-Z])", with: " ", options: .regularExpression)
        return s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func seasonEpisode(_ raw: String) -> (season: Int, episode: Int, original: String)? {
        let patterns = [
            #"[Ss]([0-9]{1,2})[Ee]([0-9]{1,3})"#,
            #"Season[\s._-]*([0-9]{1,2})[\s._-]*Episode[\s._-]*([0-9]{1,3})"#,
            #"(?<!\d)([0-9]{1,2})x([0-9]{2})(?!\d)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  match.numberOfRanges >= 3,
                  let sRange = Range(match.range(at: 1), in: raw),
                  let eRange = Range(match.range(at: 2), in: raw),
                  let season = Int(raw[sRange]), let episode = Int(raw[eRange]) else { continue }
            return (season, episode, String(raw[Range(match.range, in: raw)!]))
        }
        return nil
    }

    static func year(_ raw: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(19|20)[0-9]{2}"#),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range, in: raw) else { return nil }
        return String(raw[range])
    }
}

enum HomeSort: String, CaseIterable, Identifiable {
    case newest, oldest, title, size
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, movies, series, favourites
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
