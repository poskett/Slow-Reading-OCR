// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import Foundation
import OlmOCRCore

struct SavedDocument: Codable {
    var id: UUID
    var path: String
    var kind: SourceKind
    var pageCount: Int
    var sourceSize: Int64?
    var sourceModified: Date?
    var pages: [Int]
    var pageRangeText: String
    var status: String
    var failure: String?
    var pagesDone: Int
    var flaggedPages: [Int]
    var outputPaths: [String]
    var plan: OutputPlan?
    var lastRun: DocumentRun?
    var saveFailed: Bool
    var selectedPage: Int
    var redo: Bool
}

struct SavedQueue: Codable {
    var selection: UUID?
    var documents: [SavedDocument] = []
}

enum ScanProblem: String {
    case missing = "Original file not found"
    case changed = "Original file has changed"
    case locked = "Password-protected"
}

struct SavedSourceResult: Sendable {
    var source: PageSource?
    var problem: ScanProblem?
}

let queueFile = ModelStore.applicationSupport.appendingPathComponent("queue.json")
let queueResultsFolder = ModelStore.applicationSupport.appendingPathComponent("Queue", isDirectory: true)

func savedResultsURL(_ id: UUID) -> URL {
    queueResultsFolder.appendingPathComponent(id.uuidString).appendingPathExtension("json")
}

func loadSavedQueue() -> SavedQueue {
    guard let data = try? Data(contentsOf: queueFile),
        let saved = try? JSONDecoder().decode(SavedQueue.self, from: data)
    else {
        return SavedQueue()
    }
    return saved
}

func writeSavedQueue(_ saved: SavedQueue) {
    guard let data = try? JSONEncoder().encode(saved) else {
        return
    }
    try? FileManager.default.createDirectory(
        at: queueFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: queueFile, options: .atomic)
}

func loadSavedResults(_ id: UUID) -> [PageResult] {
    guard let data = try? Data(contentsOf: savedResultsURL(id)),
        let results = try? JSONDecoder().decode([PageResult].self, from: data)
    else {
        return []
    }
    return results
}

func writeSavedResults(_ results: [PageResult], id: UUID) {
    guard let data = try? JSONEncoder().encode(results) else {
        return
    }
    try? FileManager.default.createDirectory(at: queueResultsFolder, withIntermediateDirectories: true)
    try? data.write(to: savedResultsURL(id), options: .atomic)
}

func removeSavedResults(_ id: UUID) {
    try? FileManager.default.removeItem(at: savedResultsURL(id))
}

func removeUnusedResults(keeping ids: Set<UUID>) {
    let names = Set(ids.map(\.uuidString))
    let files = (try? FileManager.default.contentsOfDirectory(
        at: queueResultsFolder, includingPropertiesForKeys: nil)) ?? []
    for file in files where !names.contains(file.deletingPathExtension().lastPathComponent) {
        try? FileManager.default.removeItem(at: file)
    }
}

func sourceFingerprint(_ url: URL, kind: SourceKind) -> (size: Int64?, modified: Date?) {
    guard kind != .folder, let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
        return (nil, nil)
    }
    return ((attributes[.size] as? NSNumber)?.int64Value, attributes[.modificationDate] as? Date)
}

func openSavedSource(
    url: URL, kind: SourceKind, pageCount: Int, size: Int64?, modified: Date?
) -> SavedSourceResult {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return SavedSourceResult(source: nil, problem: .missing)
    }
    let source: PageSource
    do {
        source = try PageSource(url: url)
    } catch PageSourceError.encrypted {
        return SavedSourceResult(source: nil, problem: .locked)
    } catch {
        return SavedSourceResult(source: nil, problem: .changed)
    }
    let current = sourceFingerprint(url, kind: kind)
    var changed = source.pageCount != pageCount
    if let size, let currentSize = current.size, size != currentSize {
        changed = true
    }
    if let modified, let currentModified = current.modified,
        abs(modified.timeIntervalSince(currentModified)) > 1
    {
        changed = true
    }
    return SavedSourceResult(source: source, problem: changed ? .changed : nil)
}
