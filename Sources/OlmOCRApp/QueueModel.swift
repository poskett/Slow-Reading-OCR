// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import AppKit
import CoreImage
import Foundation
import Observation
import OlmOCRCore
import UserNotifications

enum DocumentStatus: Equatable {
    case waiting
    case running
    case paused
    case done
    case failed(String)
}

@MainActor
@Observable
final class DocumentItem: Identifiable {
    let id: UUID
    let url: URL
    var source: PageSource?
    var kind: SourceKind
    var pageCount: Int
    var sourceSize: Int64?
    var sourceModified: Date?
    var pages: [Int]
    var pageRangeText = ""
    var status: DocumentStatus = .waiting
    var results: [Int: PageResult] = [:]
    var currentPage: Int?
    var currentAttempt: PageAttempt?
    var pageStarted: Date?
    var attemptStarted: Date?
    var attemptTokens = 0
    var tokenLimit = defaultTokenLimit
    var outputFiles: [URL] = []
    var plan: OutputPlan?
    var lastRun: DocumentRun?
    var saveFailed = false
    var manifestStale = false
    var selectedPage: Int
    var followProgress = true
    var redo = false
    var resultsLoaded = true
    var savedPagesDone = 0
    var savedFlaggedPages: [Int] = []

    init(url: URL, source: PageSource) {
        self.id = UUID()
        self.url = url
        self.source = source
        self.kind = source.kind
        self.pageCount = source.pageCount
        let fingerprint = sourceFingerprint(url, kind: source.kind)
        self.sourceSize = fingerprint.size
        self.sourceModified = fingerprint.modified
        self.pages = Array(1...source.pageCount)
        self.selectedPage = 1
    }

    init(saved: SavedDocument) {
        self.id = saved.id
        self.url = URL(fileURLWithPath: saved.path)
        self.kind = saved.kind
        self.pageCount = saved.pageCount
        self.sourceSize = saved.sourceSize
        self.sourceModified = saved.sourceModified
        self.pages = saved.pages
        self.pageRangeText = saved.pageRangeText
        self.outputFiles = saved.outputPaths.map { URL(fileURLWithPath: $0) }
        self.plan = saved.plan
        self.lastRun = saved.lastRun
        self.saveFailed = saved.saveFailed
        self.selectedPage = saved.selectedPage
        self.redo = saved.redo
        self.resultsLoaded = false
        self.savedPagesDone = saved.pagesDone
        self.savedFlaggedPages = saved.flaggedPages
        switch saved.status {
        case "waiting": self.status = .waiting
        case "done": self.status = .done
        case "failed": self.status = .failed(saved.failure ?? "")
        default: self.status = .paused
        }
    }

    var saved: SavedDocument {
        var statusName = "paused"
        var failure: String?
        switch status {
        case .waiting: statusName = "waiting"
        case .done: statusName = "done"
        case .failed(let message):
            statusName = "failed"
            failure = message
        case .running, .paused: break
        }
        return SavedDocument(
            id: id, path: url.path, kind: kind, pageCount: pageCount, sourceSize: sourceSize,
            sourceModified: sourceModified, pages: pages, pageRangeText: pageRangeText, status: statusName,
            failure: failure, pagesDone: pagesDone, flaggedPages: pagesNeedingChecking,
            outputPaths: outputFiles.map(\.path), plan: plan, lastRun: lastRun, saveFailed: saveFailed,
            selectedPage: selectedPage, redo: redo)
    }

    func adopt(_ opened: PageSource) {
        source = opened
        let fingerprint = sourceFingerprint(url, kind: opened.kind)
        sourceSize = fingerprint.size
        sourceModified = fingerprint.modified
        if opened.pageCount != pageCount {
            pageCount = opened.pageCount
            pages = Array(1...opened.pageCount)
            pageRangeText = ""
            selectedPage = 1
        }
    }

    var name: String {
        url.lastPathComponent
    }

