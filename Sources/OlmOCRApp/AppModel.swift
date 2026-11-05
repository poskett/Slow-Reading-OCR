// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import AppKit
import CoreImage
import Foundation
import Observation
import OlmOCRCore

enum SetupPhase: Equatable {
    case checking
    case blocked(String)
    case needsModel
    case downloading
    case importing
    case testing
    case ready
    case failed(String)
}

@MainActor
@Observable
final class AppModel {
    var phase: SetupPhase = .checking
    var report: SystemReport?
    var selectedTier: ModelTier = .compact
    var downloadProgress: DownloadProgress?
    var testMessage = ""
    var testDetail = ""
    var testFraction: Double?
    var stepStarted = Date()
    var modelDamaged = false
    var loadError: String?
    var secondsPerPage: Double? {
        didSet {
            queue.fallbackSecondsPerPage = secondsPerPage
        }
    }
    var engine: OCREngine?
    let queue = QueueModel()

    private var setupTask: Task<Void, Never>?

    var isBusy: Bool {
        queue.isRunning || phase == .testing
    }

    func stopForQuit() async {
        if phase == .testing, let setupTask {
            setupTask.cancel()
            await setupTask.value
        }
        await queue.stopAndWait()
    }
    private var activity: NSObjectProtocol?

    private let defaults = UserDefaults.standard

    func start() {
        let report = checkSystem()
        self.report = report
        if let problem = report.blockingProblem {
            phase = .blocked(problem)
            return
        }
        let saved = defaults.string(forKey: "selectedTier").flatMap(ModelTier.init(rawValue:))
        if let saved, report.supportedTiers.contains(saved) {
            selectedTier = saved
        } else if let recommended = report.recommendedTier {
            selectedTier = recommended
        }
        if installedModelDirectory(selectedTier) == nil,
            let installed = report.supportedTiers.first(where: { installedModelDirectory($0) != nil })
        {
            selectedTier = installed
        }
        let storedSpeed = defaults.double(forKey: "secondsPerPage.\(selectedTier.rawValue)")
        secondsPerPage = storedSpeed > 0 ? storedSpeed : nil
        if let directory = installedModelDirectory(selectedTier) {
            loadAndTest(directory: directory, runTest: secondsPerPage == nil)
        } else {
            phase = .needsModel
        }
    }

    func chooseTier(_ tier: ModelTier) {
        selectedTier = tier
        modelDamaged = false
        queue.forgetMeasuredSpeed()
        defaults.set(tier.rawValue, forKey: "selectedTier")
        let storedSpeed = defaults.double(forKey: "secondsPerPage.\(tier.rawValue)")
        secondsPerPage = storedSpeed > 0 ? storedSpeed : nil
    }

    func switchTier(_ tier: ModelTier) {
        guard tier != selectedTier, !queue.isRunning else {
            return
        }
        chooseTier(tier)
        engine = nil
        if let directory = installedModelDirectory(tier) {
            loadAndTest(directory: directory, runTest: secondsPerPage == nil)
        } else {
            phase = .needsModel
        }
    }

    var canChangeStorage: Bool {
        !isBusy && phase != .downloading && phase != .importing
    }

    func removeModel(_ tier: ModelTier) throws {
        guard canChangeStorage else {
            return
        }
        try ModelStore.removeModelFiles(tier)
        guard tier == selectedTier else {
            return
        }
        engine = nil
        modelDamaged = false
        if let directory = installedModelDirectory(tier) {
            loadAndTest(directory: directory, runTest: secondsPerPage == nil)
        } else {
            phase = .needsModel
        }
    }

    var isModelInstalled: Bool {
        installedModelDirectory(selectedTier) != nil
    }

    func useInstalledModel() {
        guard let directory = installedModelDirectory(selectedTier) else {
            phase = .needsModel
            return
        }
        defaults.set(selectedTier.rawValue, forKey: "selectedTier")
        loadAndTest(directory: directory, runTest: secondsPerPage == nil)
    }

    func download() {
        let tier = selectedTier
        let repair = modelDamaged
        modelDamaged = false
        defaults.set(tier.rawValue, forKey: "selectedTier")
        phase = .downloading
        downloadProgress = nil
        beginActivity("Downloading the olmOCR model")
        setupTask = Task {
            do {
                let folder = try await downloadModel(tier, repair: repair) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                self.endActivity()
                self.loadAndTest(directory: folder, runTest: true)
            } catch is CancellationError {
                self.endActivity()
                self.phase = .needsModel
            } catch let error as URLError where error.code == .cancelled {
                self.endActivity()
                self.phase = .needsModel
            } catch {
                self.endActivity()
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func pauseDownload() {
        setupTask?.cancel()
    }

    var hasPartialDownload: Bool {
        let folder = ModelStore.modelsDirectory.appendingPathComponent(selectedTier.folderName)
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return !items.isEmpty && !isModelInstalled
    }

    func importModel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing the \(selectedTier.folderName) model files."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let source = panel.url else {
            return
        }
        let tier = selectedTier
        defaults.set(tier.rawValue, forKey: "selectedTier")
        phase = .importing
        setupTask = Task {
            do {
                let folder = try await Task.detached(priority: .userInitiated) {
                    try ModelStore.importModel(from: source, tier: tier)
                }.value
                self.loadAndTest(directory: folder, runTest: true)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func loadAndTest(directory: URL, runTest: Bool) {
        phase = .testing
        testMessage = "Preparing…"
        testDetail = "Loading the model into memory"
        testFraction = nil
        stepStarted = Date()
        let tier = selectedTier
        setupTask = Task {
            do {
                let engine: OCREngine
                do {
                    engine = try await OCREngine.load(modelDirectory: directory)
                } catch {
                    self.loadError = error.localizedDescription
                    self.modelDamaged = true
                    self.phase = .failed("The model files look damaged. Repair downloads only the damaged files.")
                    return
                }
                self.engine = engine
                if runTest {
                    self.testMessage = "Testing transcription speed…"
                    self.testDetail = "Reading a sample page. This only happens once."
                    self.testFraction = 0
                    self.stepStarted = Date()
                    let seconds = try await runSelfTest(engine: engine) { fraction in
                        Task { @MainActor in
                            self.testFraction = max(self.testFraction ?? 0, fraction)
                        }
                    }
                    if seconds > 0 {
                        self.secondsPerPage = seconds
                        self.defaults.set(seconds, forKey: "secondsPerPage.\(tier.rawValue)")
                    }
                }
                self.phase = .ready
                self.checkForUpdatesIfDue()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func retry() {
        start()
    }

    func beginActivity(_ reason: String) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: reason)
    }

    func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }
}

func resourceURL(_ name: String) -> URL? {
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources")
}

struct SelfTestError: LocalizedError {
    var errorDescription: String? {
        "The model loaded but produced no text on the sample page. Try again, or choose the other model."
    }
}

let sampleExpectedTokens = 650

func runSelfTest(engine: OCREngine, onProgress: @escaping @Sendable (Double) -> Void) async throws -> Double {
    guard let imageURL = resourceURL("sample_page.png"), let image = CIImage(contentsOf: imageURL) else {
        return 0
    }
    let start = Date()
    let result = try await engine.processPage(
        image: image, page: 1, fallbackText: nil,
        onTokens: { count in
            onProgress(min(Double(count) / Double(sampleExpectedTokens), 0.97))
        })
    guard let text = result.response.naturalText, !text.isEmpty else {
        throw SelfTestError()
    }
    return Date().timeIntervalSince(start)
}
