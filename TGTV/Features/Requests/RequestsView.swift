import SwiftUI

/// Movie request wizard. Mirrors the Android `RequestsActivity` flow: pick a bot,
/// search a title, answer the bot's gates, and save arriving files to Saved Messages.
struct RequestsView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store

    private let defaults = ["SearchMoviesBot", "TVSeriesSearchBot", "Spoty_xbot", "Angela2_moviebot"]

    @State private var botHandle = ""
    @State private var query = ""
    @State private var status = ""
    @State private var busy = false
    @State private var history: [String] = []
    @State private var trackedChatId: Int64?

    private var needsUser: Bool { td.isBot }

    var body: some View {
        Form {
            if needsUser {
                Section {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange)
                        Text("Movie requests need a user account. Sign out and log in with a phone number to use this feature.")
                            .font(.caption)
                    }
                }
            }

            Section("Bot") {
                Picker("Bot", selection: $botHandle) {
                    ForEach(defaults, id: \.self) { Text("@\($0)").tag($0) }
                    Text("Custom…").tag("custom")
                }
                if botHandle == "custom" || !defaults.contains(botHandle) {
                    TextField("@username", text: $botHandle)
                }
            }

            Section("Request") {
                TextField("Movie or series name", text: $query)
                Button(busy ? "Working…" : "Ask the bot") {
                    busy = true
                    status = "Contacting @\(botHandle)…"
                    Task {
                        let chat = await td.resolvePublicChat(botHandle)
                        guard let chat else {
                            status = "Could not find that bot."
                            busy = false
                            return
                        }
                        trackedChatId = chat.id
                        _ = await td.sendText(chatId: chat.id, text: query)
                        status = "Waiting for the bot's reply. When the file arrives it will be saved to Saved Messages."
                        history.insert("@\(botHandle): \(query)", at: 0)
                        if history.count > 20 { history = Array(history.prefix(20)) }
                        busy = false
                    }
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(busy || query.isEmpty || needsUser)
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            }

            Section("Watching") {
                if let chatId = trackedChatId {
                    let matches = td.library.filter { $0.chatId == chatId }
                    if matches.isEmpty {
                        Text("No file yet — keep this screen open or come back later.").font(.caption)
                    } else {
                        ForEach(matches) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.fileName).font(.caption).lineLimit(1)
                                    Text(item.prettySize).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Save") {
                                    Task {
                                        await td.forwardToSavedMessages(chatId: item.chatId, messageId: item.messageId)
                                        status = "Saved to Saved Messages."
                                    }
                                }
                                .buttonStyle(.bordered).tint(.red)
                            }
                        }
                    }
                } else {
                    Text("Send a request to start tracking the bot's replies.").font(.caption)
                }
            }

            if !history.isEmpty {
                Section("History") {
                    ForEach(history, id: \.self) { Text($0).font(.caption) }
                }
            }
        }
        .navigationTitle("Movie requests")
        .onAppear { botHandle = store.requestBot }
        .onChange(of: botHandle) { store.requestBot = botHandle }
    }
}
