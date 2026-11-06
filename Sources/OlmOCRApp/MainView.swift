// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import OlmOCRCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false

    var queue: QueueModel { model.queue }

    var body: some View {
        Group {
            if queue.items.isEmpty {
                DropZone(isTargeted: isTargeted) {
                    chooseFiles()
                }
                .navigationTitle("")
                .toolbarBackground(.hidden, for: .windowToolbar)
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
                } detail: {
                    if let item = queue.selectedItem {
                        DocumentDetailView(item: item, queue: queue)
                            .id(item.id)
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(urls: urls)
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .toolbar {
            if !queue.items.isEmpty {
                ToolbarItem(placement: .principal) {
                    statusText
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        chooseFiles()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .help("Add PDFs, images or folders (⌘O)")
                    runButton
                }
            }
        }
    }

    var sidebar: some View {
        List(selection: Bindable(queue).selection) {
            Section("Queue") {
            ForEach(queue.items) { item in
                DocumentRow(
                    item: item,
                    pausing: queue.isPausing,
                    remaining: queue.remainingText(for: item)
                )
                .tag(item.id)
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.outputFiles.first ?? item.url])
                        }
                        if item.status == .done {
                            Button("Transcribe Again") {
                                queue.transcribeAgain(item)
                            }
                        }
                        Divider()
                        Button("Remove", role: .destructive) {
                            queue.remove(item)
                        }
                        Button("Clear Finished") {
                            queue.clearFinished()
                        }
                        .disabled(!queue.hasFinished)
                    }
                    .accessibilityAction(named: "Move Up") {
                        queue.move(item, by: -1)
                    }
                    .accessibilityAction(named: "Move Down") {
                        queue.move(item, by: 1)
                    }
                    .accessibilityAction(named: "Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.outputFiles.first ?? item.url])
                    }
                    .accessibilityAction(named: "Remove") {
                        queue.remove(item)
                    }
            }
            .onMove { from, to in
                queue.moveItems(from: from, to: to)
            }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if let item = queue.selectedItem {
                queue.remove(item)
            }
        }
    }

    @ViewBuilder
    var statusText: some View {
        if queue.isPausing {
            Text("Pausing…")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if queue.isRunning {
            HStack(spacing: 6) {
                if let remaining = queue.remainingText() {
                    Text(pagesText(queue.pagesRemaining))
                    Text("·")
                        .accessibilityHidden(true)
                    Text("\(remaining) left")
                } else {
                    Text("\(pagesText(queue.pagesRemaining)) left")
                }
                if let retrying = queue.retryingItem, let attempt = retrying.currentAttempt {
                    Text("·")
                        .accessibilityHidden(true)
                    Text("Attempt \(attempt.number) of \(attempt.total)")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .help("Estimated time to finish all documents. It grows if a page needs extra attempts.")
            .accessibilityElement(children: .combine)
        } else if queue.hasPausedItems {
            Text("Paused · \(pagesText(queue.pagesRemaining)) left")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help("Press Resume to carry on. Finished pages are kept.")
        }
    }

    @ViewBuilder
    var runButton: some View {
        if queue.isPausing {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 6)
                .help("Finishing the current step, then pausing")
                .accessibilityLabel("Pausing")
        } else if queue.isRunning {
            Button {
                queue.pause()
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .help("Pause (⌘↩). Pages are saved as they finish.")
            .keyboardShortcut(.return, modifiers: .command)
        } else {
            Button {
                if let engine = model.engine {
                    queue.start(engine: engine, settings: OutputSettings.current())
                }
            } label: {
                Label(queue.hasPausedItems ? "Resume" : "Start", systemImage: "play.fill")
            }
            .help(queue.hasPausedItems ? "Resume transcribing (⌘↩)" : "Start transcribing (⌘↩)")
            .disabled(!queue.hasWork || model.engine == nil)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.pdf, .image, .folder]
        if panel.runModal() == .OK {
            queue.add(urls: panel.urls)
        }
    }
}

struct DropZone: View {
    var isTargeted: Bool
    var choose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            AppTitle()
                .padding(.top, 14)
            VStack(spacing: 16) {
                dropBox
                Text("OCR model runs locally on this Mac. No data leaves your computer.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    var dropBox: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolEffect(.bounce, value: reduceMotion ? false : isTargeted)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Drop PDFs or images")
                    .font(.title2.weight(.semibold))
                Button("Choose Files…", action: choose)
                    .buttonStyle(.link)
                    .accessibilityLabel("Choose Files")
                    .accessibilityHint("Or drop PDFs or images anywhere in this window")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.06) : .clear))
        }
    }
}

