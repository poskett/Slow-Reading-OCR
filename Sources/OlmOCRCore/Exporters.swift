// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import CryptoKit
import Foundation

public enum OutputFormat: String, CaseIterable, Codable, Sendable {
    case markdown
    case text
    case pages
    case jsonl
    case manifest
}

public struct ExportedFiles: Sendable {
    public var files: [URL]
}

func pageMarker(_ result: PageResult, label: String) -> String {
    var marker = "<!-- p. \(result.page)"
    if label != "\(result.page)" {
        marker += ", \(label)"
    }
    if result.response.naturalText == nil {
        marker += ", blank"
    }
    if result.needsChecking {
        marker += ", NEEDS CHECKING: \(result.problem ?? "uncertain result")"
    }
    return marker + " -->"
}

public func markdownDocument(_ results: [PageResult], source: PageSource) -> String {
    results.map { result in
        let marker = pageMarker(result, label: source.pageLabel(result.page))
        guard let text = result.response.naturalText else {
            return marker
        }
        return marker + "\n\n" + text
    }.joined(separator: "\n\n") + "\n"
}

public func plainText(fromMarkdown markdown: String) -> String {
    var text = markdown
    let replacements: [(String, String)] = [
        (#"!\[([^\]]*)\]\([^)]*\)"#, "[Figure: $1]"),
        (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
        (#"(?m)^#{1,6}\s+"#, ""),
        (#"\*\*([^*]+)\*\*"#, "$1"),
        (#"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, "$1"),
        (#"(?<![\w_])_([^_\n]+)_(?![\w_])"#, "$1"),
        (#"(?m)^>\s?"#, ""),
        (#"</?(?:table|thead|tbody|tr)[^>]*>"#, "\n"),
        (#"</t[hd]>"#, "\t"),
        (#"<[^>]+>"#, ""),
        (#"\n{3,}"#, "\n\n"),
    ]
    for (pattern, template) in replacements {
        text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
    return text
}

public func plainTextDocument(_ results: [PageResult], source: PageSource) -> String {
    results.map { result in
        var header = "[p. \(result.page)"
        if source.kind == .folder {
            header += ", \(source.pageLabel(result.page))"
        }
        if result.needsChecking {
            header += ", NEEDS CHECKING"
        }
        header += "]"
        return header + "\n\n" + plainText(fromMarkdown: result.response.naturalText ?? "")
    }.joined(separator: "\n\n") + "\n"
}

public func dolmaRecord(_ results: [PageResult], run: DocumentRun) -> [String: Any]? {
    var documentText = ""
    var spans: [[Int]] = []
    for (index, result) in results.enumerated() {
        let start = documentText.unicodeScalars.count
        if let text = result.response.naturalText {
            documentText += text + (index < results.count - 1 ? "\n" : "")
        }
        spans.append([start, documentText.unicodeScalars.count, result.page])
    }
    guard !documentText.isEmpty else {
        return nil
    }
    let day = ISO8601DateFormatter.string(from: run.finished, timeZone: .current, formatOptions: [.withFullDate])
    let id = Insecure.SHA1.hash(data: Data(documentText.utf8)).map { String(format: "%02x", $0) }.joined()
    func list<T>(_ value: (PageResult) -> T) -> [Any] { results.map { value($0) as Any } }
    return [
        "id": id,
        "text": documentText,
        "source": "olmocr",
        "added": day,
        "created": day,
        "metadata": [
            "Source-File": run.source,
            "olmocr-version": "olmocr-mac \(run.appVersion)",
            "pdf-total-pages": results.count,
            "total-input-tokens": run.totalInputTokens,
            "total-output-tokens": run.totalOutputTokens,
            "total-fallback-pages": run.fallbackPages.count,
            "model": run.model,
        ],
        "attributes": [
            "pdf_page_numbers": spans,
            "primary_language": results.map { ($0.response.primaryLanguage as Any?) ?? NSNull() },
            "is_rotation_valid": list { $0.response.isRotationValid },
            "rotation_correction": list { $0.response.rotationCorrection },
            "is_table": list { $0.response.isTable },
            "is_diagram": list { $0.response.isDiagram },
            "needs_checking": list { $0.needsChecking },
        ],
    ]
}

public func outputBaseURL(for source: PageSource, outputFolder: URL?) -> URL {
    let folder = outputFolder ?? source.url.deletingLastPathComponent()
    let name = source.kind == .folder ? source.url.lastPathComponent : source.url.deletingPathExtension().lastPathComponent
    return folder.appendingPathComponent(name)
}

public struct OutputPlan: Sendable {
    public var base: URL
    public var pagesFolder: URL
    public var manifest: URL
    public var formats: [OutputFormat]
    public var model: String
    public var modelRevision: String?
}

public func makeOutputPlan(
    source: PageSource, outputFolder: URL?, formats: [OutputFormat], model: String, modelRevision: String?
) -> OutputPlan {
    let base = availableBase(for: source, outputFolder: outputFolder)
    return OutputPlan(
        base: base,
        pagesFolder: URL(fileURLWithPath: base.path + "_pages", isDirectory: true),
        manifest: URL(fileURLWithPath: base.path + "_manifest.csv"),
        formats: formats,
        model: model,
        modelRevision: modelRevision
    )
}

func pageFileExtensions(_ formats: [OutputFormat]) -> [String] {
    var extensions: [String] = []
    if formats.contains(.markdown) {
        extensions.append("md")
    }
    if formats.contains(.text) {
        extensions.append("txt")
    }
    return extensions.isEmpty ? ["md"] : extensions
}

public func pageFileURL(page: Int, source: PageSource, plan: OutputPlan, fileExtension: String? = nil) -> URL {
    let stem: String
    if source.kind == .folder {
        stem = source.imageFiles[page - 1].deletingPathExtension().lastPathComponent
    } else {
        stem = String(format: "p%04d", page)
    }
    let ext = fileExtension ?? pageFileExtensions(plan.formats)[0]
    return plan.pagesFolder.appendingPathComponent(stem).appendingPathExtension(ext)
}

public func writePageFile(_ result: PageResult, source: PageSource, plan: OutputPlan, onlyIfMissing: Bool = false) throws {
    guard plan.formats.contains(.pages) else {
        return
    }
    let manager = FileManager.default
    if !manager.fileExists(atPath: plan.pagesFolder.path) {
        try manager.createDirectory(at: plan.pagesFolder, withIntermediateDirectories: true)
        markAsOutput(plan.pagesFolder, source: source)
    }
    for ext in pageFileExtensions(plan.formats) {
        let url = pageFileURL(page: result.page, source: source, plan: plan, fileExtension: ext)
        if onlyIfMissing && manager.fileExists(atPath: url.path) {
            continue
        }
        let text = result.response.naturalText ?? ""
        let content = ext == "txt" ? plainText(fromMarkdown: text) : text
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

public let promptHash: String = {
    let digest = SHA256.hash(data: Data(olmOCRPrompt.utf8)).map { String(format: "%02x", $0) }.joined()
    return String(digest.prefix(10))
}()

func csvField(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

func pageStatus(_ result: PageResult) -> String {
    if result.isFallback && result.response.naturalText == nil {
        return "failed"
    }
    if result.isFallback {
        return "fallback"
    }
    if result.needsChecking {
        return "check"
    }
    if result.response.naturalText == nil {
        return "blank"
    }
    return "ok"
}

let manifestColumns = [
    "source_file", "page", "page_label", "image_path", "page_file", "model", "model_revision",
    "prompt_version", "prompt_hash", "options", "status", "problem", "language", "is_table", "is_diagram",
    "rotation", "attempts", "temperature", "chars", "input_tokens", "output_tokens", "seconds", "timestamp",
]

public func manifestCSV(_ results: [PageResult], source: PageSource, plan: OutputPlan) -> String {
    let temperatures = temperatureByAttempt.map { String($0) }.joined(separator: ", ")
    func optionsText(_ result: PageResult) -> String {
        let limit = result.tokenLimit ?? maxTokens
        let repetition = (result.stopOnRepetition ?? false) ? "true" : "false"
        return "{\"image_longest_side\": \(Int(targetLongestSide)), \"max_tokens\": \(limit), \"stop_on_repetition\": \(repetition), \"temperature_by_attempt\": [\(temperatures)]}"
    }
    let timestampFormatter = ISO8601DateFormatter()
    timestampFormatter.formatOptions = [.withInternetDateTime]
    timestampFormatter.timeZone = .current

    var lines = [manifestColumns.joined(separator: ",")]
    for result in results.sorted(by: { $0.page < $1.page }) {
        let pageFile = plan.formats.contains(.pages) ? pageFileURL(page: result.page, source: source, plan: plan).path : ""
        let imagePath = source.kind == .folder ? source.imageFiles[result.page - 1].path : ""
        let row: [String] = [
            source.url.lastPathComponent,
            "\(result.page)",
            source.pageLabel(result.page),
            imagePath,
            pageFile,
            plan.model,
            plan.modelRevision ?? "",
            promptVersion,
            promptHash,
            optionsText(result),
            pageStatus(result),
            result.problem ?? "",
            result.response.primaryLanguage ?? "",
            result.response.isTable ? "true" : "false",
            result.response.isDiagram ? "true" : "false",
            "\(result.rotation)",
            "\(result.attempts)",
            String(format: "%.1f", result.temperature),
            "\(result.response.naturalText?.count ?? 0)",
            "\(result.inputTokens)",
            "\(result.outputTokens)",
            String(format: "%.1f", result.seconds),
            result.finishedAt.map { timestampFormatter.string(from: $0) } ?? "",
        ]
        lines.append(row.map(csvField).joined(separator: ","))
    }
    return lines.joined(separator: "\n") + "\n"
}

public func writeManifest(_ results: [PageResult], source: PageSource, plan: OutputPlan) throws {
    guard plan.formats.contains(.manifest) else {
        return
    }
    try FileManager.default.createDirectory(
        at: plan.manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
    try manifestCSV(results, source: source, plan: plan).write(to: plan.manifest, atomically: true, encoding: .utf8)
    markAsOutput(plan.manifest, source: source)
}

public func writeOutputs(results: [PageResult], run: DocumentRun, source: PageSource, plan: OutputPlan) throws
    -> ExportedFiles
{
    let base = plan.base
    try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
    var written: [URL] = []

    for format in plan.formats {
        switch format {
        case .markdown:
            let url = base.appendingPathExtension("md")
            try markdownDocument(results, source: source).write(to: url, atomically: true, encoding: .utf8)
            markAsOutput(url, source: source)
            written.append(url)
        case .text:
            let url = base.appendingPathExtension("txt")
            try plainTextDocument(results, source: source).write(to: url, atomically: true, encoding: .utf8)
            markAsOutput(url, source: source)
            written.append(url)
        case .pages:
            for result in results {
                try writePageFile(result, source: source, plan: plan)
            }
            written.append(plan.pagesFolder)
        case .jsonl:
            let url = base.appendingPathExtension("jsonl")
            if let record = dolmaRecord(results, run: run) {
                let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
                try (String(data: data, encoding: .utf8)! + "\n").write(to: url, atomically: true, encoding: .utf8)
                markAsOutput(url, source: source)
                written.append(url)
            }
        case .manifest:
            try writeManifest(results, source: source, plan: plan)
            written.append(plan.manifest)
        }
    }
    return ExportedFiles(files: written)
}

let outputMarker = "io.github.poskett.slowreading.output"

func sourceKey(_ source: PageSource) -> String {
    source.url.standardizedFileURL.path
}

public func isOutput(_ url: URL, of source: PageSource) -> Bool {
    let size = getxattr(url.path, outputMarker, nil, 0, 0, 0)
    guard size > 0 else {
        return false
    }
    var buffer = [UInt8](repeating: 0, count: size)
    getxattr(url.path, outputMarker, &buffer, size, 0, 0)
    return String(decoding: buffer, as: UTF8.self) == sourceKey(source)
}

func markAsOutput(_ url: URL, source: PageSource) {
    let value = Array(sourceKey(source).utf8)
    setxattr(url.path, outputMarker, value, value.count, 0, 0)
}

func outputCandidates(_ base: URL) -> [URL] {
    [
        base.appendingPathExtension("md"), base.appendingPathExtension("txt"), base.appendingPathExtension("jsonl"),
        URL(fileURLWithPath: base.path + "_pages", isDirectory: true),
        URL(fileURLWithPath: base.path + "_manifest.csv"),
    ]
}

public func availableBase(for source: PageSource, outputFolder: URL?) -> URL {
    let first = outputBaseURL(for: source, outputFolder: outputFolder)
    let folder = first.deletingLastPathComponent()
    let name = first.lastPathComponent
    let manager = FileManager.default
    var number = 1
    while true {
        let base = number == 1 ? first : folder.appendingPathComponent("\(name) (\(number))")
        let free = outputCandidates(base).allSatisfy { url in
            !manager.fileExists(atPath: url.path) || isOutput(url, of: source)
        }
        if free {
            return base
        }
        number += 1
    }
}
