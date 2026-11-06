// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import CryptoKit
import Foundation

public let appVersion = "1.1.1"

public struct DocumentRun: Codable, Sendable {
    public var source: String
    public var sourceKind: SourceKind
    public var totalPages: Int
    public var pagesProcessed: [Int]
    public var pagesNeedingChecking: [Int]
    public var fallbackPages: [Int]
    public var model: String
    public var modelRevision: String?
    public var promptVersion: String
    public var imageLongestSide: Int
    public var temperatureByAttempt: [Float]
    public var maxTokens: Int
    public var stopOnRepetition: Bool?
    public var appVersion: String
    public var started: Date
    public var finished: Date
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
}

public func parsePageRange(_ text: String, pageCount: Int) -> [Int]? {
    var pages: [Int] = []
    var cleaned = text
    for dash in ["–", "—", "‒", "−", "‑"] {
        cleaned = cleaned.replacingOccurrences(of: dash, with: "-")
    }
    cleaned = cleaned.replacingOccurrences(of: ";", with: ",")
    for part in cleaned.split(separator: ",") {
        let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if bounds.count == 1, let page = Int(bounds[0]) {
            pages.append(page)
        } else if bounds.count == 2 {
            let first = Int(bounds[0]) ?? 1
            let last = bounds[1].isEmpty ? pageCount : (Int(bounds[1]) ?? -1)
            guard first <= last else {
                return nil
            }
            pages.append(contentsOf: first...last)
        } else {
            return nil
        }
    }
    let valid = pages.filter { $0 >= 1 && $0 <= pageCount }
    guard !valid.isEmpty else {
        return nil
    }
    var seen = Set<Int>()
    return valid.filter { seen.insert($0).inserted }
}

public func cacheDirectory(for source: PageSource, modelName: String) -> URL {
    let attributes = try? FileManager.default.attributesOfItem(atPath: source.url.path)
    let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let key = "\(source.url.standardizedFileURL.path)|\(size)|\(modified)|\(source.pageCount)|\(modelName)|\(promptVersion)"
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return ModelStore.jobsDirectory
        .appendingPathComponent(String(digest.prefix(16)), isDirectory: true)
}

func cachedPageURL(_ directory: URL, page: Int) -> URL {
    directory.appendingPathComponent(String(format: "page_%05d.json", page))
}

public func loadCachedPage(_ directory: URL, page: Int) -> PageResult? {
    guard let data = try? Data(contentsOf: cachedPageURL(directory, page: page)) else {
        return nil
    }
    return try? JSONDecoder().decode(PageResult.self, from: data)
}

public func saveCachedPage(_ result: PageResult, directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(result)
    try data.write(to: cachedPageURL(directory, page: result.page), options: .atomic)
}

public enum PageEvent: Sendable {
    case started(page: Int, index: Int, total: Int)
    case attempt(PageAttempt)
    case tokens(page: Int, count: Int)
    case finished(result: PageResult, index: Int, total: Int, fromCache: Bool)
}

public func transcribeDocument(
    engine: OCREngine,
    source: PageSource,
    pages: [Int],
    tokenLimit: Int = defaultTokenLimit,
    stopOnRepetition: Bool = true,
    onEvent: @escaping @Sendable (PageEvent) -> Void
) async throws -> (results: [PageResult], run: DocumentRun) {
    let started = Date()
    let modelName = await engine.modelName
    let cache = cacheDirectory(for: source, modelName: modelName + (await engine.modelRevision ?? ""))
    var results: [PageResult] = []

    for (index, page) in pages.enumerated() {
        try Task.checkCancellation()
        if let cached = loadCachedPage(cache, page: page),
            !(cached.needsChecking && (cached.tokenLimit ?? maxTokens) < tokenLimit)
        {
            results.append(cached)
            onEvent(.finished(result: cached, index: index, total: pages.count, fromCache: true))
            continue
        }
        onEvent(.started(page: page, index: index, total: pages.count))
        let image = try source.render(page: page)
        var result = try await engine.processPage(
            image: image, page: page, fallbackText: source.embeddedText(page: page), tokenLimit: tokenLimit,
            stopOnRepetition: stopOnRepetition
        ) { attempt in
            onEvent(.attempt(attempt))
        } onTokens: { count in
            onEvent(.tokens(page: page, count: count))
        }
        result.finishedAt = Date()
        result.tokenLimit = tokenLimit
        result.stopOnRepetition = stopOnRepetition
        try saveCachedPage(result, directory: cache)
        results.append(result)
        onEvent(.finished(result: result, index: index, total: pages.count, fromCache: false))
    }

    let run = DocumentRun(
        source: source.url.path,
        sourceKind: source.kind,
        totalPages: source.pageCount,
        pagesProcessed: pages,
        pagesNeedingChecking: results.filter(\.needsChecking).map(\.page),
        fallbackPages: results.filter(\.isFallback).map(\.page),
        model: modelName,
        modelRevision: await engine.modelRevision,
        promptVersion: promptVersion,
        imageLongestSide: Int(targetLongestSide),
        temperatureByAttempt: temperatureByAttempt,
        maxTokens: tokenLimit,
        stopOnRepetition: stopOnRepetition,
        appVersion: appVersion,
        started: started,
        finished: Date(),
        totalInputTokens: results.reduce(0) { $0 + $1.inputTokens },
        totalOutputTokens: results.reduce(0) { $0 + $1.outputTokens }
    )
    return (results, run)
}
