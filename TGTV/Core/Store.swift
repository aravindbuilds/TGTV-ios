import Foundation
import Combine

/// Mirrors the SharedPreferences layout of the Android client (including the legacy
/// `tgvideotv` suite used by the TV app) so settings survive across platforms/devices.
final class Store: ObservableObject {
    static let shared = Store()

    private let defaults = UserDefaults.standard
    private let legacy = UserDefaults(suiteName: "tgvideotv")!
    private let chats = UserDefaults(suiteName: "chat_selection")!
    private let requests = UserDefaults(suiteName: "requests")!

    private init() {}

    func string(_ key: String, _ fallback: String = "") -> String {
        defaults.string(forKey: key) ?? fallback
    }
    func set(_ value: String, _ key: String) { defaults.set(value, forKey: key); objectWillChange.send() }
    func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
    func set(_ value: Bool, _ key: String) { defaults.set(value, forKey: key); objectWillChange.send() }
    func int(_ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }
    func set(_ value: Int, _ key: String) { defaults.set(value, forKey: key); objectWillChange.send() }

    // MARK: - Credentials
    var apiId: Int64 {
        get { Int64(defaults.string(forKey: "api_id") ?? "") ?? GeneratedSecrets.apiId }
        set { set(String(newValue), "api_id") }
    }
    var apiHash: String {
        get { string("api_hash", GeneratedSecrets.apiHash) }
        set { set(newValue, "api_hash") }
    }
    var phone: String { get { string("phone") } set { set(newValue, "phone") } }
    var dialCode: String { get { string("dial_code", CountryCodes.defaultDial) } set { set(newValue, "dial_code") } }
    var botToken: String { get { string("bot_token") } set { set(newValue, "bot_token") } }
    var hasAPI: Bool { (apiId > 0 && apiHash.count >= 30) || !botToken.isEmpty }

    var tmdbKey: String {
        get { string("tmdb_key", GeneratedSecrets.tmdbKey) }
        set { set(newValue, "tmdb_key") }
    }
    var tmdbDisabled: Bool { get { bool("tmdb_disabled", false) } set { set(newValue, "tmdb_disabled") } }
    var tmdbEdited: Bool { get { bool("tmdb_edited", false) } set { set(newValue, "tmdb_edited") } }
    var openSubtitlesKey: String {
        get { string("opensubtitles_key", GeneratedSecrets.openSubtitlesKey) }
        set { set(newValue, "opensubtitles_key") }
    }
    var subsEnabled: Bool { get { bool("subs_on", true) } set { set(newValue, "subs_on") } }
    var subsLanguages: String { get { string("subs_languages", "en") } set { set(newValue, "subs_languages") } }
    var subsTextSize: Int { get { int("subs_text_size", 1) } set { set(newValue, "subs_text_size") } }
    var subsEdited: Bool { get { bool("subs_edited", false) } set { set(newValue, "subs_edited") } }
    var syncEnabled: Bool { get { bool("sync_on", true) } set { set(newValue, "sync_on") } }
    var betaUpdates: Bool { get { bool("beta_updates", false) } set { set(newValue, "beta_updates") } }
    var cacheRetentionMinutes: Int { get { int("cache_retention_minutes", 60) } set { set(newValue, "cache_retention_minutes") } }

    var homeSort: HomeSort {
        get { HomeSort(rawValue: string("home_sort", "newest")) ?? .newest }
        set { set(newValue.rawValue, "home_sort") }
    }
    var homeGrouped: Bool { get { bool("home_group", true) } set { set(newValue, "home_group") } }
    var homeGridView: Bool { get { bool("home_view", true) } set { set(newValue, "home_view") } }
    var sessionIsBot: Bool { get { bool("session_is_bot", false) } set { set(newValue, "session_is_bot") } }

    var backupAt: Int64 {
        get { Int64(string("cloud_backup_at")) ?? 0 }
        set { set(String(newValue), "cloud_backup_at") }
    }

