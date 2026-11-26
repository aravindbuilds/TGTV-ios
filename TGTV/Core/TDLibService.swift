import Foundation
import UIKit
import TDLibKit

/// Thin SwiftUI-facing wrapper around TDLibKit. Mirrors `com.tgtv.mobile.td.TdLib`:
/// a single client, an authorization state machine, live chat/message caches and
/// file helpers. All published state is updated on the main actor.
@MainActor
final class TDLibService: ObservableObject {
    enum AuthPhase: Equatable {
        case idle, waitParameters, waitPhoneNumber, waitCode(String), waitPassword(String)
        case waitRegistration, ready, failed(String)
    }

    struct ChatInfo: Identifiable, Hashable {
        let id: Int64
        let title: String
        let isChannel: Bool
        let isPrivate: Bool
    }

    static let shared = TDLibService()

    @Published var phase: AuthPhase = .idle
    @Published var chats: [ChatInfo] = []
    @Published var library: [VideoItem] = []
    @Published var me: User?
    @Published var lastError: String?
    @Published var busy = false
    @Published var fileDownloads: [Int: Double] = [:]

    private var manager: TDLibClientManager?
    private var client: TDLibClient?
    private var chatObjects: [Int64: Chat] = [:]
    private var configured = false
    private var autoConfigured = false
    private var started = false
    private var receivedAnyUpdate = false
    private var downloadedWindows: Set<String> = []

