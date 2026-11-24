import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store
    @StateObject private var model = LibraryViewModel()

    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var heroIndex = 0
    @State private var showChatPicker = false
    @State private var sortMenu = false

    private let timer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    private var items: [VideoItem] {
        var result = td.library
        if !query.isEmpty {
            let q = query.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) || $0.fileName.lowercased().contains(q)
                    || $0.chatTitle.lowercased().contains(q)
            }
        }
        switch filter {
        case .all: break
        case .movies: result = result.filter { !$0.isSeries }
        case .series: result = result.filter { $0.isSeries }
        case .favourites: result = result.filter { store.isFavourite($0) }
        }
        return model.sorted(result, by: store.homeSort)
    }

    private var continueItems: [VideoItem] {
        td.library.filter { item in
            let key = WatchProgressEntry.key(chatId: item.chatId, messageId: item.messageId)
            return (store.progress[key]?.resumable ?? false) && !store.dismissedContinue.contains(key)
        }
    }

    private var heroItems: [VideoItem] { Array(td.library.prefix(8)) }

    private var hero: VideoItem? {
        heroItems.indices.contains(heroIndex) ? heroItems[heroIndex] : nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if let hero { heroCard(hero) }
                if !continueItems.isEmpty {
                    continueRow
                }
                controls
                if store.homeGrouped {
                    groupedGrid
                } else {
                    plainGrid
                }
                if items.isEmpty && !td.busy {
                    emptyState
                }
            }
            .padding(.bottom, 30)
        }
        .navigationTitle("TGTV")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(HomeSort.allCases) { sort in
                        Button {
                            store.homeSort = sort
                        } label: {
                            Label(sort.label, systemImage: store.homeSort == sort ? "checkmark" : "")
                        }
                    }
                    Divider()
                    Button { store.homeGrouped.toggle() } label: {
                        Label(store.homeGrouped ? "Ungroup chats" : "Group by chat",
                              systemImage: "rectangle.grid.2x2")
                    }
                    Button { store.homeGridView.toggle() } label: {
                        Label(store.homeGridView ? "List view" : "Poster grid",
                              systemImage: store.homeGridView ? "list.bullet" : "square.grid.3x3")
                    }
                    Divider()
                    Button { showChatPicker = true } label: {
                        Label("Library chats", systemImage: "bubble.left.and.bubble.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showChatPicker) { NavigationStack { ChatSelectionView(settingsMode: true) } }
        .onReceive(timer) { _ in
            if !heroItems.isEmpty { heroIndex = (heroIndex + 1) % heroItems.count }
        }
        .task {
            if td.library.isEmpty { await td.loadSelectedLibrary() }
            await model.warm(td.library)
        }
        .refreshable {
            await td.loadSelectedLibrary()
            await model.warm(td.library)
        }
    }

    private func heroCard(_ item: VideoItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: model.backdrop(for: item) ?? model.poster(for: item), placeholder: "film")
                .frame(height: 300)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.info(for: item)?.title ?? (item.title.isEmpty ? item.fileName : item.title))
                    .font(.title.bold())
                    .lineLimit(2)
                HStack(spacing: 10) {
                    if let info = model.info(for: item), info.voteAverage > 0 {
                        Label(String(format: "%.1f", info.voteAverage), systemImage: "star.fill")
                    }
                    if let year = TitleParser.year(item.fileName) { Text(year) }
                    Text(item.prettyDuration)
                    Text(item.chatTitle).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                HStack {
                    NavigationLink("Play") { PlayerView(item: item) }
                        .buttonStyle(.borderedProminent).tint(.red)
                    NavigationLink("Details") { DetailsView(item: item) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
            HStack(spacing: 5) {
                ForEach(heroItems.indices, id: \.self) { i in
                    Capsule().fill(i == heroIndex ? .red : .white.opacity(0.4))
                        .frame(width: i == heroIndex ? 16 : 5, height: 5)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(height: 300)
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private var continueRow: some View {
        VStack(alignment: .leading) {
            Text("Continue Watching").font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueItems) { item in
                        let key = WatchProgressEntry.key(chatId: item.chatId, messageId: item.messageId)
                        NavigationLink { PlayerView(item: item) } label: {
                            VStack(alignment: .leading) {
                                ZStack(alignment: .bottom) {
                                    RemoteImage(url: model.backdrop(for: item) ?? model.poster(for: item), placeholder: "play")
                                        .frame(width: 220, height: 124).clipped().cornerRadius(10)
                                    if let entry = store.progress[key] {
                                        ProgressBar(fraction: entry.d > 0 ? Double(entry.p) / Double(entry.d) : 0)
                                            .padding(.horizontal, 8).padding(.bottom, 8)
                                    }
                                }
                                HStack {
                                    Text(item.title.isEmpty ? item.fileName : item.title)
                                        .font(.caption).lineLimit(1)
                                    Spacer()
                                    Button {
                                        store.dismissContinue(key)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(width: 220)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            TextField("Search your library", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LibraryFilter.allCases) { f in
                        Chip(title: f.label, selected: filter == f) { filter = f }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var plainGrid: some View {
        if store.homeGridView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                ForEach(items) { item in
                    NavigationLink { DetailsView(item: item) } label: {
                        VideoCard(item: item, posterURL: model.poster(for: item))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    NavigationLink { DetailsView(item: item) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: model.poster(for: item), placeholder: "film")
                                .frame(width: 52, height: 78).clipped().cornerRadius(6)
                            VStack(alignment: .leading) {
                                Text(item.title.isEmpty ? item.fileName : item.title).font(.subheadline.weight(.semibold))
                                Text(item.chatTitle).font(.caption).foregroundStyle(.secondary)
                                Text(item.prettySize).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var groupedGrid: some View {
        let grouped = Dictionary(grouping: items) { $0.chatTitle }
        ForEach(grouped.keys.sorted(), id: \.self) { chat in
            VStack(alignment: .leading, spacing: 10) {
                Text(chat).font(.headline).padding(.horizontal)
                let videos = grouped[chat] ?? []
                let series = SeriesEntry.group(videos)
                let singles = videos.filter { v in !series.contains(where: { $0.items.contains(v) }) }
                if !series.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(series) { entry in
                                NavigationLink { SeriesDetailsView(entry: entry) } label: {
                                    VStack {
                                        RemoteImage(url: model.poster(for: entry.items[0]), placeholder: "tv")
                                            .frame(width: 110, height: 165).clipped().cornerRadius(8)
                                        Text(entry.title).font(.caption).lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 14) {
                    ForEach(singles) { item in
                        NavigationLink { DetailsView(item: item) } label: {
                            VideoCard(item: item, posterURL: model.poster(for: item))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "popcorn")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No videos yet").font(.headline)
            Text("Pick the Telegram chats that contain your movies, or drop a few files into Saved Messages.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose library chats") { showChatPicker = true }
                .buttonStyle(.bordered).tint(.red)
        }
        .padding(40)
    }
}