    var pagesDone: Int {
        resultsLoaded ? pages.filter { results[$0] != nil }.count : savedPagesDone
    }

    var pagesNeedingChecking: [Int] {
        resultsLoaded ? pages.filter { results[$0]?.needsChecking == true } : savedFlaggedPages
    }

    var isFailed: Bool {
        if case .failed = status {
            return true
        }
        return false
    }

    var fraction: Double {
        pages.isEmpty ? 0 : Double(pagesDone) / Double(pages.count)
    }

    var icon: String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .folder: return "folder"
        }
    }

    func applyPageRange(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            pages = Array(1...pageCount)
            pageRangeText = ""
            return true
        }
        guard let parsed = parsePageRange(trimmed, pageCount: pageCount) else {
            return false
        }
        pages = parsed
        pageRangeText = trimmed
        if !pages.contains(selectedPage), let first = pages.first {
            selectedPage = first
        }
        return true
    }
}

enum OutputLocation: String, CaseIterable {
    case beside
    case folder
}

@MainActor
@Observable
final class QueueModel {
    var items: [DocumentItem] = []
    var selection: DocumentItem.ID?
    var isRunning = false
    var isPausing = false
    var measuredSecondsPerPage: Double?
    var fallbackSecondsPerPage: Double?

    private var runTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var recentPageSeconds: [Double] = []
    private var continueAfterRemoval = false
    private var settledBeforeRun: Set<DocumentItem.ID> = []

    init() {
        let saved = loadSavedQueue()
        items = saved.documents.map { DocumentItem(saved: $0) }
        selection = items.contains { $0.id == saved.selection } ? saved.selection : items.first?.id
        removeUnusedResults(keeping: Set(items.map(\.id)))
    }

    func saveQueue() {
        writeSavedQueue(SavedQueue(selection: selection, documents: items.map(\.saved)))
    }

    private func saveResults(_ item: DocumentItem) {
        guard item.resultsLoaded, !item.results.isEmpty, items.contains(where: { $0.id == item.id }) else {
            return
        }
        writeSavedResults(Array(item.results.values), id: item.id)
    }

    func loadResults(_ item: DocumentItem) async {
        guard !item.resultsLoaded else {
            return
        }
        let id = item.id
        let loaded = await Task.detached(priority: .userInitiated) {
            loadSavedResults(id)
        }.value
        guard !item.resultsLoaded else {
            return
        }
        for result in loaded {
            item.results[result.page] = result
        }
        item.resultsLoaded = true
    }

    func prepareSource(_ item: DocumentItem) async -> ScanProblem? {
        if item.source != nil && !item.redo {
            return nil
        }
        let url = item.url
        let kind = item.kind
        let pageCount = item.pageCount
        let size = item.sourceSize
        let modified = item.sourceModified
        let opened = await Task.detached(priority: .userInitiated) {
            openSavedSource(url: url, kind: kind, pageCount: pageCount, size: size, modified: modified)
        }.value
        if let source = opened.source, opened.problem == nil || item.redo {
            item.adopt(source)
            return nil
        }
        if item.source != nil && opened.problem == .locked {
            return nil
        }
        return opened.problem
    }

    var selectedItem: DocumentItem? {
        items.first { $0.id == selection }
    }

    var pagesRemaining: Int {
        items.filter { $0.status != .done && !$0.isFailed }.reduce(0) { $0 + $1.pages.count - $1.pagesDone }
    }

    var hasPausedItems: Bool {
        items.contains { $0.status == .paused }
    }

    var hasWork: Bool {
        items.contains { $0.status == .waiting || $0.status == .paused }
    }

