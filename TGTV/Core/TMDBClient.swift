import Foundation

/// Port of `com.tgtv.mobile.tmdb.TmdbClient`. Uses the TMDB v3 REST API with an
/// in-memory + disk cache and the same filename cleanup heuristics as Android.
final class TMDBClient {
    static let shared = TMDBClient()

    struct Info: Codable, Hashable {
        var id: Int = 0
        var mediaType: String = "movie"
        var title: String = ""
        var overview: String = ""
        var posterPath: String?
        var backdropPath: String?
        var voteAverage: Double = 0
        var releaseDate: String = ""
        var runtime: Int = 0
        var genres: [String] = []
        var cast: [CastMember] = []
        var seasons: [Season] = []
    }

    struct CastMember: Codable, Hashable {
        var name: String = ""
        var character: String = ""
        var profilePath: String?
    }

    struct Season: Codable, Hashable {
        var seasonNumber: Int = 0
        var name: String = ""
        var overview: String = ""
        var posterPath: String?
        var airDate: String = ""
    }

    private struct SearchResponse: Codable {
        let results: [SearchResult]?
    }
    private struct SearchResult: Codable {
        let id: Int?
        let mediaType: String?
        let title: String?
        let name: String?
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let voteAverage: Double?
        let releaseDate: String?
        let firstAirDate: String?
    }
    private struct DetailResponse: Codable {
        let id: Int?
        let title: String?
        let name: String?
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let voteAverage: Double?
        let releaseDate: String?
        let firstAirDate: String?
        let runtime: Int?
        let genres: [Genre]?
        let credits: Credits?
        let seasons: [SeasonResponse]?
    }
    private struct Genre: Codable { let name: String? }
    private struct Credits: Codable { let cast: [CastResponse]? }
    private struct CastResponse: Codable {
        let name: String?
        let character: String?
        let profilePath: String?
    }
    private struct SeasonResponse: Codable {
        let seasonNumber: Int?
        let name: String?
        let overview: String?
        let posterPath: String?
        let airDate: String?
    }

    private var memory: [String: Info] = [:]
    private var misses: Set<String> = []
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()
    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tmdb", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var enabled: Bool { !Store.shared.tmdbDisabled && !Store.shared.tmdbKey.isEmpty }

    func lookupQuick(_ fileName: String) async -> Info? {
        let title = TitleParser.canonical(fileName)
        guard !title.isEmpty else { return nil }
        return await lookup(title)
    }

