import Foundation
import Combine

/// Holds TMDB metadata and poster URLs for the library grid, mirroring the
/// in-memory `InfoCache` / `PosterCache` of the Android HomeActivity.
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var infos: [String: TMDBClient.Info] = [:]
    @Published private(set) var posters: [String: URL] = [:]
    private var requested: Set<String> = []

    func warm(_ items: [VideoItem]) async {
        guard TMDBClient.shared.enabled else { return }
        for item in items.prefix(48) {
            guard !requested.contains(item.id) else { continue }
            requested.insert(item.id)
            let info = await TMDBClient.shared.lookupQuick(item.fileName)
            if let info {
                infos[item.id] = info
                posters[item.id] = TMDBClient.shared.imageURL(info.posterPath, size: "w500")
            } else {
                posters.removeValue(forKey: item.id)
            }
        }
    }

    func info(for item: VideoItem) -> TMDBClient.Info? { infos[item.id] }
    func poster(for item: VideoItem) -> URL? { posters[item.id] }
    func backdrop(for item: VideoItem) -> URL? {
        guard let info = infos[item.id] else { return nil }
        return TMDBClient.shared.imageURL(info.backdropPath, size: "w1280")
            ?? TMDBClient.shared.imageURL(info.posterPath, size: "w780")
    }

    func sorted(_ items: [VideoItem], by sort: HomeSort) -> [VideoItem] {
        switch sort {
        case .newest: return items.sorted { $0.messageId > $1.messageId }
        case .oldest: return items.sorted { $0.messageId < $1.messageId }
        case .title: return items.sorted { ($0.title.isEmpty ? $0.fileName : $0.title) < ($1.title.isEmpty ? $1.fileName : $1.title) }
        case .size: return items.sorted { $0.fileSize > $1.fileSize }
        }
    }
}
