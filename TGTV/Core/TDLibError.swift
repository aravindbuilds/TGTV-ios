import Foundation
import TDLibKit

/// TDLibKit's `Error` conforms to `Swift.Error` but not to `LocalizedError`, so
/// `error.localizedDescription` collapses every failure into the useless
/// "The operation couldn't be completed. (TDLibKit.Error error 1.)".
/// This helper surfaces the real TDLib code and message instead, e.g.
/// `400: PHONE_NUMBER_INVALID`.
func tgErrorText(_ error: Swift.Error) -> String {
    if let td = error as? TDLibKit.Error {
        return "\(td.code): \(td.message)"
    }
    let ns = error as NSError
    if ns.domain == "TGTV" { return ns.localizedDescription }
    return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
}

/// A validation error raised by the app itself (never by TDLib).
struct TGTVError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// TDLib emits snake_case JSON (`authorization_state`, `@type`), while TDLibKit's
/// generated models are camelCase. This decoder matches the one TDLibKit builds
/// internally; without it every update fails with `keyNotFound`.
let tgUpdateDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()
