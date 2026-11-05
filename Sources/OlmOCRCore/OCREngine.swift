// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import CoreImage
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

public let olmOCRPrompt =
    "Attached is one page of a document that you must process. "
    + "Just return the plain text representation of this document as if you were reading it naturally. Convert equations to LateX and tables to HTML.\n"
    + "If there are any figures or charts, label them with the following markdown syntax ![Alt text describing the contents of the figure](page_startx_starty_width_height.png)\n"
    + "Return your output as markdown, with a front matter section on top specifying values for the primary_language, is_rotation_valid, rotation_correction, is_table, and is_diagram parameters."

public let promptVersion = "olmocr-v4-yaml-no-anchoring"
public let maxTokens = 8000
public let defaultTokenLimit = 6000
public let tokenLimitChoices = [4000, 6000, 8000]
public let modelMaxContext = 16384
public let modelMaxPixels = 12_845_056
public let temperatureByAttempt: [Float] = [0.1, 0.1, 0.2, 0.3, 0.5, 0.8, 0.9, 1.0]
public let maxAttempts = 8

public struct PageResponse: Codable, Sendable, Equatable {
    public var primaryLanguage: String?
    public var isRotationValid: Bool
    public var rotationCorrection: Int
    public var isTable: Bool
    public var isDiagram: Bool
    public var naturalText: String?
}

public struct PageResult: Codable, Sendable {
    public var page: Int
    public var response: PageResponse
    public var inputTokens: Int
    public var outputTokens: Int
    public var attempts: Int
    public var rotation: Int
    public var temperature: Float
    public var isFallback: Bool
    public var isValid: Bool
    public var needsChecking: Bool
    public var problem: String?
    public var seconds: Double
    public var finishedAt: Date? = nil
    public var tokenLimit: Int? = nil
    public var stopOnRepetition: Bool? = nil
}

public struct RawGeneration: Sendable {
    public var text: String
    public var promptTokens: Int
    public var outputTokens: Int
    public var tokensPerSecond: Double
    public var stoppedForRepetition = false
}

public let repetitionWindow = 1000
public let repetitionMaxUnit = 250

public func isRepeating(_ tokens: [Int]) -> Bool {
    let count = tokens.count
    guard count >= repetitionWindow else {
        return false
    }
    let start = count - repetitionWindow
    for unit in 1...repetitionMaxUnit {
        var periodic = true
        var index = start + unit
        while index < count {
            if tokens[index] != tokens[index - unit] {
                periodic = false
                break
            }
            index += 1
        }
        if periodic {
            return true
        }
    }
    return false
}

final class RepetitionFlag: @unchecked Sendable {
    var stopped = false
}

