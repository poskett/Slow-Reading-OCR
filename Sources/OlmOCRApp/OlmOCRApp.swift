// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import OlmOCRCore
import SwiftUI

let appName = "Slow Reading"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let model = AppModel()
    static var openMainWindow: (() -> Void)?
    static var quitConfirmed = false
    static let closeGuard = WindowCloseGuard()

    static func confirmStopAndQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop transcribing and quit?"
        alert.informativeText = "Finished pages are kept. Add the same files again later to carry on."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Working")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["SLOWREADING_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        if let other = others.first {
            other.activate()
            NSApp.terminate(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppDelegate.model.queue.add(urls: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppDelegate.model
        guard model.isBusy else {
            return .terminateNow
        }
        if model.queue.isRunning && !AppDelegate.quitConfirmed && !AppDelegate.confirmStopAndQuit() {
            AppDelegate.openMainWindow?()
            return .terminateCancel
        }
        Task { @MainActor in
            await model.stopForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    nonisolated(unsafe) weak var original: NSWindowDelegate?

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard AppDelegate.model.queue.isRunning else {
            return original?.windowShouldClose?(sender) ?? true
        }
        if AppDelegate.confirmStopAndQuit() {
            AppDelegate.quitConfirmed = true
            NSApp.terminate(nil)
        }
        return false
    }
}

final class GuardedWindowView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.delegate !== AppDelegate.closeGuard else {
            return
        }
        AppDelegate.closeGuard.original = window.delegate
        window.delegate = AppDelegate.closeGuard
    }
}

struct WindowGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> GuardedWindowView {
        GuardedWindowView()
    }

    func updateNSView(_ view: GuardedWindowView, context: Context) {}
}

@main
struct OlmOCRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("transcriptTextSize") private var textSize = defaultTranscriptTextSize
    private var model: AppModel { AppDelegate.model }

    var body: some Scene {
        Window(appName, id: "main") {
            ContentView(model: model)
                .frame(minWidth: 880, minHeight: 520)
                .task {
                    if model.phase == .checking {
                        model.start()
                    }
                }
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(appName)") {
                    showAbout()
                }
                Button("Check for Updates…") {
                    Task {
                        await model.checkForUpdates(manual: true)
                    }
                }
                .disabled(model.phase != .ready)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    openFiles()
                }
                .keyboardShortcut("o")
                .disabled(model.phase != .ready)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Move Up") {
                    model.queue.moveSelected(by: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!model.queue.canMoveSelected(by: -1))
                Button("Move Down") {
                    model.queue.moveSelected(by: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!model.queue.canMoveSelected(by: 1))
                Button("Remove from Queue") {
                    if let item = model.queue.selectedItem {
                        model.queue.remove(item)
                    }
                }
                .disabled(model.queue.selectedItem == nil)
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Bigger Text") {
                    textSize = transcriptTextSizes.first { $0 > textSize } ?? textSize
                }
                .keyboardShortcut("+")
                .disabled(textSize >= transcriptTextSizes.last ?? textSize)
                Button("Smaller Text") {
                    textSize = transcriptTextSizes.last { $0 < textSize } ?? textSize
                }
                .keyboardShortcut("-")
                .disabled(textSize <= transcriptTextSizes.first ?? textSize)
                Button("Normal Text Size") {
                    textSize = defaultTranscriptTextSize
                }
                .keyboardShortcut("0")
                .disabled(textSize == defaultTranscriptTextSize)
                Divider()
            }
            CommandGroup(replacing: .help) {
                Button("Copy Diagnostic Information") {
                    let report = model.report ?? checkSystem()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        report.diagnosticText + "\nApp version: \(appVersion)", forType: .string)
                }
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }

    func showAbout() {
        AboutWindow.show()
    }

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.pdf, .image, .folder]
        if panel.runModal() == .OK {
            model.queue.add(urls: panel.urls)
        }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.phase == .ready {
                MainView(model: model)
            } else {
                SetupView(model: model)
            }
        }
        .background(WindowGuard())
        .onAppear {
            AppDelegate.openMainWindow = { openWindow(id: "main") }
        }
    }
}
