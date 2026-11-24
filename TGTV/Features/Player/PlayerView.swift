import SwiftUI
import AVKit
import MediaPlayer

@MainActor
final class PlayerModel: ObservableObject {
    @Published var player = AVPlayer()
    @Published var position: Int64 = 0
    @Published var duration: Int64 = 0
    @Published var isPlaying = false
    @Published var gravity: AVLayerVideoGravity = .resizeAspect
    @Published var speed: Float = 1
    @Published var status = "Loading…"
    @Published var subtitleText: String = ""
    @Published var errorMessage: String?

    let item: VideoItem
    private let startAt: Int64?
    private var observer: Any?
    private var cues: [SubtitleCue] = []
    private var loaded = false

    init(item: VideoItem, startAt: Int64? = nil) {
        self.item = item
        self.startAt = startAt
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        status = "Fetching from Telegram…"
        guard let path = await TDLibService.shared.localPath(for: item.fileId) else {
            status = "Could not load file"
            errorMessage = TDLibService.shared.lastError ?? "The file is not available offline."
            return
        }
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        if let duration = try? await asset.load(.duration) {
            self.duration = Int64(duration.seconds * 1000)
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            let ms = Int64(time.seconds * 1000)
            Task { @MainActor in
                guard let self else { return }
                self.position = ms
                if self.duration > 0 { self.duration = max(self.duration, ms) }
                self.updateSubtitle(at: ms)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }
        if let start = startAt, start > 0 {
            player.seek(to: CMTime(milliseconds: start))
        }
        player.play()
        isPlaying = true
        status = "Playing"
        if let path = SubtitlesClient.shared.cachedPath(for: item.fileId) { loadSubtitles(path) }
    }

    func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func skip(_ seconds: Double) {
        let time = player.currentTime() + CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
    }

    func setSpeed(_ value: Float) {
        speed = value
        player.rate = value
    }

    func cycleGravity() {
        switch gravity {
        case .resizeAspect: gravity = .resizeAspectFill
        default: gravity = .resizeAspect
        }
    }

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let target = CMTime(milliseconds: Int64(Double(duration) * fraction))
        player.seek(to: target)
    }

    func attachSubtitles(_ path: String) {
        loadSubtitles(path)
    }

    private func loadSubtitles(_ path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var result: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard lines.count >= 2,
                  let arrow = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[arrow].split(separator: "-->").map(String.init)
            guard parts.count == 2 else { continue }
            let start = Self.parseTime(parts[0].trimmingCharacters(in: .whitespaces))
            let end = Self.parseTime(parts[1].trimmingCharacters(in: .whitespaces))
            let body = lines[(arrow + 1)...].joined(separator: "\n")
            result.append(SubtitleCue(start: start, end: end, text: body))
        }
        cues = result
    }

    private static func parseTime(_ value: String) -> Int64 {
        let cleaned = value.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return 0 }
        return Int64((h * 3600 + m * 60 + s) * 1000)
    }

    private func updateSubtitle(at ms: Int64) {
        guard !cues.isEmpty else { return }
        subtitleText = cues.first { ms >= $0.start && ms <= $0.end }?.text ?? ""
    }

    func saveProgress() {
        let entry = WatchProgressEntry(
            p: position, d: duration, u: Int64(Date().timeIntervalSince1970 * 1000)
        )
        Store.shared.save(progress: entry, key: WatchProgressEntry.key(chatId: item.chatId, messageId: item.messageId))
        Task { await ProgressSync.shared.publish(item: item, entry: entry) }
        Task { await CloudBackup.shared.request() }
    }
}

struct SubtitleCue {
    let start: Int64
    let end: Int64
    let text: String
}

extension CMTime {
    static func milliseconds(_ value: Int64) -> CMTime {
        CMTime(value: value, timescale: 1000)
    }
}

struct PlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = gravity
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let layer = view.layer.sublayers?.first as? AVPlayerLayer else { return }
        layer.player = player
        layer.videoGravity = gravity
        layer.frame = view.bounds
        DispatchQueue.main.async { layer.frame = view.bounds }
    }
}

struct PlayerView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store
    let item: VideoItem
    var startAt: Int64? = nil

    @StateObject private var model: PlayerModel
    @State private var controls = true
    @State private var showSubtitleSheet = false
    @State private var candidates: [SubtitlesClient.Candidate] = []
    @State private var searchQuery = ""
    @State private var subtitleSearching = false

    init(item: VideoItem, startAt: Int64? = nil) {
        self.item = item
        self.startAt = startAt
        _model = StateObject(wrappedValue: PlayerModel(item: item, startAt: startAt))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerLayer(player: model.player, gravity: model.gravity)
                .ignoresSafeArea()

            // Double-tap seek zones
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.skip(-10) }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.skip(10) }
            }
            .ignoresSafeArea()

            if !model.subtitleText.isEmpty {
                Text(model.subtitleText)
                    .font(.system(size: CGFloat(14 + store.subsTextSize * 4), weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .padding(.horizontal)
                    .padding(.bottom, 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            if model.errorMessage != nil {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(model.status).font(.headline)
                    Text(model.errorMessage ?? "").font(.caption).multilineTextAlignment(.center)
                    Button("Retry") { Task { await model.load() } }
                        .buttonStyle(.borderedProminent).tint(.red)
                }
                .padding()
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            }

            if controls {
                VStack {
                    HStack {
                        Button {
                            model.togglePlay()
                        } label: {
                            Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 30))
                        }
                        Spacer()
                        Text(item.title.isEmpty ? item.fileName : item.title)
                            .font(.caption).lineLimit(1)
                        Spacer()
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                                Button("\(value, specifier: "%.2f")×") { model.setSpeed(Float(value)) }
                            }
                        } label: {
                            Text("\(model.speed, specifier: "%.2f")×").font(.caption)
                        }
                        Button { model.cycleGravity() } label: {
                            Image(systemName: "rectangle")
                        }
                        Button { showSubtitleSheet = true } label: {
                            Image(systemName: "captions.bubble")
                        }
                    }
                    .foregroundStyle(.white)
                    .padding()

                    Spacer()

                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { model.duration > 0 ? Double(model.position) / Double(model.duration) : 0 },
                                set: { model.seek(to: $0) }
                            )
                        )
                        .tint(.red)
                        HStack {
                            Text(formattedTime(model.position))
                            Spacer()
                            Text(formattedTime(model.duration))
                        }
                        .font(.caption2)
                    }
                    .padding()
                    .background(.black.opacity(0.55))
                }
            }
        }
        .onTapGesture { withAnimation { controls.toggle() } }
        .onAppear { Task { await model.load() } }
        .onDisappear { model.saveProgress() }
        .sheet(isPresented: $showSubtitleSheet) {
            NavigationStack {
                VStack {
                    TextField("Search subtitles", text: $searchQuery)
                        .textFieldStyle(.roundedBorder).padding()
                    Button("Search") {
                        subtitleSearching = true
                        Task {
                            candidates = await SubtitlesClient.shared.search(
                                fileName: searchQuery.isEmpty ? item.fileName : searchQuery
                            )
                            subtitleSearching = false
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                    if subtitleSearching { ProgressView() }
                    List(candidates) { candidate in
                        Button {
                            Task {
                                if let path = await SubtitlesClient.shared.download(candidate, videoFileId: item.fileId) {
                                    model.attachSubtitles(path)
                                    showSubtitleSheet = false
                                }
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(candidate.fileName).font(.subheadline)
                                Text("\(candidate.language) · \(candidate.releaseName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Subtitles")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showSubtitleSheet = false }
                    }
                }
            }
        }
    }
}