    func add(urls: [URL]) {
        let expanded = expandInputs(urls)
        if expanded.count > 50
            && !confirm(
                title: "Add \(expanded.count) documents?",
                message: "The folders you added contain \(expanded.count) PDFs, images or image folders.",
                button: "Add All")
        {
            return
        }
        var candidates: [(url: URL, source: PageSource, hasText: Bool)] = []
        var problems: [String] = []
        var alreadyQueued: DocumentItem?
        for url in expanded {
            if let existing = items.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                alreadyQueued = alreadyQueued ?? existing
                continue
            }
            if candidates.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                continue
            }
            switch openSource(url) {
            case .opened(let source):
                candidates.append((url, source, source.hasEmbeddedText()))
            case .failed(let message):
                problems.append(message)
            case .skipped:
                continue
            }
        }
        let outputFolder = OutputSettings.current().outputFolder
        let transcribed = candidates.compactMap { candidate -> (url: URL, transcript: URL)? in
            existingTranscripts(for: candidate.source, outputFolder: outputFolder).first
                .map { (candidate.url, $0) }
        }
        var redoURLs: Set<URL> = []
        if !transcribed.isEmpty {
            if askAboutTranscribed(transcribed) {
                redoURLs = Set(transcribed.map(\.url))
            } else {
                let skipped = Set(transcribed.map(\.url))
                candidates.removeAll { skipped.contains($0.url) }
            }
        }
        let withText = candidates.filter { $0.hasText && !redoURLs.contains($0.url) }
        var includeText = true
        if !withText.isEmpty {
            let title = withText.count == 1
                ? "“\(withText[0].url.lastPathComponent)” already contains text"
                : "\(withText.count) PDFs already contain text"
            let message = withText.count == 1
                ? "Transcribe it anyway?"
                : nameList(withText.map { $0.url.lastPathComponent }) + "\n\nTranscribe them anyway?"
            includeText = confirm(title: title, message: message, button: "Transcribe")
        }
        var added: DocumentItem?
        for candidate in candidates
        where includeText || !candidate.hasText || redoURLs.contains(candidate.url) {
            let item = DocumentItem(url: candidate.url, source: candidate.source)
            item.redo = redoURLs.contains(candidate.url)
            items.append(item)
            added = added ?? item
        }
        if let chosen = added ?? alreadyQueued {
            selection = chosen.id
        }
        saveQueue()
        if problems.count == 1 {
            showError(problems[0])
        } else if problems.count > 1 {
            showError("\(problems.count) items couldn’t be added", details: nameList(problems))
        }
    }

    private func askAboutTranscribed(_ transcribed: [(url: URL, transcript: URL)]) -> Bool {
        let warning = "Transcribing again replaces the existing transcript, including any corrections you made to it."
        if transcribed.count == 1 {
            let choice = chooseAlert(
                title: "“\(transcribed[0].url.lastPathComponent)” is already transcribed", message: warning,
                buttons: ["Open Transcript", "Transcribe Again", "Cancel"])
            if choice == 0 {
                NSWorkspace.shared.open(transcribed[0].transcript)
            }
            return choice == 1
        }
        let names = nameList(transcribed.map { $0.url.lastPathComponent })
        return chooseAlert(
            title: "\(transcribed.count) documents are already transcribed", message: names + "\n\n" + warning,
            buttons: ["Skip These", "Transcribe Again"]) == 1
    }

    func transcribeAgain(_ item: DocumentItem) {
        if item.source == nil {
            let opened = openSavedSource(
                url: item.url, kind: item.kind, pageCount: item.pageCount, size: item.sourceSize,
                modified: item.sourceModified)
            guard opened.source != nil else {
                showError((opened.problem ?? .missing).rawValue)
                return
            }
        }
        guard chooseAlert(
            title: "Transcribe “\(item.name)” again?",
            message: "This replaces the existing transcript, including any corrections you made to it.",
            buttons: ["Transcribe Again", "Cancel"]) == 0
        else {
            return
        }
        removeSavedResults(item.id)
        item.results = [:]
        item.resultsLoaded = true
        item.outputFiles = []
        item.plan = nil
        item.lastRun = nil
        item.saveFailed = false
        item.followProgress = true
        item.redo = true
        item.status = .waiting
        saveQueue()
    }

    enum OpenResult {
        case opened(PageSource)
        case failed(String)
        case skipped
    }

    func openSource(_ url: URL) -> OpenResult {
        do {
            return .opened(try PageSource(url: url))
        } catch PageSourceError.encrypted {
            var password = askPassword(for: url.lastPathComponent)
            while let attempt = password {
                if let source = try? PageSource(url: url, password: attempt) {
                    return .opened(source)
                }
                password = askPassword(for: url.lastPathComponent, retry: true)
            }
            return .skipped
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func stopAndWait() async {
        guard let task = runTask else {
            return
        }
        continueAfterRemoval = false
        isPausing = true
        task.cancel()
        await task.value
    }

    func saveElsewhere(_ item: DocumentItem) {
        guard let plan = item.plan, let run = item.lastRun else {
            return
        }
        guard let source = item.source else {
            showError(ScanProblem.missing.rawValue)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose a folder for the transcript of “\(item.name)”."
        guard panel.runModal() == .OK, let folder = panel.url else {
            return
        }
        let newPlan = makeOutputPlan(
            source: source, outputFolder: folder, formats: plan.formats,
            model: plan.model, modelRevision: plan.modelRevision)
        let results = item.pages.compactMap { item.results[$0] }
        do {
            item.outputFiles = try writeOutputs(results: results, run: run, source: source, plan: newPlan).files
            item.plan = newPlan
            item.saveFailed = false
            item.status = .done
            saveQueue()
        } catch {
            showError("Couldn’t save there either", details: error.localizedDescription)
        }
    }

    func remove(_ item: DocumentItem) {
        if item.status == .running {
            continueAfterRemoval = !isPausing
            pause()
        }
        items.removeAll { $0.id == item.id }
        removeSavedResults(item.id)
        if selection == item.id {
            selection = items.first?.id
        }
        saveQueue()
    }

    var hasFinished: Bool {
        items.contains { $0.status == .done }
    }

    func clearFinished() {
        for item in items where item.status == .done {
            removeSavedResults(item.id)
        }
        items.removeAll { $0.status == .done }
        if !items.contains(where: { $0.id == selection }) {
            selection = items.first?.id
        }
        saveQueue()
    }

    func moveSelected(by step: Int) {
        guard let item = selectedItem else {
            return
        }
        move(item, by: step)
    }

    func move(_ item: DocumentItem, by step: Int) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
            items.indices.contains(index + step)
        else {
            return
        }
        items.swapAt(index, index + step)
        saveQueue()
    }

    func moveItems(from offsets: IndexSet, to destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
        saveQueue()
    }

    func canMoveSelected(by step: Int) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == selection }) else {
            return false
        }
        return items.indices.contains(index + step)
    }

    func start(engine: OCREngine, settings: OutputSettings) {
        guard !isRunning else {
            return
        }
        for item in items where item.status == .paused {
            item.status = .waiting
        }
        settledBeforeRun = Set(items.filter { $0.status == .done || $0.isFailed }.map(\.id))
        isRunning = true
        isPausing = false
        requestNotificationPermission()
        activity = ProcessInfo.processInfo.beginActivity(
            options: settings.keepAwake ? [.userInitiated, .idleSystemSleepDisabled] : [.userInitiated],
            reason: "Transcribing documents")
        runTask = Task {
            while let item = self.items.first(where: { $0.status == .waiting }) {
                await self.process(item, engine: engine, settings: OutputSettings.current())
                if Task.isCancelled {
                    break
                }
            }
            self.finishRun()
            if self.continueAfterRemoval {
                self.continueAfterRemoval = false
                if self.hasWork {
                    self.start(engine: engine, settings: OutputSettings.current())
                }
            }
        }
    }

    func pause() {
        guard isRunning, !isPausing else {
            return
        }
        isPausing = true
        runTask?.cancel()
    }

    private func finishRun() {
        isRunning = false
        isPausing = false
        runTask = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        if hasPausedItems && !continueAfterRemoval {
            announce("Paused")
        }
        let settled = items.filter { !settledBeforeRun.contains($0.id) }
        let finished = settled.filter { $0.status == .done }.count
        let failed = settled.filter(\.isFailed).count
        if !hasWork && finished + failed > 0 && !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
            var body = finished == 1 ? "1 document is ready." : "\(finished) documents are ready."
            if failed > 0 {
                body += failed == 1 ? " 1 had a problem." : " \(failed) had problems."
            }
            postNotification(title: "Transcription finished", body: body)
        }
    }

    private func process(_ item: DocumentItem, engine: OCREngine, settings: OutputSettings) async {
        item.status = .running
        defer {
            saveResults(item)
            saveQueue()
        }
        await loadResults(item)
        let problem = await prepareSource(item)
        guard let source = item.source, problem == nil else {
            item.status = .failed((problem ?? .missing).rawValue)
            return
        }
        let modelName = await engine.modelName
        let modelRevision = await engine.modelRevision
        if item.redo {
            try? FileManager.default.removeItem(
                at: cacheDirectory(for: source, modelName: modelName + (modelRevision ?? "")))
            item.redo = false
        }
        let pages = item.pages
        let plan = makeOutputPlan(
            source: source, outputFolder: settings.outputFolder, formats: settings.formats,
            model: modelName, modelRevision: modelRevision)
        item.plan = plan
        item.tokenLimit = settings.tokenLimit
        let tokenLimit = settings.tokenLimit
        let stopOnRepetition = settings.stopOnRepetition
        item.saveFailed = false
        do {
            let (results, run) = try await transcribeDocument(
                engine: engine, source: source, pages: pages, tokenLimit: tokenLimit,
                stopOnRepetition: stopOnRepetition
            ) { event in
                Task { @MainActor in
                    self.handle(event, item: item)
                }
            }
            for result in results {
                item.results[result.page] = result
            }
            item.currentPage = nil
            item.lastRun = run
            do {
                item.outputFiles = try await Task.detached {
                    try writeOutputs(results: results, run: run, source: source, plan: plan).files
                }.value
                item.manifestStale = false
                item.status = .done
                let flagged = item.pagesNeedingChecking.count
                announce(
                    flagged == 0
                        ? "\(item.name) finished"
                        : "\(item.name) finished. \(pagesText(flagged)) to check.")
            } catch {
                removeIfEmpty(plan.folder)
                item.saveFailed = true
                item.status = .failed(error.localizedDescription)
                announce("Couldn’t save \(item.name)")
            }
        } catch is CancellationError {
            item.currentPage = nil
            item.status = .paused
            saveProgress(item)
        } catch {
            item.currentPage = nil
            item.status = Task.isCancelled ? .paused : .failed(error.localizedDescription)
            if !Task.isCancelled {
                announce("\(item.name) failed")
            }
        }
    }

    private func handle(_ event: PageEvent, item: DocumentItem) {
        switch event {
        case .started(let page, _, _):
            item.currentPage = page
            item.currentAttempt = nil
            item.pageStarted = Date()
            item.attemptStarted = Date()
            item.attemptTokens = 0
            if item.manifestStale {
                saveProgress(item)
            }
        case .attempt(let attempt):
            item.currentAttempt = attempt
            item.attemptStarted = Date()
            item.attemptTokens = 0
        case .tokens(_, let count):
            item.attemptTokens = count
        case .finished(let result, _, _, let fromCache):
            item.results[result.page] = result
            item.currentAttempt = nil
            item.pageStarted = nil
            item.attemptStarted = nil
            item.attemptTokens = 0
            if let plan = item.plan, let source = item.source {
                try? writePageFile(result, source: source, plan: plan, onlyIfMissing: fromCache)
                if fromCache {
                    item.manifestStale = true
                } else {
                    saveProgress(item)
                }
            }
            if item.followProgress {
                item.selectedPage = result.page
            }
            if !fromCache {
                recentPageSeconds.append(result.seconds)
                if recentPageSeconds.count > 10 {
                    recentPageSeconds.removeFirst()
                }
                let sorted = recentPageSeconds.sorted()
                measuredSecondsPerPage = sorted[sorted.count / 2]
            }
        }
    }

    private func saveProgress(_ item: DocumentItem) {
        guard let plan = item.plan, let source = item.source else {
            return
        }
        let results = item.pages.compactMap { item.results[$0] }
        guard !results.isEmpty else {
            return
        }
        try? writeManifest(results, source: source, plan: plan)
        item.manifestStale = false
    }

    var retryingItem: DocumentItem? {
        items.first { $0.status == .running && ($0.currentAttempt?.number ?? 1) > 1 }
    }

    var perPageSeconds: Double? {
        measuredSecondsPerPage ?? fallbackSecondsPerPage
    }

    func forgetMeasuredSpeed() {
        recentPageSeconds = []
        measuredSecondsPerPage = nil
    }

    func isSlowAttempt(_ item: DocumentItem) -> Bool {
        guard let started = item.attemptStarted, let perPage = perPageSeconds else {
            return false
        }
        return Date().timeIntervalSince(started) > max(perPage * 2, 60)
    }

    func currentPageSeconds(_ item: DocumentItem, perPage: Double) -> Double {
        let now = Date()
        if let started = item.attemptStarted, item.attemptTokens > 0, isSlowAttempt(item) {
            let tokensPerSecond = Double(item.attemptTokens) / now.timeIntervalSince(started)
            return Double(max(item.tokenLimit - item.attemptTokens, 0)) / tokensPerSecond
        }
        if let attempt = item.currentAttempt, attempt.number > 1, let started = item.pageStarted {
            let failedAttemptSeconds = now.timeIntervalSince(started) / Double(attempt.number - 1)
            return max(failedAttemptSeconds, perPage)
        }
        if let started = item.attemptStarted {
            return max(perPage - now.timeIntervalSince(started), 0)
        }
        return perPage
    }

    func remainingSeconds(for item: DocumentItem, perPage: Double) -> Double {
        let pages = item.pages.count - item.pagesDone
        guard pages > 0 else {
            return 0
        }
        if item.status == .running && item.currentPage != nil {
            return Double(pages - 1) * perPage + currentPageSeconds(item, perPage: perPage)
        }
        return Double(pages) * perPage
    }

    func remainingText() -> String? {
        guard pagesRemaining > 0, let perPage = perPageSeconds else {
            return nil
        }
        let seconds = items.filter { $0.status != .done && !$0.isFailed }
            .reduce(0) { $0 + remainingSeconds(for: $1, perPage: perPage) }
        return durationText(seconds)
    }

    func remainingText(for item: DocumentItem) -> String? {
        guard item.pages.count > item.pagesDone, let perPage = perPageSeconds else {
            return nil
        }
        return durationText(remainingSeconds(for: item, perPage: perPage))
    }
}

