// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import CryptoKit
import Foundation

public enum DownloadError: LocalizedError {
    case listingFailed(String)
    case notEnoughSpace(needed: Int64, available: Int64)
    case badResponse(String, Int)
    case sizeMismatch(String)
    case checksumMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .listingFailed(let reason):
            return "Could not reach Hugging Face to find the model files (\(reason)). Check your internet connection, or use “Import model from folder…” instead."
        case .notEnoughSpace(let needed, let available):
            return "The model needs \(formatBytes(needed)) of disk space, but only \(formatBytes(available)) is free."
        case .badResponse(let file, let status):
            return "The download of \(file) failed (server reply \(status))."
        case .sizeMismatch(let file):
            return "\(file) did not download completely. Try again to resume."
        case .checksumMismatch(let file):
            return "\(file) was damaged during download and has been deleted. Try again."
        }
    }
}

public struct RemoteFile: Codable, Sendable {
    public var path: String
    public var size: Int64
    public var sha256: String?
}

public struct ModelInfo: Codable, Sendable {
    public var repo: String
    public var revision: String
    public var files: [RemoteFile]
    public var installed: Date
}

public func readModelRevision(directory: URL) -> String? {
    let infoURL = directory.appendingPathComponent("model_info.json")
    if let data = try? Data(contentsOf: infoURL),
        let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let revision = info["revision"] as? String
    {
        return revision
    }
    if directory.deletingLastPathComponent().lastPathComponent == "snapshots" {
        return directory.lastPathComponent
    }
    return nil
}

public struct DownloadProgress: Sendable {
    public var bytesDone: Int64
    public var bytesTotal: Int64
    public var currentFile: String
    public var bytesPerSecond: Double

    public var fraction: Double {
        bytesTotal > 0 ? Double(bytesDone) / Double(bytesTotal) : 0
    }

    public var secondsRemaining: Double? {
        bytesPerSecond > 0 ? Double(bytesTotal - bytesDone) / bytesPerSecond : nil
    }
}

let skippedFiles: Set<String> = [".gitattributes", "README.md", "zero_to_fp32.py"]

