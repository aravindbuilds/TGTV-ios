import Foundation

/// Port of `com.tgtv.mobile.sub.SubtitlesClient`: OpenSubtitles.com search + download,
/// saved to the app cache as `subs_<fileId>.srt`.
final class SubtitlesClient {
    static let shared = SubtitlesClient()

    struct Candidate: Identifiable, Hashable {
        var id: String
        var fileId: Int64
        var fileName: String
        var language: String
        var releaseName: String
        var isCC: Bool
        var rating: Double
    }

    private struct SearchResponse: Codable {
        let data: [Entry]?
    }
    private struct Entry: Codable {
        let id: Int64?
        let attributes: Attributes?
    }
    private struct Attributes: Codable {
        let fileName: String?
        let language: String?
        let releaseName: String?
        let subtitleDownloadCount: Int?
        let rating: Double?
        let flags: String?
    }
    private struct DownloadRequest: Codable {
        let fileId: Int64
    }
    private struct DownloadResponse: Codable {
        let link: String?
        let remainingDownloads: Int?
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    var enabled: Bool { Store.shared.subsEnabled && !Store.shared.openSubtitlesKey.isEmpty }

    func search(fileName: String, imdbId: String? = nil) async -> [Candidate] {
        guard enabled else { return [] }
        let languages = Store.shared.subsLanguages.split(separator: ",").map(String.init).joined(separator: ",")
        var components = URLComponents(string: "https://api.opensubtitles.com/api/v1/subtitles")!
        components.queryItems = [
            URLQueryItem(name: "query", value: TitleParser.canonical(fileName)),
            URLQueryItem(name: "languages", value: languages),
            URLQueryItem(name: "format", value: "srt")
        ]
        if let imdbId { components.queryItems?.append(URLQueryItem(name: "imdb_id", value: imdbId)) }
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue(Store.shared.openSubtitlesKey, forHTTPHeaderField: "Api-Key")
        request.setValue("TGTV/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return [] }
        return (decoded.data ?? []).compactMap { entry in
            guard let id = entry.id else { return nil }
            let a = entry.attributes
            return Candidate(
                id: String(id), fileId: id,
                fileName: a?.fileName ?? "subtitle-\(id).srt",
                language: a?.language ?? "",
                releaseName: a?.releaseName ?? "",
                isCC: (a?.flags ?? "").lowercased().contains("c"),
                rating: a?.rating ?? 0
            )
        }
    }

    @discardableResult
    func download(_ candidate: Candidate, videoFileId: Int) async -> String? {
        guard enabled, let url = URL(string: "https://api.opensubtitles.com/api/v1/download") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Store.shared.openSubtitlesKey, forHTTPHeaderField: "Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(DownloadRequest(fileId: candidate.fileId))
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(DownloadResponse.self, from: data),
              let link = decoded.link,
              let cdn = URL(string: link),
              let (srt, cdnResponse) = try? await session.data(from: cdn),
              (cdnResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tgtv-subs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("subs_\(videoFileId).srt")
        try? srt.write(to: path)
        return path.path
    }

    func cachedPath(for videoFileId: Int) -> String? {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tgtv-subs/subs_\(videoFileId).srt")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let date = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(date) < 86_400 else { return nil }
        return path.path
    }
}
