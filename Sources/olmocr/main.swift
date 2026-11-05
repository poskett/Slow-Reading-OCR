// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import Foundation
import OlmOCRCore

let usage = """
    usage: olmocr [options] <pdf, image or folder of images> ...

      --model <full|compact|folder>  model to use (default: the one recommended for this Mac)
      --pages <range>                e.g. 1-5,9 (default: all pages)
      --out <folder>                 where to write results (default: next to each source)
      --format <list>                markdown,text,pages,jsonl,manifest (default: markdown)
      --max-tokens <n>               page length limit: 4000, 6000 (default) or 8000
      --no-repetition-check          let attempts run on when the model repeats itself (olmOCR behaviour)
      --save-images <folder>         also save each rendered page image (for checking)

    other commands:
      olmocr --check                 report what this Mac can run
      olmocr --download <full|compact>
    """

var arguments = Array(CommandLine.arguments.dropFirst())

func tier(named name: String) -> ModelTier? {
    switch name {
    case "full", "8bit": return .full
    case "compact", "4bit": return .compact
    default: return nil
    }
}

if arguments.first == "--check" {
    let report = checkSystem()
    print(report.diagnosticText)
    if let problem = report.blockingProblem {
        print("\nCannot run: \(problem)")
    }
    for tier in report.supportedTiers {
        let location = installedModelDirectory(tier)?.path ?? "not installed"
        print("\n\(tier.title) (\(tier.folderName)): \(location)")
        for warning in report.warnings(for: tier) {
            print("  warning: \(warning)")
        }
    }
    exit(0)
}

if arguments.first == "--download" {
    guard arguments.count == 2, let tier = tier(named: arguments[1]) else {
        print(usage)
        exit(1)
    }
    print("Downloading \(tier.repo) to \(ModelStore.modelsDirectory.path)")
    let folder = try await downloadModel(tier) { progress in
        let remaining = progress.secondsRemaining.map { String(format: ", about %.0f min left", $0 / 60) } ?? ""
        print(String(format: "  %5.1f%%  %@ of %@  %.1f MB/s%@  %@",
            progress.fraction * 100, formatBytes(progress.bytesDone), formatBytes(progress.bytesTotal),
            progress.bytesPerSecond / 1_000_000, remaining, progress.currentFile))
    }
    print("Installed in \(folder.path)")
    exit(0)
}

@MainActor func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

let modelChoice = option("--model") ?? checkSystem().recommendedTier?.rawValue ?? "compact"
let pageRange = option("--pages")
let outputFolder = option("--out").map { URL(fileURLWithPath: $0, isDirectory: true) }
let imageFolder = option("--save-images").map { URL(fileURLWithPath: $0, isDirectory: true) }
let tokenLimit = option("--max-tokens").flatMap(Int.init) ?? defaultTokenLimit
let stopOnRepetition = !arguments.contains("--no-repetition-check")
arguments.removeAll { $0 == "--no-repetition-check" }
let formatText = option("--format") ?? "markdown"
let formats = formatText.split(separator: ",").compactMap { OutputFormat(rawValue: String($0)) }

guard !arguments.isEmpty, !formats.isEmpty else {
    print(usage)
    exit(1)
}

var modelDirectory = URL(fileURLWithPath: modelChoice, isDirectory: true)
if let chosenTier = tier(named: modelChoice) {
    guard let installed = installedModelDirectory(chosenTier) else {
        print("The \(chosenTier.title) model is not installed. Run: olmocr --download \(chosenTier.rawValue)")
        exit(1)
    }
    modelDirectory = installed
}

print("Loading model \(ModelStore.modelName(for: modelDirectory)) ...")
let loadStart = Date()
let engine = try await OCREngine.load(modelDirectory: modelDirectory)
print(String(format: "Model loaded in %.1f s", Date().timeIntervalSince(loadStart)))

for path in arguments {
    let url = URL(fileURLWithPath: path)
    let source: PageSource
    do {
        source = try PageSource(url: url)
    } catch {
        print("Skipping \(url.lastPathComponent): \(error.localizedDescription)")
        continue
    }
    let pages: [Int]
    if let pageRange {
        guard let parsed = parsePageRange(pageRange, pageCount: source.pageCount) else {
            print("Skipping \(url.lastPathComponent): page range \(pageRange) does not fit its \(source.pageCount) pages.")
            continue
        }
        pages = parsed
    } else {
        pages = Array(1...source.pageCount)
    }
    if source.hasEmbeddedText() {
        print("Note: \(url.lastPathComponent) already contains a text layer; transcribing anyway.")
    }

    if let imageFolder {
        try FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
        for page in pages {
            let image = try source.render(page: page)
            let name = url.deletingPathExtension().lastPathComponent + String(format: "_p%04d.png", page)
            try savePNG(image, to: imageFolder.appendingPathComponent(name))
        }
    }

    print("\(url.lastPathComponent): \(pages.count) of \(source.pageCount) pages")
    let plan = makeOutputPlan(
        source: source, outputFolder: outputFolder, formats: formats,
        model: await engine.modelName, modelRevision: await engine.modelRevision)
    let (results, run) = try await transcribeDocument(
        engine: engine, source: source, pages: pages, tokenLimit: tokenLimit,
        stopOnRepetition: stopOnRepetition
    ) { event in
        switch event {
        case .started, .tokens:
            break
        case .attempt(let attempt):
            if attempt.number > 1 {
                var line = "  p. \(attempt.page) attempt \(attempt.number) of \(attempt.total) at temperature \(attempt.temperature)"
                if attempt.rotation != 0 {
                    line += ", rotated \(attempt.rotation)°"
                }
                if let problem = attempt.previousProblem {
                    line += " (previous attempt: \(problem))"
                }
                print(line)
            }
        case .finished(let result, let index, let total, let fromCache):
            var line = String(format: "  p. %d (%d/%d) ", result.page, index + 1, total)
            if fromCache {
                line += "from cache"
            } else {
                line += String(format: "%.1f s, %d tokens, attempt %d", result.seconds, result.outputTokens, result.attempts)
            }
            if result.rotation != 0 {
                line += ", rotated \(result.rotation)°"
            }
            if result.needsChecking {
                line += " NEEDS CHECKING: \(result.problem ?? "")"
            }
            print(line)
            try? writePageFile(result, source: source, plan: plan)
        }
    }
    let exported = try writeOutputs(results: results, run: run, source: source, plan: plan)
    for file in exported.files {
        print("  wrote \(file.path)")
    }
}