struct DocumentRow: View {
    var item: DocumentItem
    var pausing: Bool
    var remaining: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            statusIcon
        }
        .padding(.vertical, 3)
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(spokenDetail)")
        .accessibilityAddTraits(.isStaticText)
    }

    var spokenDetail: String {
        detail.replacingOccurrences(of: " · ", with: ", ")
    }

    var detail: String {
        let total = item.pages.count
        let pageWord = total == 1 ? "page" : "pages"
        switch item.status {
        case .waiting:
            if let remaining {
                return "Waiting · \(total) \(pageWord) · \(remaining)"
            }
            return "Waiting · \(total) \(pageWord)"
        case .running:
            if pausing {
                return "Pausing · \(item.pagesDone) of \(total) \(pageWord) done"
            }
            if let attempt = item.currentAttempt, attempt.number > 1 {
                var text = "Page \(attempt.page): attempt \(attempt.number) of \(attempt.total)"
                if let problem = attempt.previousProblem {
                    text += " (last attempt: \(problem))"
                }
                if let remaining {
                    text += " · \(remaining) left"
                }
                return text
            }
            if let remaining {
                return "\(item.pagesDone) of \(total) \(pageWord) done · \(remaining) left"
            }
            return "\(item.pagesDone) of \(total) \(pageWord) done"
        case .paused:
            return "Paused · \(item.pagesDone) of \(total) \(pageWord) done"
        case .done:
            let flagged = item.pagesNeedingChecking.count
            if flagged > 0 {
                return "Done · \(flagged) \(flagged == 1 ? "page needs" : "pages need") checking"
            }
            return "Done · \(total) \(pageWord)"
        case .failed(let message):
            return message
        }
    }

    var subtitle: String {
        let total = item.pages.count
        switch item.status {
        case .waiting: return "\(total) \(total == 1 ? "page" : "pages")"
        case .running:
            if pausing {
                return "Pausing…"
            }
            if let attempt = item.currentAttempt, attempt.number > 1 {
                return "\(item.pagesDone) of \(total) · attempt \(attempt.number) of \(attempt.total)"
            }
            return "\(item.pagesDone) of \(total)"
        case .paused: return "Paused · \(item.pagesDone) of \(total)"
        case .done:
            let flagged = item.pagesNeedingChecking.count
            return flagged > 0 ? "\(flagged) to check" : "\(total) \(total == 1 ? "page" : "pages")"
        case .failed(let message): return item.saveFailed ? "Couldn’t save" : message
        }
    }

    @ViewBuilder
    var statusIcon: some View {
        switch item.status {
        case .waiting:
            EmptyView()
        case .running:
            ProgressRing(fraction: item.fraction, active: true)
        case .paused:
            ProgressRing(fraction: item.fraction, active: false)
        case .done:
            Image(systemName: item.pagesNeedingChecking.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(item.pagesNeedingChecking.isEmpty ? Color.green : Color.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

struct ProgressRing: View {
    var fraction: Double
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(fraction, 0.02))
                .stroke(active ? Color.accentColor : Color.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut, value: fraction)
        }
        .frame(width: 15, height: 15)
    }
}
