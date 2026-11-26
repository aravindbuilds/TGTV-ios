import Foundation

/// Minimal file logger. iOS device logs are awkward to reach over USB, so the
/// app also appends to `Application Support/tgtv.log`, which can be pulled with
/// `pymobiledevice3 apps pull <bundle-id> "Library/Application Support/tgtv.log"`.
/// Never log credentials, phone numbers or message contents.
enum TGTVLog {
    private static let maxBytes: UInt64 = 512 * 1024

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tgtv.log")
    }

    static func write(_ message: String) {
        print("[TGTV] \(message)")
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(message)\n".data(using: .utf8) else { return }
        let path = url
        let size = (try? FileManager.default.attributesOfItem(atPath: path.path))?[.size] as? UInt64 ?? 0
        if size > maxBytes {
            try? data.write(to: path)
            return
        }
        if let handle = try? FileHandle(forWritingTo: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }
}
