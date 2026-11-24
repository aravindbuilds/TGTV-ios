import SwiftUI

struct FavouritesView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store
    @StateObject private var model = LibraryViewModel()

    @State private var activeList = "All"
    @State private var newListName = ""
    @State private var showNewList = false

    private var items: [VideoItem] {
        switch activeList {
        case "All": return Array(Set(store.favouriteLists.flatMap { $0.items })).sorted { $0.messageId > $1.messageId }
        default: return store.favouriteLists.first { $0.name == activeList }?.items ?? []
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Chip(title: "All", selected: activeList == "All") { activeList = "All" }
                        ForEach(store.favouriteLists) { list in
                            Chip(title: list.name, selected: activeList == list.name) { activeList = list.name }
                        }
                        Button {
                            showNewList = true
                        } label: {
                            Label("New", systemImage: "plus")
                                .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.white.opacity(0.1), in: Capsule()).foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal)
                }

                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart").font(.system(size: 44)).foregroundStyle(.secondary)
                        Text("Nothing saved yet").font(.headline)
                        Text("Tap the heart on any title, or long-press it to pick a named list.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                        ForEach(items) { item in
                            NavigationLink { DetailsView(item: item) } label: {
                                VideoCard(item: item, posterURL: model.poster(for: item))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Favourites")
        .task { await model.warm(items) }
        .alert("New list", isPresented: $showNewList) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Add") {
                store.newList(newListName)
                activeList = newListName
                newListName = ""
                Task { await CloudBackup.shared.request() }
            }
        }
        .toolbar {
            if activeList != "All" {
                Button {
                    store.deleteList(activeList)
                    activeList = "All"
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}
