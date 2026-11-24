import Foundation

/// Implements the cross-device `#TGTVBackup` document shared by the Android phone
/// app and the TV app. Restore is additive: it never deletes local entries.
@MainActor
final class CloudBackup: ObservableObject {
    static let shared = CloudBackup()

    static let caption = "#TGTVBackup"
    private static let autoInterval: Int64 = 30 * 60 * 1000

    @Published var lastResult: String = ""
    @Published var working = false

    private var lastApplied: Int64 {
        get { Int64(UserDefaults.standard.string(forKey: "cloud_backup_applied_at") ?? "") ?? 0 }
        set { UserDefaults.standard.set(String(newValue), forKey: "cloud_backup_applied_at") }
    }

    func request(force: Bool = false) async {
        let store = Store.shared
        guard store.syncEnabled else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if !force && now - store.backupAt < Self.autoInterval { return }
        await backup(now: now)
    }

    func backup(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async {
        guard let saved = await TDLibService.shared.savedMessagesChatId,
              !TDLibService.shared.isBot else { return }
        working = true
        defer { working = false }

        let store = Store.shared
        let lists = store.favouriteLists
        let doc = BackupDocument(
            at: now,
            favLists: lists,
            watchlist: Array(Set(lists.flatMap { $0.items })),
            progress: store.progress,
            pinnedChats: store.selectedChatIds.map(String.init).sorted(),
            subsEnabled: store.subsEnabled,
            subsTextSize: store.subsTextSize,
            subsLanguages: store.subsLanguages,
            tmdbDisabled: store.tmdbDisabled
        )
        guard let data = try? JSONEncoder().encode(doc) else { return }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("tgtv-backup.json").path
        try? data.write(to: URL(fileURLWithPath: path))

        let sentId = await TDLibService.shared.sendDocument(path: path, caption: Self.caption, chatId: saved)
        if sentId != nil {
            let messages = await TDLibService.shared.searchMessages(chatId: saved, query: Self.caption, limit: 20)
            let old = messages.filter { $0.id != sentId }.map(\.id)
            if !old.isEmpty { await TDLibService.shared.deleteMessages(chatId: saved, ids: old) }
            store.backupAt = now
            lastResult = "Backed up \(lists.count) list(s)"
        } else {
            lastResult = "Backup failed: \(TDLibService.shared.lastError ?? "unknown")"
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    func restore(force: Bool = false) async {
        guard let saved = await TDLibService.shared.savedMessagesChatId,
              !TDLibService.shared.isBot else { return }
        let store = Store.shared
        if !force && !store.syncEnabled { return }
        working = true
        defer { working = false }

        let messages = await TDLibService.shared.searchMessages(chatId: saved, query: Self.caption, limit: 20)
        guard let newest = messages.max(by: { $0.date < $1.date }),
              Int64(newest.date) * 1000 > lastApplied,
              let fileId = await TDLibService.shared.messageFileId(newest),
              let path = await TDLibService.shared.localPath(for: fileId),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let doc = try? JSONDecoder().decode(BackupDocument.self, from: data) else {
            lastResult = "No newer backup found"
            return
        }

        store.merge(progress: doc.progress)
        var pins = store.selectedChatIds
        for value in doc.pinnedChats { if let id = Int64(value) { pins.insert(id) } }
        if !pins.isEmpty { store.selectedChatIds = pins }

        var lists = store.favouriteLists
        for list in doc.favLists {
            if let index = lists.firstIndex(where: { $0.name == list.name }) {
                var items = lists[index].items
                for item in list.items where !items.contains(item) { items.append(item) }
                lists[index].items = items
            } else {
                lists.append(list)
            }
        }
        let flat = doc.watchlist
        if !flat.isEmpty, let index = lists.firstIndex(where: { $0.name == "Favourites" }) {
            var items = lists[index].items
            for item in flat where !items.contains(item) { items.append(item) }
            lists[index].items = items
        }
        store.favouriteLists = lists

        if !store.subsEdited {
            store.subsEnabled = doc.subsEnabled
            store.subsTextSize = doc.subsTextSize
            store.subsLanguages = doc.subsLanguages
        }
        if !store.tmdbEdited { store.tmdbDisabled = doc.tmdbDisabled }

        lastApplied = Int64(newest.date) * 1000
        lastResult = "Restored backup from \(Date(timeIntervalSince1970: Double(newest.date)))"
    }
}

/// Cross-device watch progress carried in a private Saved Messages text reply.
@MainActor
final class ProgressSync: ObservableObject {
    static let shared = ProgressSync()
    static let marker = "TGTV ▶"

    func publish(item: VideoItem, entry: WatchProgressEntry) async {
        guard let saved = await TDLibService.shared.savedMessagesChatId,
              !TDLibService.shared.isBot else { return }
        let text = "\(Self.marker) \(entry.p) \(entry.d)"
        if let id = await TDLibService.shared.sendText(chatId: saved, text: text) {
            await TDLibService.shared.editText(chatId: saved, messageId: id, text: text)
        }
    }

    func reconcile() async {
        guard let saved = await TDLibService.shared.savedMessagesChatId else { return }
        let messages = await TDLibService.shared.searchMessages(chatId: saved, query: Self.marker, limit: 30)
        var incoming: [String: WatchProgressEntry] = [:]
        for message in messages {
            guard case .messageText(let value) = message.content else { continue }
            let parts = value.text.text.split(separator: " ")
            // Wire format: "TGTV ▶ <positionMs> <durationMs>"
            guard parts.count == 4, parts[0] == "TGTV", parts[1] == "▶",
                  let p = Int64(parts[2]), let d = Int64(parts[3]) else { continue }
            let key = "sync:\(message.id)"
            incoming[key] = WatchProgressEntry(p: p, d: d, u: Int64(message.date) * 1000)
        }
        Store.shared.merge(progress: incoming)
    }
}
