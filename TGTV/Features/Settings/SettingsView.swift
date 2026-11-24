import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var backup: CloudBackup

    @State private var tmdbKey = ""
    @State private var subsKey = ""
    @State private var languages = ""
    @State private var apiId = ""
    @State private var apiHash = ""
    @State private var showSignOut = false
    @State private var showCacheCleared = false

    var body: some View {
        Form {
            Section("Session") {
                HStack {
                    Text("Signed in as")
                    Spacer()
                    Text(td.me.map { "\($0.firstName) \($0.lastName)" } ?? (td.isBot ? "Bot" : "User"))
                        .foregroundStyle(.secondary)
                }
                NavigationLink("Library chats") { ChatSelectionView(settingsMode: true) }
                NavigationLink("Movie requests") { RequestsView() }
                Button("Sign out", role: .destructive) { showSignOut = true }
            }

            Section("Metadata") {
                Toggle("TMDB artwork", isOn: Binding(
                    get: { !store.tmdbDisabled },
                    set: { store.tmdbDisabled = !$0; store.tmdbEdited = true }
                ))
                SecureField("TMDB v3 key", text: $tmdbKey)
                    .onSubmit { store.tmdbKey = tmdbKey; store.tmdbEdited = true }
                Button("Save TMDB key") { store.tmdbKey = tmdbKey; store.tmdbEdited = true }
            }

            Section("Subtitles") {
                Toggle("Subtitles on", isOn: Binding(
                    get: { store.subsEnabled },
                    set: { store.subsEnabled = $0; store.subsEdited = true }
                ))
                TextField("Languages (en,hi)", text: $languages)
                    .onSubmit { store.subsLanguages = languages; store.subsEdited = true }
                SecureField("OpenSubtitles API key", text: $subsKey)
                    .onSubmit { store.openSubtitlesKey = subsKey; store.subsEdited = true }
                Picker("Text size", selection: Binding(
                    get: { store.subsTextSize },
                    set: { store.subsTextSize = $0; store.subsEdited = true }
                )) {
                    Text("Small").tag(0); Text("Medium").tag(1); Text("Large").tag(2)
                }
            }

            Section("Library") {
                Picker("Sort", selection: $store.homeSort) {
                    ForEach(HomeSort.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Group by chat", isOn: $store.homeGrouped)
                Toggle("Poster grid", isOn: $store.homeGridView)
                Picker("Cache retention", selection: $store.cacheRetentionMinutes) {
                    Text("Off").tag(0); Text("15 min").tag(15); Text("1 hour").tag(60)
                    Text("6 hours").tag(360); Text("24 hours").tag(1440); Text("Forever").tag(-1)
                }
                Button("Clear caches") {
                    clearCaches()
                    showCacheCleared = true
                }
            }

            Section("Sync & backup") {
                Toggle("Two-way sync", isOn: $store.syncEnabled)
                Button("Backup now") { Task { await backup.backup(force: true) } }
                Button("Restore now") { Task { await backup.restore(force: true) } }
                HStack {
                    Text("Last backup")
                    Spacer()
                    Text(store.backupAt > 0 ? Date(timeIntervalSince1970: Double(store.backupAt) / 1000).formatted() : "Never")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !backup.lastResult.isEmpty {
                    Text(backup.lastResult).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Telegram API") {
                TextField("API ID", text: $apiId).keyboardType(.numberPad)
                SecureField("API hash", text: $apiHash)
                Button("Save credentials") {
                    store.apiId = Int64(apiId) ?? store.apiId
                    store.apiHash = apiHash
                }
                Text("Stored locally. Requires signing out and back in to take effect.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("About") {
                HStack { Text("Version"); Spacer(); Text("1.0 (1)").foregroundStyle(.secondary) }
                HStack { Text("Bundle"); Spacer(); Text("com.tgtv.iphone").font(.caption).foregroundStyle(.secondary) }
                Link("Source on GitHub", destination: URL(string: "https://github.com/aravindbuilds/TGTV-ios")!)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            tmdbKey = store.tmdbKey
            subsKey = store.openSubtitlesKey
            languages = store.subsLanguages
            apiId = store.apiId > 0 ? String(store.apiId) : ""
            apiHash = store.apiHash
        }
        .confirmationDialog("Sign out of Telegram?", isPresented: $showSignOut) {
            Button("Sign out", role: .destructive) {
                Task { await td.signOut(); store.chatsConfigured = false }
            }
        }
        .alert("Caches cleared", isPresented: $showCacheCleared) {
            Button("OK", role: .cancel) {}
        }
    }

    private func clearCaches() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for name in ["tmdb", "details-img", "thumbs", "posters"] {
            try? fm.removeItem(at: support.appendingPathComponent(name))
        }
        let tmp = fm.temporaryDirectory.appendingPathComponent("tgtv-subs")
        try? fm.removeItem(at: tmp)
    }
}
