import SwiftUI

struct SeriesDetailsView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store
    let entry: SeriesEntry

    @State private var activeSeason: Int = 0
    @State private var info: TMDBClient.Info?
    @State private var sharePath: String?

    private var seasons: [Int] {
        Array(Set(entry.items.compactMap { TitleParser.seasonEpisode($0.fileName)?.season })).sorted()
    }
    private var episodes: [VideoItem] {
        entry.items.filter { TitleParser.seasonEpisode($0.fileName)?.season == activeSeason }
            .sorted { (TitleParser.seasonEpisode($0.fileName)?.episode ?? 0) < (TitleParser.seasonEpisode($1.fileName)?.episode ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RemoteImage(url: TMDBClient.shared.imageURL(info?.backdropPath, size: "w1280")
                            ?? TMDBClient.shared.imageURL(info?.posterPath, size: "w780"), placeholder: "tv")
                    .frame(height: 200).clipped().cornerRadius(12).padding(.horizontal)

                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(info?.title ?? entry.title).font(.title2.bold())
                        Text("\(seasons.count) season\(seasons.count == 1 ? "" : "s") · \(entry.items.count) episodes")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if let first = entry.items.first {
                            store.toggleFavourite(first)
                            Task { await CloudBackup.shared.request() }
                        }
                    } label: {
                        Image(systemName: "heart").foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)

                if let overview = info?.overview, !overview.isEmpty {
                    Text(overview).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(seasons, id: \.self) { season in
                            Button("Season \(season)") { activeSeason = season }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(activeSeason == season ? Color.red : Color.white.opacity(0.1), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal)
                }

                LazyVStack(spacing: 0) {
                    ForEach(episodes) { item in
                        let ep = TitleParser.seasonEpisode(item.fileName)
                        let key = WatchProgressEntry.key(chatId: item.chatId, messageId: item.messageId)
                        HStack(spacing: 12) {
                            NavigationLink { PlayerView(item: item, startAt: store.progress[key]?.p) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RemoteImage(url: TMDBClient.shared.imageURL(info?.posterPath, size: "w300"), placeholder: "tv")
                                            .frame(width: 86, height: 52).clipped().cornerRadius(6)
                                        Image(systemName: "play.circle.fill").font(.title2)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("S\(ep?.season ?? 0) E\(ep?.episode ?? 0)  \(item.fileName)")
                                            .font(.subheadline).lineLimit(1)
                                        Text(item.prettySize).font(.caption2).foregroundStyle(.secondary)
                                        if let entry = store.progress[key], entry.resumable {
                                            ProgressBar(fraction: entry.d > 0 ? Double(entry.p) / Double(entry.d) : 0)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            Button {
                                Task { if let path = await td.localPath(for: item.fileId) { sharePath = path } }
                            } label: {
                                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { activeSeason = seasons.last ?? 0 }
        .task {
            guard let found = await TMDBClient.shared.lookupQuick(entry.title) else { return }
            info = await TMDBClient.shared.enrich(found)
        }
        .sheet(item: Binding(get: { sharePath.map { ShareItem(path: $0) } }, set: { _ in sharePath = nil })) { share in
            ShareSheet(items: [URL(fileURLWithPath: share.path)])
        }
    }
}
