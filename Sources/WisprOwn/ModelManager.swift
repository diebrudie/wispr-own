import CryptoKit
import Foundation

/// Spec 03 — downloads ggml-large-v3-turbo on first launch.
/// Checksum is trust-on-first-use: SHA-256 is computed after the first
/// successful download and pinned next to the model; a later mismatch
/// (corrupted/replaced file) forces a re-download.
final class ModelManager: NSObject {
    /// Main transcription model.
    static let modelName = "ggml-large-v3-turbo.bin"
    static let modelURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!
    /// Guards against truncated downloads; the real file is ~1.62 GB.
    static let minimumBytes: Int64 = 1_500_000_000

    /// Tiny model used only for language detection — one full encoder pass
    /// on the big model costs seconds; on this one it's ~0.2 s.
    static let detectModelName = "ggml-base.bin"
    static let detectModelURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!
    static let detectMinimumBytes: Int64 = 140_000_000

    /// CoreML encoder — whisper.cpp auto-loads it when the .mlmodelc sits
    /// next to the .bin. Runs on the Neural Engine: measured 3 s → ~0.8 s
    /// per dictation on an M3. Optional: Metal fallback works without it.
    static let encoderDirName = "ggml-large-v3-turbo-encoder.mlmodelc"
    static let encoderZipURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-encoder.mlmodelc.zip")!
    static let encoderZipMinimumBytes: Int64 = 1_000_000_000

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WisprOwn")
    }
    static var modelPath: URL { supportDir.appendingPathComponent("models/\(modelName)") }
    static var detectModelPath: URL { supportDir.appendingPathComponent("models/\(detectModelName)") }

    var onProgress: (Double) -> Void = { _ in }

    private var continuation: CheckedContinuation<Void, Error>?
    private var currentDestination: URL?
    private var currentMinimumBytes: Int64 = 0
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    var modelReady: Bool {
        fileReady(Self.modelPath, minBytes: Self.minimumBytes)
            && fileReady(Self.detectModelPath, minBytes: Self.detectMinimumBytes)
    }

    private func fileReady(_ path: URL, minBytes: Int64) -> Bool {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: path.path)[.size] as? Int64 else { return false }
        return size >= minBytes
    }

    func ensureModel() async throws {
        try await ensure(url: Self.detectModelURL, at: Self.detectModelPath,
                         minBytes: Self.detectMinimumBytes, label: "~150 MB")
        try await ensure(url: Self.modelURL, at: Self.modelPath,
                         minBytes: Self.minimumBytes, label: "~1.6 GB")
        await ensureCoreMLEncoder()
    }

    /// Best-effort: transcription works without it (Metal fallback), so a
    /// failed download logs and moves on instead of blocking startup.
    private func ensureCoreMLEncoder() async {
        let encoderDir = Self.modelPath.deletingLastPathComponent()
            .appendingPathComponent(Self.encoderDirName)
        guard !FileManager.default.fileExists(atPath: encoderDir.path) else { return }
        let zipPath = Self.supportDir.appendingPathComponent("models/encoder.zip")
        do {
            try await ensure(url: Self.encoderZipURL, at: zipPath,
                             minBytes: Self.encoderZipMinimumBytes, label: "~1.2 GB, CoreML encoder")
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-xk", zipPath.path, zipPath.deletingLastPathComponent().path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: encoderDir.path) else {
                throw URLError(.cannotParseResponse)
            }
            dlog("model: CoreML encoder installed (first load compiles it, ~1 min)")
        } catch {
            dlog("model: CoreML encoder unavailable (\(error.localizedDescription)) — using Metal fallback")
        }
        try? FileManager.default.removeItem(at: zipPath)
        try? FileManager.default.removeItem(at: zipPath.appendingPathExtension("sha256"))
        try? FileManager.default.removeItem(
            at: zipPath.deletingLastPathComponent().appendingPathComponent("__MACOSX"))
    }

    /// Checksum is trust-on-first-use: pinned after the first download,
    /// verified on later launches; a mismatch forces a re-download.
    private func ensure(url: URL, at path: URL, minBytes: Int64, label: String) async throws {
        let checksumPath = path.appendingPathExtension("sha256")
        if fileReady(path, minBytes: minBytes) {
            guard let pinned = try? String(contentsOf: checksumPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            if try Self.sha256(of: path) == pinned { return }
            dlog("model: checksum mismatch for \(path.lastPathComponent), re-downloading")
            try FileManager.default.removeItem(at: path)
            try? FileManager.default.removeItem(at: checksumPath)
        }
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        dlog("model: downloading \(path.lastPathComponent) (\(label), one-time)")
        currentDestination = path
        currentMinimumBytes = minBytes
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            session.downloadTask(with: url).resume()
        }
        let checksum = try Self.sha256(of: path)
        try checksum.write(to: checksumPath, atomically: true, encoding: .utf8)
        dlog("model: \(path.lastPathComponent) ready, sha256 pinned \(checksum.prefix(12))…")
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            guard let destination = currentDestination else { throw URLError(.unknown) }
            guard let http = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let size = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0
            guard size >= currentMinimumBytes else { throw URLError(.cannotParseResponse) }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