public func parseResponse(_ raw: String) -> PageResponse? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```") {
        var lines = text.components(separatedBy: "\n")
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        text = lines.joined(separator: "\n")
    }
    guard text.hasPrefix("---\n") else {
        return nil
    }
    let afterOpening = text.index(text.startIndex, offsetBy: 4)
    guard let closing = text.range(of: "\n---", range: afterOpening..<text.endIndex) else {
        return nil
    }
    var values: [String: String] = [:]
    for line in text[afterOpening..<closing.lowerBound].components(separatedBy: "\n") {
        let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2 {
            values[parts[0]] = parts[1]
        }
    }
    func bool(_ key: String) -> Bool? {
        switch values[key]?.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
    guard let language = values["primary_language"],
        let rotationValid = bool("is_rotation_valid"),
        let rotationText = values["rotation_correction"], let rotation = Int(rotationText),
        [0, 90, 180, 270].contains(rotation),
        let isTable = bool("is_table"),
        let isDiagram = bool("is_diagram")
    else {
        return nil
    }
    let noLanguage = ["", "null", "none", "~"].contains(language.lowercased())
    let body = String(text[closing.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    return PageResponse(
        primaryLanguage: noLanguage ? nil : language,
        isRotationValid: rotationValid,
        rotationCorrection: rotation,
        isTable: isTable,
        isDiagram: isDiagram,
        naturalText: body.isEmpty ? nil : body
    )
}

public struct PageAttempt: Sendable {
    public var page: Int
    public var number: Int
    public var total: Int
    public var temperature: Float
    public var rotation: Int
    public var previousProblem: String?
}

public actor OCREngine {
    public let modelDirectory: URL
    public let modelName: String
    public let modelRevision: String?
    private let container: ModelContainer
    private var attemptHandler: (@Sendable (PageAttempt) -> Void)?
    private var tokenHandler: (@Sendable (Int) -> Void)?
    private var tokenLimit = defaultTokenLimit
    private var stopOnRepetition = true
    private var lastProblem: String?

    private init(modelDirectory: URL, modelName: String, modelRevision: String?, container: ModelContainer) {
        self.modelDirectory = modelDirectory
        self.modelName = modelName
        self.modelRevision = modelRevision
        self.container = container
    }

    public static func load(modelDirectory: URL) async throws -> OCREngine {
        let prepared = try ModelStore.prepare(modelDirectory)
        Memory.cacheLimit = memoryCacheLimit(for: ModelStore.modelName(for: modelDirectory))
        let container = try await loadModelContainer(from: prepared, using: #huggingFaceTokenizerLoader())
        return OCREngine(
            modelDirectory: prepared,
            modelName: ModelStore.modelName(for: modelDirectory),
            modelRevision: readModelRevision(directory: modelDirectory),
            container: container)
    }

    public func transcribe(image: CIImage, temperature: Float, seed: UInt64) async throws -> RawGeneration {
        let parameters = GenerateParameters(maxTokens: tokenLimit, temperature: temperature, seed: seed)
        let onTokens = tokenHandler
        let checkRepetition = stopOnRepetition
        let flag = RepetitionFlag()
        let generation = try await container.perform { context in
            let messages: [MLXLMCommon.Message] = [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": olmOCRPrompt],
                        ["type": "image"],
                    ],
                ]
            ]
            let input = UserInput(
                prompt: .messages(messages),
                images: [UserInput.Image(source: .ciImage(image))],
                processing: .init(maxPixels: modelMaxPixels)
            )
            let prepared = try await context.processor.prepare(input: input)
            let result = try MLXLMCommon.generate(input: prepared, parameters: parameters, context: context) {
                (tokens: [Int]) -> GenerateDisposition in
                if tokens.count % 100 == 0 {
                    onTokens?(tokens.count)
                    if checkRepetition && isRepeating(tokens) {
                        flag.stopped = true
                        return .stop
                    }
                }
                return Task.isCancelled ? .stop : .more
            }
            return RawGeneration(
                text: result.output,
                promptTokens: result.promptTokenCount,
                outputTokens: result.generationTokenCount,
                tokensPerSecond: result.tokensPerSecond,
                stoppedForRepetition: flag.stopped
            )
        }
        Memory.clearCache()
        try Task.checkCancellation()
        return generation
    }

    func attempt(image: CIImage, page: Int, attempt: Int, rotation: Int) async throws -> PageResult? {
        let start = Date()
        let temperature = temperatureByAttempt[min(attempt, temperatureByAttempt.count - 1)]
        attemptHandler?(
            PageAttempt(
                page: page, number: attempt + 1, total: maxAttempts, temperature: temperature, rotation: rotation,
                previousProblem: lastProblem))
        let rotated = rotateCounterClockwise(image, degrees: rotation)
        let generation = try await transcribe(image: rotated, temperature: temperature, seed: UInt64(attempt))
        let runaway = generation.stoppedForRepetition
        guard let response = parseResponse(generation.text) else {
            if runaway {
                lastProblem = "the model started repeating itself"
            } else if generation.outputTokens >= tokenLimit {
                lastProblem = "hit the \(tokenLimit)-token limit (the model may be repeating itself)"
            } else {
                lastProblem = "answer could not be read"
            }
            return nil
        }
        let hitLimit = generation.outputTokens >= tokenLimit || runaway
        if runaway {
            lastProblem = "the model started repeating itself"
        } else if hitLimit {
            lastProblem = "hit the \(tokenLimit)-token limit (the model may be repeating itself)"
        } else if !response.isRotationValid {
            lastProblem = "page looked rotated by \(response.rotationCorrection)°"
        } else {
            lastProblem = nil
        }
        let tooLong = generation.promptTokens + generation.outputTokens > modelMaxContext
        return PageResult(
            page: page,
            response: response,
            inputTokens: generation.promptTokens,
            outputTokens: generation.outputTokens,
            attempts: attempt + 1,
            rotation: rotation,
            temperature: temperature,
            isFallback: false,
            isValid: !hitLimit && !tooLong,
            needsChecking: false,
            problem: runaway
                ? "Output was stopped because the model started repeating itself."
                : (hitLimit ? "Output was cut off (the model may have repeated itself)." : nil),
            seconds: Date().timeIntervalSince(start)
        )
    }

    public func processPage(
        image: CIImage, page: Int, fallbackText: String?,
        tokenLimit: Int = defaultTokenLimit,
        stopOnRepetition: Bool = true,
        onAttempt: (@Sendable (PageAttempt) -> Void)? = nil,
        onTokens: (@Sendable (Int) -> Void)? = nil
    ) async throws -> PageResult {
        self.tokenLimit = min(tokenLimit, maxTokens)
        self.stopOnRepetition = stopOnRepetition
        attemptHandler = onAttempt
        tokenHandler = onTokens
        lastProblem = nil
        defer {
            attemptHandler = nil
            tokenHandler = nil
        }
        let start = Date()
        var result = try await attempt(image: image, page: page, attempt: 0, rotation: 0)

        if let first = result, first.isValid, first.response.isRotationValid {
            return first
        }

        if let first = result, !first.response.isRotationValid {
            var rotation = first.response.rotationCorrection % 360
            for number in 1..<maxAttempts {
                result = try await attempt(image: image, page: page, attempt: number, rotation: rotation)
                if let current = result, current.isValid, current.response.isRotationValid {
                    return finish(current, start: start)
                }
                if let current = result {
                    rotation = (rotation + current.response.rotationCorrection) % 360
                }
            }
            if var last = result, last.isValid {
                last.needsChecking = true
                last.problem = "The model was unsure which way up the page is."
                return finish(last, start: start)
            }
            return fallback(page: page, fallbackText: fallbackText, lastResult: result, start: start)
        }

        for number in 1..<maxAttempts {
            result = try await attempt(image: image, page: page, attempt: number, rotation: 0)
            if let current = result, current.isValid, current.response.isRotationValid {
                return finish(current, start: start)
            }
        }
        if var last = result, last.isValid {
            last.needsChecking = true
            last.problem = "The model was unsure which way up the page is."
            return finish(last, start: start)
        }
        return fallback(page: page, fallbackText: fallbackText, lastResult: result, start: start)
    }

    func finish(_ result: PageResult, start: Date) -> PageResult {
        var finished = result
        finished.seconds = Date().timeIntervalSince(start)
        return finished
    }

    func fallback(page: Int, fallbackText: String?, lastResult: PageResult?, start: Date) -> PageResult {
        if let fallbackText {
            return PageResult(
                page: page,
                response: PageResponse(
                    primaryLanguage: nil, isRotationValid: true, rotationCorrection: 0,
                    isTable: false, isDiagram: false, naturalText: fallbackText),
                inputTokens: 0, outputTokens: 0, attempts: maxAttempts, rotation: 0, temperature: 0,
                isFallback: true, isValid: true, needsChecking: true,
                problem: "olmOCR could not read this page; the PDF's own embedded text was used instead.",
                seconds: Date().timeIntervalSince(start)
            )
        }
        if var last = lastResult {
            last.needsChecking = true
            last.isFallback = false
            last.problem = last.problem ?? "olmOCR could not read this page reliably."
            last.seconds = Date().timeIntervalSince(start)
            return last
        }
        return PageResult(
            page: page,
            response: PageResponse(
                primaryLanguage: nil, isRotationValid: true, rotationCorrection: 0,
                isTable: false, isDiagram: false, naturalText: nil),
            inputTokens: 0, outputTokens: 0, attempts: maxAttempts, rotation: 0, temperature: 0,
            isFallback: true, isValid: false, needsChecking: true,
            problem: "olmOCR could not read this page.",
            seconds: Date().timeIntervalSince(start)
        )
    }
}