    func lookup(_ query: String) async -> Info? {
        guard enabled else { return nil }
        let key = "q:" + query.lowercased()
        if misses.contains(key) { return nil }
        if let cached = memory[key] { return cached }
        if let disk = read(key) { memory[key] = disk; return disk }

        var candidates = [query]
        if let year = TitleParser.year(query) {
            candidates.append(query.replacingOccurrences(of: year, with: ""))
        }
        let words = query.split(separator: " ").map(String.init)
        if words.count > 4 { candidates.append(words.prefix(4).joined(separator: " ")) }

        for candidate in candidates {
            guard let url = URL(string: "https://api.themoviedb.org/3/search/multi?api_key=\(Store.shared.tmdbKey)&query=\(candidate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&include_adult=false&language=en-US&page=1"),
                  let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data),
                  let first = decoded.results?.first else { continue }
            let info = Info(
                id: first.id ?? 0,
                mediaType: first.mediaType ?? "movie",
                title: first.title ?? first.name ?? candidate,
                overview: first.overview ?? "",
                posterPath: first.posterPath,
                backdropPath: first.backdropPath,
                voteAverage: first.voteAverage ?? 0,
                releaseDate: first.releaseDate ?? first.firstAirDate ?? ""
            )
            memory[key] = info
            write(info, key)
            return info
        }
        misses.insert(key)
        return nil
    }

    func enrich(_ info: Info) async -> Info {
        guard enabled && info.id > 0 else { return info }
        let key = "d:\(info.mediaType):\(info.id)"
        if let cached = read(key) { return cached }
        let path = info.mediaType == "tv" ? "tv" : "movie"
        guard let url = URL(string: "https://api.themoviedb.org/3/\(path)/\(info.id)?api_key=\(Store.shared.tmdbKey)&append_to_response=credits&language=en-US"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let detail = try? JSONDecoder().decode(DetailResponse.self, from: data) else { return info }
        var result = info
        result.title = detail.title ?? detail.name ?? info.title
        result.overview = detail.overview ?? info.overview
        result.posterPath = detail.posterPath ?? info.posterPath
        result.backdropPath = detail.backdropPath ?? info.backdropPath
        result.voteAverage = detail.voteAverage ?? info.voteAverage
        result.releaseDate = detail.releaseDate ?? detail.firstAirDate ?? info.releaseDate
        result.runtime = detail.runtime ?? 0
        result.genres = (detail.genres ?? []).compactMap { $0.name }
        result.cast = (detail.credits?.cast ?? []).prefix(20).map {
            CastMember(name: $0.name ?? "", character: $0.character ?? "", profilePath: $0.profilePath)
        }
        result.seasons = (detail.seasons ?? []).map {
            Season(seasonNumber: $0.seasonNumber ?? 0, name: $0.name ?? "", overview: $0.overview ?? "",
                   posterPath: $0.posterPath, airDate: $0.airDate ?? "")
        }
        write(result, key)
        return result
    }

    func imageURL(_ path: String?, size: String = "w500") -> URL? {
        guard let path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    private func fileURL(_ key: String) -> URL {
        cacheDir.appendingPathComponent(key.utf8.md5 + ".json")
    }
    private func read(_ key: String) -> Info? {
        guard let data = try? Data(contentsOf: fileURL(key)),
              let info = try? JSONDecoder().decode(Info.self, from: data) else { return nil }
        return info
    }
    private func write(_ info: Info, _ key: String) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        try? data.write(to: fileURL(key))
    }
}

extension String {
    var md5: String {
        let bytes = Array(self.utf8)
        var digest = [UInt8](repeating: 0, count: 16)
        var length = UInt32(bytes.count) &* 8
        var message = bytes
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        message.append(contentsOf: withUnsafeBytes(of: length.littleEndian) { Array($0) })
        var a: UInt32 = 0x67452301, b: UInt32 = 0xefcdab89, c: UInt32 = 0x98badcfe, d: UInt32 = 0x10325476
        let s: [UInt32] = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21]
        let k: [UInt32] = (0..<64).map { i in UInt32(floor(abs(sin(Double(i + 1))) * 4294967296)) }
        func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
        for offset in stride(from: 0, to: message.count, by: 64) {
            let chunk = Array(message[offset..<(offset + 64)])
            let m = (0..<16).map { i -> UInt32 in
                var v: UInt32 = 0
                for j in 0..<4 { v |= UInt32(chunk[i * 4 + j]) << UInt32(8 * j) }
                return v
            }
            var A = a, B = b, C = c, D = d
            for i in 0..<64 {
                let f: UInt32
                let g: Int
                if i < 16 { f = (B & C) | (~B & D); g = i }
                else if i < 32 { f = (D & B) | (~D & C); g = (5 * i + 1) % 16 }
                else if i < 48 { f = B ^ C ^ D; g = (3 * i + 5) % 16 }
                else { f = C ^ (B | ~D); g = (7 * i) % 16 }
                let temp = D
                D = C; C = B
                B = B &+ rotate(A &+ f &+ k[i] &+ m[g], s[(i / 16) * 4 + (i % 4)])
                A = temp
            }
            a &+= A; b &+= B; c &+= C; d &+= D
        }
        return [a, b, c, d].flatMap { withUnsafeBytes(of: $0.littleEndian) { Array($0) } }
            .map { String(format: "%02x", $0) }.joined()
    }
}
