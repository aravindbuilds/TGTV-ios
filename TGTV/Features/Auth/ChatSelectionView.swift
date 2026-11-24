import SwiftUI

struct ChatSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store

    /// When opened from Settings the screen only saves the selection and closes.
    var settingsMode = false

    @State private var query = ""
    @State private var selection: Set<Int64> = []

    private var filtered: [TDLibService.ChatInfo] {
        let q = query.lowercased()
        return td.chats.filter { q.isEmpty || $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Pick the chats that hold your movies")
                .font(.headline)
                .padding(.top, 12)
            Text("TGTV scans these Telegram chats and builds your library. Saved Messages is recommended — it keeps your collection private.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            TextField("Search chats", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()

            List {
                ForEach(filtered) { chat in
                    Button {
                        if selection.contains(chat.id) { selection.remove(chat.id) }
                        else { selection.insert(chat.id) }
                    } label: {
                        HStack {
                            Image(systemName: chat.isPrivate ? "person.fill" : (chat.isChannel ? "megaphone.fill" : "person.3.fill"))
                                .foregroundStyle(.red)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(chat.title).foregroundStyle(.primary)
                                Text("\(chat.id)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selection.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(chat.id) ? .red : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)

            HStack {
                Text("\(selection.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button(settingsMode ? "Save" : "Continue") {
                    store.selectedChatIds = selection
                    store.chatsConfigured = true
                    Task {
                        await td.loadLibrary(chatIds: selection)
                        await CloudBackup.shared.request()
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(selection.isEmpty)
            }
            .padding()
        }
        .navigationTitle("Library chats")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selection = store.selectedChatIds
            if selection.isEmpty {
                if let saved = td.savedMessagesChatId { selection = [saved] }
                else if let first = td.chats.first(where: { $0.isPrivate }) { selection = [first.id] }
            }
        }
    }
}