struct OutputSettings: Sendable {
    var formats: [OutputFormat]
    var outputFolder: URL?
    var keepAwake: Bool
    var tokenLimit: Int
    var stopOnRepetition: Bool

    static func current() -> OutputSettings {
        let defaults = UserDefaults.standard
        var formats: [OutputFormat] = []
        if defaults.object(forKey: "format.markdown") as? Bool ?? true { formats.append(.markdown) }
        if defaults.bool(forKey: "format.text") { formats.append(.text) }
        if defaults.object(forKey: "format.pages") as? Bool ?? true { formats.append(.pages) }
        if defaults.bool(forKey: "format.jsonl") { formats.append(.jsonl) }
        if formats.isEmpty { formats = [.markdown] }
        if defaults.bool(forKey: "format.manifest") { formats.append(.manifest) }
        let location = OutputLocation(rawValue: defaults.string(forKey: "outputLocation") ?? "") ?? .beside
        let folderPath = defaults.string(forKey: "outputFolder")
        let folder = location == .folder ? folderPath.map { URL(fileURLWithPath: $0, isDirectory: true) } : nil
        let keepAwake = defaults.object(forKey: "keepAwake") as? Bool ?? true
        let storedLimit = defaults.integer(forKey: "tokenLimit")
        let tokenLimit = tokenLimitChoices.contains(storedLimit) ? storedLimit : defaultTokenLimit
        let stopOnRepetition = defaults.object(forKey: "stopOnRepetition") as? Bool ?? true
        return OutputSettings(
            formats: formats, outputFolder: folder, keepAwake: keepAwake, tokenLimit: tokenLimit,
            stopOnRepetition: stopOnRepetition)
    }
}

