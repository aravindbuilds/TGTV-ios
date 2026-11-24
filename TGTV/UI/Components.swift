import SwiftUI

struct RemoteImage: View {
    let url: URL?
    let placeholder: String
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        ZStack {
            LinearGradient(colors: [.gray.opacity(0.32), .black.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: placeholder)
                .font(.title)
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

struct LocalImage: View {
    let path: String?
    let placeholder: String

    var body: some View {
        Group {
            if let path, let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.gray.opacity(0.25)
                    Image(systemName: placeholder).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }
}

struct VideoCard: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store
    let item: VideoItem
    var posterURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: posterURL, placeholder: "film")
                        .frame(width: geo.size.width, height: geo.size.width * 1.5)
                        .clipped()
                        .cornerRadius(8)
                    if let ep = TitleParser.seasonEpisode(item.fileName) {
                        Text("S\(ep.season) E\(ep.episode)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.75), in: Capsule())
                            .padding(6)
                    }
                    if store.isFavourite(item) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }
            .aspectRatio(2/3, contentMode: .fit)

            Text(item.title.isEmpty ? item.fileName : item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.white)
            Text(item.chatTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(selected ? Color.red : Color.white.opacity(0.1), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.red)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 3)
    }
}

func formattedTime(_ ms: Int64) -> String {
    let total = Int(ms / 1000)
    return String(format: "%02d:%02d", total / 60, total % 60)
}