func fetchJSON(_ url: URL) async throws -> Any {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw DownloadError.listingFailed("server reply \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    }
    return try JSONSerialization.jsonObject(with: data)
}

public func listRemoteModel(repo: String) async throws -> (revision: String, files: [RemoteFile]) {
    do {
        let revisionInfo = try await fetchJSON(URL(string: "https://huggingface.co/api/models/\(repo)/revision/main")!)
        guard let revision = (revisionInfo as? [String: Any])?["sha"] as? String else {
            throw DownloadError.listingFailed("no revision")
        }
        let tree = try await fetchJSON(URL(string: "https://huggingface.co/api/models/\(repo)/tree/\(revision)")!)
        guard let entries = tree as? [[String: Any]] else {
            throw DownloadError.listingFailed("unexpected file list")
        }
        let files = entries.compactMap { entry -> RemoteFile? in
            guard entry["type"] as? String == "file", let path = entry["path"] as? String,
                !skippedFiles.contains(path), let size = (entry["size"] as? NSNumber)?.int64Value
            else {
                return nil
            }
            let sha = (entry["lfs"] as? [String: Any])?["oid"] as? String
            return RemoteFile(path: path, size: size, sha256: sha)
        }
        return (revision, files)
    } catch let error as DownloadError {
        throw error
    } catch {
        throw DownloadError.listingFailed(error.localizedDescription)
    }
}

func sha256OfFile(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 16 * 1024 * 1024), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

final class ChunkDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let destination: URL
    let onBytes: @Sendable (Int64) -> Void
    var handle: FileHandle?
    var continuation: CheckedContinuation<Void, Error>?
    var status = 0
    let fileName: String

    init(destination: URL, fileName: String, onBytes: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.fileName = fileName
        self.onBytes = onBytes
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 {
            try? FileManager.default.removeItem(at: destination)
        }
        if status == 200 || status == 206 {
            if !FileManager.default.fileExists(atPath: destination.path) {
                FileManager.default.createFile(atPath: destination.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: destination)
            _ = try? handle?.seekToEnd()
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        try? handle?.write(contentsOf: data)
        onBytes(Int64(data.count))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        if let error {
            continuation?.resume(throwing: error)
        } else if status != 200 && status != 206 {
            continuation?.resume(throwing: DownloadError.badResponse(fileName, status))
        } else {
            continuation?.resume()
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}

func downloadFile(from url: URL, to destination: URL, fileName: String, onBytes: @escaping @Sendable (Int64) -> Void)
    async throws
{
    let existing = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
    var request = URLRequest(url: url)
    if existing > 0 {
        request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
    }
    let delegate = ChunkDownloader(destination: destination, fileName: fileName, onBytes: onBytes)
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    let task = session.dataTask(with: request)
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            task.resume()
        }
    } onCancel: {
        task.cancel()
    }
}

final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var done: Int64
    private var lastReport = Date.distantPast
    private var windowStart = Date()
    private var windowBytes: Int64 = 0
    private var rate: Double = 0

    init(done: Int64) {
        self.done = done
    }

    func add(_ bytes: Int64) -> (done: Int64, rate: Double, shouldReport: Bool) {
        lock.lock()
        defer { lock.unlock() }
        done += bytes
        windowBytes += bytes
        let now = Date()
        let elapsed = now.timeIntervalSince(windowStart)
        if elapsed >= 2 {
            rate = Double(windowBytes) / elapsed
            windowBytes = 0
            windowStart = now
        }
        let report = now.timeIntervalSince(lastReport) >= 0.25
        if report {
            lastReport = now
        }
        return (done, rate, report)
    }
}

public func installedModelDirectory(_ tier: ModelTier) -> URL? {
    let folder = ModelStore.modelsDirectory.appendingPathComponent(tier.folderName, isDirectory: true)
    let info = folder.appendingPathComponent("model_info.json")
    if FileManager.default.fileExists(atPath: info.path), (try? ModelStore.checkComplete(folder)) != nil {
        return folder
    }
    if UserDefaults.standard.bool(forKey: "ignoreHuggingFaceCache") {
        return nil
    }
    if let cached = ModelStore.huggingFaceCacheSnapshot(repo: tier.repo), (try? ModelStore.checkComplete(cached)) != nil {
        return cached
    }
    return nil
}

func removeDamagedFiles(_ files: [RemoteFile], folder: URL) async throws {
    for file in files {
        try Task.checkCancellation()
        let url = folder.appendingPathComponent(file.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            continue
        }
        if let expected = file.sha256 {
            let actual = try await Task.detached(priority: .userInitiated) { try sha256OfFile(url) }.value
            if actual == expected {
                continue
            }
        }
        try FileManager.default.removeItem(at: url)
    }
}

public func downloadModel(
    _ tier: ModelTier, repair: Bool = false, onProgress: @escaping @Sendable (DownloadProgress) -> Void
) async throws -> URL {
    let (revision, files) = try await listRemoteModel(repo: tier.repo)
    let folder = ModelStore.modelsDirectory.appendingPathComponent(tier.folderName, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    func partialURL(_ file: RemoteFile) -> URL { folder.appendingPathComponent(file.path + ".part") }
    func finalURL(_ file: RemoteFile) -> URL { folder.appendingPathComponent(file.path) }
    func sizeOnDisk(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    let total = files.reduce(0) { $0 + $1.size }
    if repair {
        onProgress(DownloadProgress(bytesDone: 0, bytesTotal: total, currentFile: "Checking files", bytesPerSecond: 0))
        try await removeDamagedFiles(files, folder: folder)
    }
    let alreadyDone = files.reduce(Int64(0)) { sum, file in
        sum + (sizeOnDisk(finalURL(file)) == file.size ? file.size : sizeOnDisk(partialURL(file)))
    }
    let available = freeDiskBytes(at: folder)
    let needed = total - alreadyDone + 500_000_000
    if available < needed {
        throw DownloadError.notEnoughSpace(needed: needed, available: available)
    }

    let counter = ProgressCounter(done: alreadyDone)
    onProgress(DownloadProgress(bytesDone: alreadyDone, bytesTotal: total, currentFile: "", bytesPerSecond: 0))

    for file in files.sorted(by: { $0.size < $1.size }) {
        try Task.checkCancellation()
        let target = finalURL(file)
        if sizeOnDisk(target) == file.size {
            continue
        }
        let partial = partialURL(file)
        if sizeOnDisk(partial) > file.size {
            try FileManager.default.removeItem(at: partial)
        }
        if sizeOnDisk(partial) < file.size {
            let encodedPath = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
            let url = URL(string: "https://huggingface.co/\(tier.repo)/resolve/\(revision)/\(encodedPath)")!
            try await downloadFile(from: url, to: partial, fileName: file.path) { bytes in
                let state = counter.add(bytes)
                if state.shouldReport {
                    onProgress(DownloadProgress(
                        bytesDone: state.done, bytesTotal: total, currentFile: file.path, bytesPerSecond: state.rate))
                }
            }
        }
        guard sizeOnDisk(partial) == file.size else {
            throw DownloadError.sizeMismatch(file.path)
        }
        if let expected = file.sha256 {
            onProgress(DownloadProgress(
                bytesDone: counter.add(0).done, bytesTotal: total, currentFile: "Checking \(file.path)", bytesPerSecond: 0))
            let actual = try await Task.detached(priority: .userInitiated) { try sha256OfFile(partial) }.value
            if actual != expected {
                try? FileManager.default.removeItem(at: partial)
                throw DownloadError.checksumMismatch(file.path)
            }
        }
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: partial, to: target)
    }

    try ModelStore.fixConfigInPlace(folder)
    let info = ModelInfo(repo: tier.repo, revision: revision, files: files, installed: Date())
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(info).write(to: folder.appendingPathComponent("model_info.json"), options: .atomic)
    onProgress(DownloadProgress(bytesDone: total, bytesTotal: total, currentFile: "", bytesPerSecond: 0))
    return folder
}