@MainActor
func confirm(title: String, message: String, button: String) -> Bool {
    chooseAlert(title: title, message: message, buttons: [button, "Skip"]) == 0
}

@MainActor
func chooseAlert(title: String, message: String, buttons: [String]) -> Int {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    for button in buttons {
        alert.addButton(withTitle: button)
    }
    return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
}

@MainActor
func askPassword(for name: String, retry: Bool = false) -> String? {
    let alert = NSAlert()
    alert.messageText = retry ? "Wrong password" : "“\(name)” is protected"
    alert.informativeText = "Enter the password to open it."
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    alert.accessoryView = field
    alert.addButton(withTitle: "Open")
    alert.addButton(withTitle: "Skip")
    alert.window.initialFirstResponder = field
    return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
}

@MainActor
func showError(_ message: String, details: String = "") {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = details
    alert.alertStyle = .warning
    alert.runModal()
}

func nameList(_ names: [String], limit: Int = 8) -> String {
    var lines = Array(names.prefix(limit))
    if names.count > limit {
        lines.append("and \(names.count - limit) more")
    }
    return lines.joined(separator: "\n")
}

func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
}

func resolveAlias(_ url: URL) -> URL {
    (try? URL(resolvingAliasFileAt: url)) ?? url
}

func expandInputs(_ urls: [URL]) -> [URL] {
    urls.flatMap { expandInput(resolveAlias($0), depth: 0) }
}

