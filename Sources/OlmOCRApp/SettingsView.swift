// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import OlmOCRCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("outputLocation") private var outputLocation = OutputLocation.beside.rawValue
    @AppStorage("outputFolder") private var outputFolder = ""
    @AppStorage("format.markdown") private var markdown = true
    @AppStorage("format.text") private var text = false
    @AppStorage("format.pages") private var pages = false
    @AppStorage("format.jsonl") private var jsonl = false
    @AppStorage("format.manifest") private var manifest = false
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("tokenLimit") private var tokenLimit = defaultTokenLimit
    @AppStorage("stopOnRepetition") private var stopOnRepetition = true
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @State private var modelSizes: [ModelTier: Int64] = [:]
    @State private var savedPagesSize: Int64 = 0

    var body: some View {
        Form {
            Section("Save") {
                Picker("Location", selection: $outputLocation) {
                    Text("Next to original").tag(OutputLocation.beside.rawValue)
                    Text(outputFolder.isEmpty ? "Folder…" : URL(fileURLWithPath: outputFolder).lastPathComponent)
                        .tag(OutputLocation.folder.rawValue)
                }
                .onChange(of: outputLocation) { _, newValue in
                    if newValue == OutputLocation.folder.rawValue {
                        chooseFolder()
                    }
                }
                if outputLocation == OutputLocation.folder.rawValue {
                    LabeledContent("Folder") {
                        Button(outputFolder.isEmpty ? "Choose…" : (outputFolder as NSString).abbreviatingWithTildeInPath) {
                            chooseFolder()
                        }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                }
            }

            Section("Formats") {
                Toggle("Markdown", isOn: $markdown)
                Toggle("Plain text", isOn: $text)
                Toggle("One file per page", isOn: $pages)
                Toggle("JSONL", isOn: $jsonl)
                Toggle("Manifest", isOn: $manifest)
                    .help("A CSV file with one row per page, recording its status, the model and the settings used.")
            }

            Section {
                Picker("Model", selection: Binding(get: { model.selectedTier }, set: { model.switchTier($0) })) {
                    ForEach(model.report?.supportedTiers ?? [], id: \.self) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .disabled(model.queue.isRunning || model.phase != .ready)
                Picker("Page length limit", selection: $tokenLimit) {
                    Text("4,000 tokens").tag(4000)
                    Text("6,000 tokens").tag(6000)
                    Text("8,000 tokens (olmOCR default)").tag(8000)
                }
                .help("Stops a page that runs on too long, which usually means the model is repeating itself. Raise it if very dense pages, such as indexes, come back flagged as cut off.")
                Toggle("Stop pages that repeat themselves", isOn: $stopOnRepetition)
                    .help("Stops an attempt as soon as the model starts repeating the same text over and over, then tries again. Saves minutes on difficult pages. Turn off to match olmOCR exactly.")
            }

            Section("Storage") {
                ForEach(ModelTier.allCases, id: \.self) { tier in
                    if let size = modelSizes[tier], size > 0 {
                        LabeledContent("\(tier.title) model") {
                            HStack(spacing: 10) {
                                Text(formatBytes(size))
                                    .foregroundStyle(.secondary)
                                Button("Remove…") {
                                    removeModel(tier)
                                }
                                .disabled(!model.canChangeStorage)
                                .help(model.canChangeStorage
                                    ? "Delete this model from your Mac. You can download it again later."
                                    : "Not while transcribing or loading")
                            }
                        }
                    }
                }
                LabeledContent("Cached pages") {
                    HStack(spacing: 10) {
                        Text(formatBytes(savedPagesSize))
                            .foregroundStyle(.secondary)
                        Button("Clear…") {
                            clearSavedPages()
                        }
                        .disabled(!model.canChangeStorage || savedPagesSize == 0)
                        .help("Finished pages are kept so a stopped document can carry on. Clearing means documents are read again if you add them again. Your transcripts are not touched.")
                    }
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.open(ModelStore.applicationSupport)
                }
                .help("Open the folder where models and cached pages are kept")
            }

            Section {
                Toggle("Keep Mac awake while working", isOn: $keepAwake)
                Toggle("Check for updates", isOn: $checkForUpdates)
                    .help("Once a day, asks whether a new version of the app or model exists. Nothing is installed without asking, and your documents are never sent.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await refreshStorage()
        }
    }

    func refreshStorage() async {
        let sizes = await Task.detached(priority: .utility) {
            var found: [ModelTier: Int64] = [:]
            for tier in ModelTier.allCases {
                found[tier] = ModelStore.folderSize(ModelStore.modelFolder(tier))
            }
            return (found, ModelStore.folderSize(ModelStore.jobsDirectory))
        }.value
        modelSizes = sizes.0
        savedPagesSize = sizes.1
    }

    func removeModel(_ tier: ModelTier) {
        let installed = installedModelDirectory(tier) != nil
        let message = installed
            ? "It will be deleted from this Mac. You can download it again later."
            : "This is an unfinished download. It will be deleted from this Mac."
        guard confirmRemoval(title: "Remove the \(tier.title) model?", message: message, button: "Remove") else {
            return
        }
        do {
            try model.removeModel(tier)
        } catch {
            showError("Couldn’t remove the model", details: error.localizedDescription)
        }
        Task {
            await refreshStorage()
        }
    }

    func clearSavedPages() {
        guard confirmRemoval(
            title: "Clear cached pages?",
            message: "Your transcripts are not touched. Documents you add again will be read again from the start.",
            button: "Clear")
        else {
            return
        }
        do {
            try ModelStore.removeSavedPages()
        } catch {
            showError("Couldn’t clear cached pages", details: error.localizedDescription)
        }
        Task {
            await refreshStorage()
        }
    }

    func confirmRemoval(title: String, message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url.path
        } else if outputFolder.isEmpty {
            outputLocation = OutputLocation.beside.rawValue
        }
    }
}
