import Foundation
import Network

/// A tiny localhost HTTP server that lets AVPlayer stream a Telegram file
/// progressively. AVPlayer cannot read TDLib's partial file directly, so the
/// player requests byte ranges from this proxy and the proxy pulls those
/// windows from TDLib on demand — the same idea as the Android app's
/// `TdVideoStreamDataSource`.
final class TDLibStreamProxy {
    private let fileId: Int
    private let fileSize: Int64
    private let queue = DispatchQueue(label: "com.tgtv.iphone.stream", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let windowSize: Int64 = 2 * 1024 * 1024

    private(set) var port: UInt16 = 0
    private(set) var url: URL?

    init(fileId: Int, size: Int64) {
        self.fileId = fileId
        self.fileSize = max(size, 1)
    }

    deinit { stop() }

    func start() async throws -> URL {
        guard listener == nil else { return url! }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let newListener = try NWListener(using: parameters)
        listener = newListener

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self, !resumed else { return }
                switch state {
                case .ready:
                    guard let port = newListener.port?.rawValue else { return }
                    resumed = true
                    self.port = port
                    let url = URL(string: "http://127.0.0.1:\(port)/video")!
                    self.url = url
                    continuation.resume(returning: url)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                self.receive(remaining: Data(), on: connection)
            }
            newListener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections { connection.cancel() }
        connections.removeAll()
    }

    // MARK: - HTTP

    private func receive(remaining: Data, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = remaining
            if let data { buffer.append(data) }
            guard let text = String(data: buffer, encoding: .utf8),
                  let headerEnd = text.range(of: "\r\n\r\n") else {
                if complete || error != nil { connection.cancel() }
                else { self.receive(remaining: buffer, on: connection) }
                return
            }
            let request = String(text[text.startIndex..<headerEnd.lowerBound])
            Task { await self.respond(to: request, on: connection) }
        }
    }

    private func respond(to request: String, on connection: NWConnection) async {
        let range = parseRange(request)
        let start = range?.0 ?? 0
        let requestedEnd = range?.1 ?? (fileSize - 1)
        let windowStart = (start / windowSize) * windowSize
        let end = min(max(requestedEnd, start), fileSize - 1, windowStart + windowSize - 1)
        let length = end - start + 1
        guard length > 0 else { connection.cancel(); return }

        let available = await TDLibService.shared.ensureRange(fileId: fileId, start: windowStart, end: end)
        guard available,
              let bytes = await TDLibService.shared.readRange(fileId: fileId, offset: start, length: length) else {
            let body = Data("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: body, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        let isPartial = range != nil
        let status = isPartial ? "206 Partial Content" : "200 OK"
        var headers = "HTTP/1.1 \(status)\r\n"
        headers += "Content-Type: video/mp4\r\n"
        headers += "Accept-Ranges: bytes\r\n"
        headers += "Content-Length: \(bytes.count)\r\n"
        if isPartial { headers += "Content-Range: bytes \(start)-\(end)/\(fileSize)\r\n" }
        headers += "Connection: close\r\n\r\n"

        connection.send(content: Data(headers.utf8) + bytes,
                        completion: .contentProcessed { _ in connection.cancel() })

        // Warm the next window while the current one is being consumed.
        let nextStart = windowStart + windowSize
        if nextStart < fileSize {
            let fid = fileId
            let size = fileSize
            let window = windowSize
            Task.detached {
                let nextEnd = min(nextStart + window - 1, size - 1)
                await TDLibService.shared.ensureRange(fileId: fid, start: nextStart, end: nextEnd)
            }
        }
    }

    private func parseRange(_ request: String) -> (Int64, Int64)? {
        let lines = request.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let line = lines.first(where: { $0.lowercased().hasPrefix("range:") }) else { return nil }
        let value = line.split(separator: ":", maxSplits: 1).last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = String(value.dropFirst(6))
        let parts = spec.split(separator: "-", maxSplits: 1)
        guard let first = parts.first else { return nil }
        let start = Int64(first) ?? 0
        if parts.count < 2 || parts[1].isEmpty { return (start, fileSize - 1) }
        return (start, Int64(parts[1]) ?? (fileSize - 1))
    }
}