func expandInput(_ url: URL, depth: Int) -> [URL] {
    guard isDirectory(url), PageSource.imageFiles(in: url).isEmpty, depth < 4 else {
        return [url]
    }
    let entries = ((try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    var found: [URL] = []
    for entry in entries {
        if isDirectory(entry) {
            let inner = expandInput(entry, depth: depth + 1)
            if inner != [entry] || !PageSource.imageFiles(in: entry).isEmpty {
                found.append(contentsOf: inner)
            }
        } else if entry.pathExtension.lowercased() == "pdf" {
            found.append(entry)
        }
    }
    return found.isEmpty ? [url] : found
}

func removeIfEmpty(_ folder: URL) {
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? ["x"]
    if contents.isEmpty {
        try? FileManager.default.removeItem(at: folder)
    }
}

func pageImage(source: PageSource, page: Int) async -> NSImage? {
    await Task.detached(priority: .userInitiated) {
        guard let image = try? source.render(page: page, longestSide: 1800) else {
            return nil
        }
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }.value
}

func durationText(_ seconds: Double) -> String {
    if seconds < 60 {
        return "under a minute"
    }
    if seconds < 3600 {
        return "about \(Int((seconds / 60).rounded())) min"
    }
    let hours = Int(seconds / 3600)
    let minutes = Int((seconds - Double(hours) * 3600) / 60)
    return "about \(hours) h \(minutes) min"
}

func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
}

func postNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}

@MainActor
func announce(_ text: String) {
    NSAccessibility.post(
        element: NSApp as Any, notification: .announcementRequested,
        userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
}

func pagesText(_ count: Int) -> String {
    count == 1 ? "1 page" : "\(count) pages"
}
