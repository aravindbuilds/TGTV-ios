import SwiftUI

struct DetailsView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store
    let item: VideoItem

    @State private var info: TMDBClient.Info?
    @State private var expanded = false
    @State private var sharePath: String?

    private var progress: WatchProgressEntry? {
        store.progress[WatchProgressEntry.key(chatId: item.chatId, messageId: item.messageId)]
    }

    private var versions: [VideoItem] {
        let title = TitleParser.canonical(item.title.isEmpty ? item.fileName : item.title)
        return td.library.filter {
            TitleParser.canonical($0.title.isEmpty ? $0.fileName : $0.title) == title
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: TMDBClient.shared.imageURL(info?.backdropPath, size: "w1280")
                                ?? TMDBClient.shared.imageURL(info?.posterPath, size: "w780"),
                                placeholder: "film")
                        .frame(height: 260)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                }
                .cornerRadius(12)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text(info?.title ?? (item.title.isEmpty ? item.fileName : item.title))
                        .font(.title.bold())
                    HStack(spacing: 12) {
                        if let rating = info?.voteAverage, rating > 0 {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill").foregroundStyle(.yellow)
                        }
                        if let year = TitleParser.year(item.fileName) { Text(year) }
                        if let runtime = info?.runtime, runtime > 0 { Text("\(runtime) min") }
                        else if item.durationSeconds > 0 { Text(item.prettyDuration) }
                        Text(item.prettySize)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let genres = info?.genres, !genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(genres, id: \.self) { genre in
                                    Text(genre).font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.white.opacity(0.1), in: Capsule())
                                }
                            }
                        }
                    }

                    Text(info?.overview ?? item.fileName)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(expanded ? nil : 4)
                    Button(expanded ? "Read Less" : "Read More") { expanded.toggle() }
                        .font(.caption).foregroundStyle(.red)
                }
                .padding(.horizontal)

                if let cast = info?.cast, !cast.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Cast").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(cast, id: \.name) { member in
                                    VStack {
                                        RemoteImage(url: TMDBClient.shared.imageURL(member.profilePath, size: "w185"),
                                                    placeholder: "person")
                                            .frame(width: 66, height: 66).clipShape(Circle())
                                        Text(member.name).font(.caption2).lineLimit(2)
                                    }
                                    .frame(width: 70)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    NavigationLink {
                        PlayerView(item: item, startAt: progress?.p)
                    } label: {
                        Label(progress?.resumable ?? false ? "Resume" : "Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.red)

                    Button {
                        Task {
                            if let path = await td.localPath(for: item.fileId) { sharePath = path }
                        }
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.toggleFavourite(item)
                        Task { await CloudBackup.shared.request() }
                    } label: {
                        Image(systemName: store.isFavourite(item) ? "heart.fill" : "heart")
                            .foregroundStyle(store.isFavourite(item) ? .red : .white)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                if versions.count > 1 {
                    VStack(alignment: .leading) {
                        Text("Versions (\(versions.count))").font(.headline).padding(.horizontal)
                        ForEach(versions) { version in
                            NavigationLink { DetailsView(item: version) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(version.fileName).font(.caption).lineLimit(1)
                                        Text("\(version.prettySize) · \(version.chatTitle)")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let found = await TMDBClient.shared.lookupQuick(item.fileName) else { return }
            info = await TMDBClient.shared.enrich(found)
        }
        .sheet(item: Binding(get: { sharePath.map { ShareItem(path: $0) } }, set: { _ in sharePath = nil })) { share in
            ShareSheet(items: [URL(fileURLWithPath: share.path)])
        }
    }
}

struct ShareItem: Identifiable {
    let path: String
    var id: String { path }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