    var isReady: Bool { if case .ready = phase { return true } else { return false } }
    var savedMessagesChatId: Int64? { me?.id }
    var isBot: Bool { Store.shared.sessionIsBot }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        TGTVLog.write("start() creating TDLib client")
        TGTVLog.write("baked apiId present: \(GeneratedSecrets.apiId > 0), baked hash length: \(GeneratedSecrets.apiHash.count), stored id present: \(Store.shared.apiId > 0), hasAPI: \(Store.shared.hasAPI)")
        do {
            let mgr = TDLibClientManager()
            manager = mgr
            client = mgr.createClient { [weak self] data, _ in
                guard let self else { return }
                do {
                    let update = try tgUpdateDecoder.decode(Update.self, from: data)
                    Task { @MainActor in self.receivedAnyUpdate = true }
                    if case .updateAuthorizationState(let value) = update {
                        let name = String(describing: value.authorizationState)
                        TGTVLog.write("auth state: \(name.prefix(120))")
                    }
                    Task { @MainActor in self.handle(update) }
                } catch {
                    var type = "unknown"
                    if let object = try? JSONSerialization.jsonObject(with: data),
                       let dict = object as? [String: Any],
                       let name = dict["@type"] as? String { type = name }
                    TGTVLog.write("update decode failed (\(type)): \(error)")
                }
            }
            phase = .waitParameters
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self, !self.isReady, !self.receivedAnyUpdate else { return }
                self.phase = .failed("TDLib did not initialize. Check your internet connection and try again.")
                TGTVLog.write("init timeout: no updates received")
            }
        } catch {
            TGTVLog.write("TDLib init failed: \(tgErrorText(error))")
            phase = .failed("Could not start Telegram engine: \(tgErrorText(error))")
        }
    }

    func shutdown() { manager?.closeClients(); manager = nil; client = nil }

    func restart() {
        shutdown()
        started = false
        receivedAnyUpdate = false
        configured = false
        autoConfigured = false
        lastError = nil
        phase = .idle
        start()
    }

    /// Records an error for the UI and the on-device log.
    private func fail(_ error: Swift.Error) {
        let text = tgErrorText(error)
        lastError = text
        TGTVLog.write("error: \(text)")
    }

    // MARK: - Update handling

    private func handle(_ update: Update) {
        switch update {
        case .updateAuthorizationState(let value):
            handleAuth(value.authorizationState)
        case .updateNewChat(let value):
            chatObjects[value.chat.id] = value.chat
            refreshChatList()
        case .updateChatTitle(let value):
            if let index = chats.firstIndex(where: { $0.id == value.chatId }) {
                chats[index] = ChatInfo(id: value.chatId, title: value.title,
                                        isChannel: chats[index].isChannel, isPrivate: chats[index].isPrivate)
            }
        case .updateNewMessage(let value):
            if let item = TDLibService.map(message: value.message, chatTitle: chatObjects[value.message.chatId]?.title ?? "") {
                if !library.contains(item) { library.insert(item, at: 0) }
            }
        case .updateFile(let value):
            let f = value.file
            if f.local.isDownloadingCompleted {
                fileDownloads[f.id] = 1
            } else if f.size > 0 {
                fileDownloads[f.id] = Double(f.local.downloadedSize) / Double(f.size)
            }
        default:
            break
        }
    }

    private func handleAuth(_ state: AuthorizationState) {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            phase = .waitParameters
            if Store.shared.hasAPI && !autoConfigured {
                autoConfigured = true
                let id = Store.shared.apiId
                let hash = Store.shared.apiHash
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.configure(apiId: id, apiHash: hash)
                    } catch {
                        self.fail(error)
                    }
                }
            }
        case .authorizationStateWaitPhoneNumber:
            phase = .waitPhoneNumber
        case .authorizationStateWaitCode(let info):
            phase = .waitCode(info.codeInfo.phoneNumber)
        case .authorizationStateWaitPassword(let info):
            phase = .waitPassword(info.passwordHint)
        case .authorizationStateWaitRegistration:
            phase = .waitRegistration
        case .authorizationStateReady:
            phase = .ready
            Task { await afterLogin() }
        case .authorizationStateClosed, .authorizationStateClosing:
            phase = .idle
        case .authorizationStateLoggingOut:
            phase = .idle
        default:
            break
        }
    }

    private func refreshChatList() {
        chats = chatObjects.values
            .sorted { ($0.positions.first?.order.rawValue ?? 0) > ($1.positions.first?.order.rawValue ?? 0) }
            .map {
                let isPrivate: Bool
                if case .chatTypePrivate = $0.type { isPrivate = true } else { isPrivate = false }
                let isChannel: Bool
                if case .chatTypeSupergroup(let g) = $0.type { isChannel = g.isChannel } else { isChannel = false }
                return ChatInfo(id: $0.id, title: $0.title, isChannel: isChannel, isPrivate: isPrivate)
            }
    }

    // MARK: - Authentication

    func configure(apiId: Int64, apiHash: String) async throws {
        guard let client else { throw TGTVError("Telegram engine is not running yet.") }
        var hash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        // Tolerate quotes pasted in from a properties file or secret.
        if hash.count >= 2, hash.hasPrefix("\""), hash.hasSuffix("\"") {
            hash = String(hash.dropFirst().dropLast())
        }
        guard apiId > 0, hash.count >= 30 else {
            throw TGTVError("API ID (an integer) and API hash (~32 characters) are required.")
        }
        lastError = nil
        Store.shared.apiId = apiId
        Store.shared.apiHash = hash
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let db = paths.appendingPathComponent("tdlib", isDirectory: true).path
        let files = paths.appendingPathComponent("tdlib_files", isDirectory: true).path
        try? FileManager.default.createDirectory(atPath: db, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: files, withIntermediateDirectories: true)
        _ = try await client.setTdlibParameters(
            apiHash: hash,
            apiId: Int(apiId),
            applicationVersion: "1.0",
            databaseDirectory: db,
            databaseEncryptionKey: nil,
            deviceModel: UIDevice.modelName,
            filesDirectory: files,
            systemLanguageCode: Locale.current.language.languageCode?.identifier ?? "en",
            systemVersion: UIDevice.current.systemVersion,
            useChatInfoDatabase: true,
            useFileDatabase: true,
            useMessageDatabase: true,
            useSecretChats: false,
            useTestDc: false
        )
        configured = true
        TGTVLog.write("setTdlibParameters accepted (hash length \(hash.count))")
    }

    func signIn(phone: String) async {
        do {
            busy = true; lastError = nil
            let digits = phone.filter { $0.isNumber }
            guard (6...14).contains(digits.count) else {
                throw TGTVError("Enter the number without the country code (6–14 digits).")
            }
            let full = "+" + digits
            Store.shared.phone = full
            Store.shared.sessionIsBot = false
            _ = try await client?.setAuthenticationPhoneNumber(phoneNumber: full, settings: nil)
        } catch { fail(error) }
        busy = false
    }

    func resendCode() async {
        do {
            busy = true; lastError = nil
            _ = try await client?.resendAuthenticationCode(reason: nil)
        } catch { fail(error) }
        busy = false
    }

    func signIn(botToken: String) async {
        do {
            busy = true; lastError = nil
            guard botToken.contains(":") else { throw TGTVError("Enter a valid BotFather token") }
            Store.shared.botToken = botToken
            Store.shared.sessionIsBot = true
            _ = try await client?.checkAuthenticationBotToken(token: botToken)
        } catch { fail(error) }
        busy = false
    }

    func submit(code: String) async {
        do {
            busy = true; lastError = nil
            _ = try await client?.checkAuthenticationCode(code: code)
        } catch { fail(error) }
        busy = false
    }

    func submit(password: String) async {
        do {
            busy = true; lastError = nil
            _ = try await client?.checkAuthenticationPassword(password: password)
        } catch { fail(error) }
        busy = false
    }

    func register(firstName: String, lastName: String) async {
        do {
            busy = true
            _ = try await client?.registerUser(disableNotification: false, firstName: firstName, lastName: lastName)
        } catch { fail(error) }
        busy = false
    }

    private func afterLogin() async {
        do {
            me = try await client?.getMe()
            try await loadChats()
            await loadSelectedLibrary()
        } catch { fail(error) }
    }

    func signOut() async {
        do { _ = try await client?.logOut() } catch { fail(error) }
        Store.shared.clearSession()
        library = []; chats = []; chatObjects = [:]
    }

    // MARK: - Chats & library

    func loadChats() async throws {
        guard let client else { return }
        let result = try await client.getChats(chatList: nil, limit: 200)
        var objects: [Int64: Chat] = [:]
        for id in result.chatIds {
            if let chat = try? await client.getChat(chatId: id) { objects[id] = chat }
        }
        chatObjects = objects
        refreshChatList()
        try? await client.loadChats(chatList: nil, limit: 200)
    }

    func loadLibrary(chatIds: Set<Int64>) async {
        guard let client else { return }
        busy = true
        var items: [VideoItem] = []
        for chatId in chatIds {
            let title = chatObjects[chatId]?.title ?? ""
            if let messages = try? await client.getChatHistory(chatId: chatId, fromMessageId: 0, limit: 100, offset: 0, onlyLocal: false) {
                for message in messages.messages ?? [] {
                    if let item = TDLibService.map(message: message, chatTitle: title) { items.append(item) }
                }
            } else if let messages = try? await client.searchChatMessages(
                chatId: chatId, filter: .searchMessagesFilterVideo, fromMessageId: 0,
                limit: 100, offset: 0, query: "", senderId: nil, topicId: nil
            ) {
                for message in messages.messages ?? [] {
                    if let item = TDLibService.map(message: message, chatTitle: title) { items.append(item) }
                }
            }
        }
        library = items.sorted { $0.messageId > $1.messageId }
        Store.shared.librarySnapshot = library
        busy = false
    }

    func loadSelectedLibrary() async {
        let ids = Store.shared.selectedChatIds
        if ids.isEmpty {
            if let saved = savedMessagesChatId {
                Store.shared.selectedChatIds = [saved]
                await loadLibrary(chatIds: [saved])
            } else if let first = chats.first(where: { $0.isPrivate }) {
                Store.shared.selectedChatIds = [first.id]
                await loadLibrary(chatIds: [first.id])
            }
        } else {
            await loadLibrary(chatIds: ids)
        }
    }

    func resolvePublicChat(_ username: String) async -> ChatInfo? {
        guard let client else { return nil }
        let handle = username.hasPrefix("@") ? String(username.dropFirst()) : username
        guard let chat = try? await client.searchPublicChat(username: handle) else { return nil }
        chatObjects[chat.id] = chat
        var isPrivate = false, isChannel = false
        if case .chatTypePrivate = chat.type { isPrivate = true }
        if case .chatTypeSupergroup(let group) = chat.type { isChannel = group.isChannel }
        return ChatInfo(id: chat.id, title: chat.title, isChannel: isChannel, isPrivate: isPrivate)
    }

    // MARK: - Files

    /// Downloads a Telegram file into TDLib's file cache and returns the local path.
    /// The Android client streams byte windows instead; AVPlayer requires a local file
    /// (or a local HTTP proxy), so the iOS port downloads before playback.
    @discardableResult
    func localPath(for fileId: Int, expectedSize: Int64 = 0) async -> String? {
        guard let client else { return nil }
        if let cached = try? await client.getFile(fileId: fileId), cached.local.isDownloadingCompleted, !cached.local.path.isEmpty {
            return cached.local.path
        }
        do {
            let file = try await client.downloadFile(fileId: fileId, limit: 0, offset: 0, priority: 32, synchronous: false)
            if file.local.isDownloadingCompleted, !file.local.path.isEmpty { return file.local.path }
        } catch { fail(error) }
        // Poll briefly until TDLib reports completion in updateFile.
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let file = try? await client.getFile(fileId: fileId), file.local.isDownloadingCompleted, !file.local.path.isEmpty {
                return file.local.path
            }
        }
        return nil
    }

    func thumbnailPath(for item: VideoItem) async -> String? {
        guard let id = item.thumbnailFileId else { return nil }
        return await localPath(for: id)
    }

    // MARK: - Progressive streaming support

    func fileSize(for fileId: Int) async -> Int64 {
        guard let client, let file = try? await client.getFile(fileId: fileId) else { return 0 }
        return max(file.size, file.expectedSize)
    }

    /// Ensures the bytes in [start, end] are present in TDLib's partial file.
    /// TDLib completes a `downloadFile(offset:limit:)` request only once that
    /// window is written, so awaiting it is enough before reading the range.
    @discardableResult
    func ensureRange(fileId: Int, start: Int64, end: Int64) async -> Bool {
        guard let client else { return false }
        let aligned = max(0, (start / 1024) * 1024)
        let limit = max(1, end + 1 - aligned)
        let key = "\(fileId):\(aligned):\(limit)"
        if downloadedWindows.contains(key) { return true }

        if let file = try? await client.getFile(fileId: fileId),
           !file.local.path.isEmpty,
           file.local.isDownloadingCompleted || file.local.downloadedPrefixSize >= end + 1 {
            downloadedWindows.insert(key)
            return true
        }

        do {
            let file = try await client.downloadFile(
                fileId: fileId, limit: limit, offset: aligned, priority: 32, synchronous: false
            )
            if !file.local.path.isEmpty {
                downloadedWindows.insert(key)
                return true
            }
        } catch {
            fail(error)
        }
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let file = try? await client.getFile(fileId: fileId), !file.local.path.isEmpty,
               file.local.isDownloadingCompleted || file.local.downloadedPrefixSize >= end + 1 {
                downloadedWindows.insert(key)
                return true
            }
        }
        return false
    }

    func readRange(fileId: Int, offset: Int64, length: Int64) async -> Data? {
        guard let client, let file = try? await client.getFile(fileId: fileId),
              !file.local.path.isEmpty else { return nil }
        guard let handle = FileHandle(forReadingAtPath: file.local.path) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(offset))
        return try? handle.read(upToCount: Int(length))
    }

    // MARK: - Messages (backup / progress sync / requests)

    func sendText(chatId: Int64, text: String) async -> Int64? {
        guard let client else { return nil }
        let content = InputMessageText(clearDraft: true, linkPreviewOptions: nil, text: FormattedText(entities: [], text: text))
        do {
            let message = try await client.sendMessage(
                chatId: chatId, inputMessageContent: .inputMessageText(content),
                options: nil, replyMarkup: nil, replyTo: nil, topicId: nil
            )
            return message.id
        } catch { fail(error); return nil }
    }

    func editText(chatId: Int64, messageId: Int64, text: String) async {
        guard let client else { return }
        let content = InputMessageText(clearDraft: true, linkPreviewOptions: nil, text: FormattedText(entities: [], text: text))
        try? await client.editMessageText(chatId: chatId, inputMessageContent: .inputMessageText(content), messageId: messageId, replyMarkup: nil)
    }

    func deleteMessages(chatId: Int64, ids: [Int64]) async {
        try? await client?.deleteMessages(chatId: chatId, messageIds: ids, revoke: true)
    }

    /// Uploads a local file as a document. Used for `#TGTVBackup` documents so the
    /// wire format stays compatible with the Android and TV clients.
    @discardableResult
    func sendDocument(path: String, caption: String, chatId: Int64) async -> Int64? {
        guard let client else { return nil }
        let document = InputDocument(
            disableContentTypeDetection: true,
            document: .inputFileLocal(InputFileLocal(path: path)),
            thumbnail: nil
        )
        let content = InputMessageDocument(
            caption: FormattedText(entities: [], text: caption),
            document: document
        )
        do {
            let message = try await client.sendMessage(
                chatId: chatId, inputMessageContent: .inputMessageDocument(content),
                options: nil, replyMarkup: nil, replyTo: nil, topicId: nil
            )
            return message.id
        } catch {
            fail(error)
            return nil
        }
    }

    func searchMessages(chatId: Int64, query: String, limit: Int = 20) async -> [Message] {
        guard let client else { return [] }
        do {
            let found = try await client.searchChatMessages(
                chatId: chatId, filter: nil, fromMessageId: 0, limit: limit,
                offset: 0, query: query, senderId: nil, topicId: nil
            )
            return found.messages ?? []
        } catch { return [] }
    }

    func messageFileId(_ message: Message) -> Int? {
        if case .messageDocument(let value) = message.content { return value.document.document.id }
        return nil
    }

    func forwardToSavedMessages(chatId: Int64, messageId: Int64) async {
        guard let saved = savedMessagesChatId else { return }
        _ = try? await client?.forwardMessages(
            chatId: saved, fromChatId: chatId, messageIds: [messageId],
            options: nil, removeCaption: true, sendCopy: true, topicId: nil
        )
    }

    // MARK: - Mapping

    static func map(message: Message, chatTitle: String) -> VideoItem? {
        switch message.content {
        case .messageVideo(let value):
            let v = value.video
            return Self.make(message: message, chatTitle: chatTitle, file: v.video, name: v.fileName,
                             duration: v.duration, mime: v.mimeType, kind: "video", thumb: v.thumbnail?.file.id)
        case .messageVideoNote(let value):
            return Self.make(message: message, chatTitle: chatTitle, file: value.videoNote.video, name: "Video note",
                             duration: value.videoNote.duration, mime: "video/mp4", kind: "note", thumb: value.videoNote.thumbnail?.file.id)
        case .messageAnimation(let value):
            let a = value.animation
            return Self.make(message: message, chatTitle: chatTitle, file: a.animation, name: a.fileName,
                             duration: a.duration, mime: a.mimeType, kind: "animation", thumb: a.thumbnail?.file.id)
        case .messageDocument(let value):
            let d = value.document
            let ext = (d.fileName as NSString).pathExtension.lowercased()
            let videoExts = ["mp4", "mkv", "avi", "mov", "m4v", "webm", "flv", "wmv", "ts"]
            guard d.mimeType.hasPrefix("video/") || videoExts.contains(ext) else { return nil }
            return Self.make(message: message, chatTitle: chatTitle, file: d.document, name: d.fileName,
                             duration: 0, mime: d.mimeType, kind: "document", thumb: d.thumbnail?.file.id)
        default:
            return nil
        }
    }

    private static func make(message: Message, chatTitle: String, file: File, name: String,
                             duration: Int, mime: String, kind: String, thumb: Int?) -> VideoItem {
        VideoItem(
            messageId: message.id, chatId: message.chatId, chatTitle: chatTitle,
            title: TitleParser.canonical(name), fileId: file.id, remoteFileId: file.remote.id,
            fileSize: file.size, durationSeconds: duration, mimeType: mime, fileName: name,
            thumbnailFileId: thumb, fileKind: kind
        )
    }
}

extension UIDevice {
    static var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine.isEmpty ? "iPhone" : machine
    }
}

