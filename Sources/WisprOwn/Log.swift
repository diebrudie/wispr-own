import Foundation
import os

let logger = Logger(subsystem: "com.diebrudie.wisprown", category: "app")

/// Timestamped stdout log for terminal runs (eval gates G1/G4 read these);
/// mirrored to os_log so Console.app sees them from the bundled .app.
func dlog(_ message: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    print("[\(f.string(from: Date()))] \(message)")
    // .notice is the lowest level the unified log persists to disk —
    // .info is memory-only, invisible to `log show` after the fact.
    logger.notice("\(message, privacy: .public)")
}