    // MARK: - Watch progress
    private(set) lazy var progress: [String: WatchProgressEntry] = decode("watch_progress", defaults) ?? [:]
    func save(progress entry: WatchProgressEntry, key: String) {
        progress[key] = entry
        defaults.set(encode(progress), forKey: "watch_progress")
        objectWillChange.send()
    }
    func merge(progress incoming: [String: WatchProgressEntry]) {
        for (key, entry) in incoming {
            if let existing = progress[key], existing.u > entry.u { continue }
            progress[key] = entry
        }
        defaults.set(encode(progress), forKey: "watch_progress")
        objectWillChange.send()
    }
    var dismissedContinue: Set<String> {
        get { Set(decode("watch_progress_dismissed", defaults) ?? [String]()) }
        set { defaults.set(encode(Array(newValue)), forKey: "watch_progress_dismissed"); objectWillChange.send() }
    }
    func dismissContinue(_ key: String) {
        var set = dismissedContinue
        set.insert(key)
        dismissedContinue = set
    }

    // MARK: - Favourites (legacy suite shared with TV app)
    var favouriteLists: [FavouriteList] {
        get { decode("watchlist_lists", legacy) ?? decode("watchlist_items", legacy).map { [FavouriteList(name: "Favourites", items: $0)] } ?? [] }
        set { legacy.set(encode(newValue), forKey: "watchlist_lists"); objectWillChange.send() }
    }
    func toggleFavourite(_ item: VideoItem, list: String = "Favourites") {
        var lists = favouriteLists
        let idx = lists.firstIndex { $0.name == list }
        if idx == nil { lists.append(FavouriteList(name: list, items: [])) }
        let at = idx ?? lists.count - 1
        if let i = lists[at].items.firstIndex(where: { $0.id == item.id }) {
            lists[at].items.remove(at: i)
        } else {
            lists[at].items.append(item)
        }
        favouriteLists = lists
    }
    func isFavourite(_ item: VideoItem) -> Bool { favouriteLists.contains { $0.items.contains(item) } }
    func newList(_ name: String) {
        guard !name.isEmpty, !favouriteLists.contains(where: { $0.name == name }) else { return }
        favouriteLists.append(FavouriteList(name: name, items: []))
    }
    func renameList(_ old: String, to new: String) {
        var lists = favouriteLists
        if let i = lists.firstIndex(where: { $0.name == old }) { lists[i].name = new; favouriteLists = lists }
    }
    func deleteList(_ name: String) { favouriteLists.removeAll { $0.name == name } }

    // MARK: - Chat selection
    var selectedChatIds: Set<Int64> {
        get { Set((chats.array(forKey: "chat_ids") as? [Int64] ?? [])) }
        set { chats.set(Array(newValue), forKey: "chat_ids"); objectWillChange.send() }
    }
    var chatsConfigured: Bool {
        get { chats.bool(forKey: "configured") }
        set { chats.set(newValue, forKey: "configured"); objectWillChange.send() }
    }

    // MARK: - Library snapshot
    var librarySnapshot: [VideoItem] {
        get { decode("library_snapshot", defaults) ?? [] }
        set { defaults.set(encode(newValue), forKey: "library_snapshot"); objectWillChange.send() }
    }

    // MARK: - Movie requests
    var requestBot: String { get { requests.string(forKey: "bot_handle") ?? "SearchMoviesBot" } set { requests.set(newValue, forKey: "bot_handle") } }

    func clearSession() {
        for key in ["api_id", "api_hash", "phone", "bot_token", "session_is_bot"] { defaults.removeObject(forKey: key) }
        chats.removeObject(forKey: "chat_ids")
        chats.set(false, forKey: "configured")
        librarySnapshot = []
        objectWillChange.send()
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
    private func decode<T: Decodable>(_ key: String, _ suite: UserDefaults) -> T? {
        guard let s = suite.string(forKey: key), let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
