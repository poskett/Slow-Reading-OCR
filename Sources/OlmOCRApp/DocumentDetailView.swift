// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import OlmOCRCore
import SwiftUI

let transcriptTextSizes: [Double] = [11, 12, 13.5, 15, 17, 20, 24, 28]
let defaultTranscriptTextSize = 13.5

struct DocumentDetailView: View {
    @Bindable var item: DocumentItem
    var queue: QueueModel
    @AppStorage("transcriptTextSize") private var textSize = defaultTranscriptTextSize
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var image: NSImage?
    @State private var showingRange = false
    @State private var rangeText = ""
    @State private var rangeInvalid = false
    @State private var copied = false

    var pageIndex: Int {
        item.pages.firstIndex(of: item.selectedPage) ?? 0
    }

    var result: PageResult? {
        item.results[item.selectedPage]
    }

    var subtitle: String {
        switch item.status {
        case .done:
            let flagged = item.pagesNeedingChecking.count
            return flagged == 0 ? "Done" : "Done · \(flagged) to check"
        case .running, .paused:
            return "\(item.pagesDone) of \(pagesText(item.pages.count))"
        case .failed:
            return item.saveFailed ? "Couldn’t save" : "Failed"
        default:
            return "\(item.pages.count) \(item.pages.count == 1 ? "page" : "pages")"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    pageView
                        .frame(width: geometry.size.width / 2)
                    Divider()
                    textView
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: item.selectedPage) {
            image = await pageImage(source: item.source, page: item.selectedPage)
        }
        .navigationTitle(item.name)
        .navigationSubtitle(subtitle)
    }

    var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                Button {
                    move(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(pageIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help("Previous page (⌘←)")
                .accessibilityLabel("Previous page")
                Text("Page \(item.source.kind == .folder ? "\(pageIndex + 1)" : "\(item.selectedPage)")")
                    .monospacedDigit()
                    .frame(minWidth: 64)
                Button {
                    move(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(pageIndex >= item.pages.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("Next page (⌘→)")
                .accessibilityLabel("Next page")
            }
            .buttonStyle(.borderless)

            Button {
                rangeText = item.pageRangeText
                rangeInvalid = false
                showingRange = true
            } label: {
                Text(item.pageRangeText.isEmpty ? (item.source.pageCount == 1 ? "1 page" : "All \(item.source.pageCount) pages") : "Pages \(item.pageRangeText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(item.status == .waiting || item.status == .paused ? "Choose which pages to transcribe" : "")
            .disabled(item.status == .running || item.status == .done)
            .popover(isPresented: $showingRange, arrowEdge: .bottom) {
                rangePopover
            }

            Spacer()

            if item.saveFailed {
                Button {
                    queue.saveElsewhere(item)
                } label: {
                    Label("Couldn’t save · Save To…", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help(saveErrorText)
            }

            if let result, result.needsChecking {
                Label("Check", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                    .help("Check this page against the scan" + (result.problem.map { ": \($0)" } ?? ""))
                    .accessibilityLabel("Check this page against the scan" + (result.problem.map { ": \($0)" } ?? ""))
            }

            HStack(spacing: 8) {
                if result?.response.naturalText != nil {
                    Button {
                        copyPage()
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(minWidth: 58)
                    }
                    .help("Copy this page’s text")
                }
                if let file = item.outputFiles.first {
                    Button {
                        NSWorkspace.shared.open(file)
                    } label: {
                        Label("Open Transcript", systemImage: "arrow.up.forward.square")
                    }
                    .help("Open \(file.lastPathComponent)")
                } else if let file = currentPageFile {
                    Button {
                        NSWorkspace.shared.open(file)
                    } label: {
                        Label("Open Page", systemImage: "arrow.up.forward.square")
                    }
                    .help("Open \(file.lastPathComponent). The full transcript is saved when the document finishes.")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([finderTarget])
                } label: {
                    Label("Open Finder", systemImage: "folder")
                }
                .help("Show \(finderTarget.lastPathComponent) in Finder")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    var rangePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("All pages", text: $rangeText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(applyRange)
            Text(rangeInvalid ? "Use e.g. 1-10, 15" : "e.g. 1-10, 15")
                .font(.caption)
                .foregroundStyle(rangeInvalid ? Color.red : .secondary)
        }
        .padding(14)
    }

    func applyRange() {
        if item.applyPageRange(rangeText) {
            showingRange = false
        } else {
            rangeInvalid = true
        }
    }

    var currentPageFile: URL? {
        guard let plan = item.plan, result != nil else {
            return nil
        }
        let url = pageFileURL(page: item.selectedPage, source: item.source, plan: plan)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var finderTarget: URL {
        if let file = item.outputFiles.first {
            return file
        }
        if let file = currentPageFile {
            return file
        }
        if let plan = item.plan, FileManager.default.fileExists(atPath: plan.manifest.path) {
            return plan.manifest
        }
        return item.url
    }

    var saveErrorText: String {
        if case .failed(let message) = item.status {
            return message + " Choose another folder to save the transcript."
        }
        return "Choose another folder to save the transcript."
    }

    func copyPage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result?.response.naturalText ?? "", forType: .string)
        withAnimation {
            copied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation {
                copied = false
            }
        }
    }

    func move(_ step: Int) {
        let index = min(max(pageIndex + step, 0), item.pages.count - 1)
        item.selectedPage = item.pages[index]
        item.followProgress = false
    }

    var quietText: HierarchicalShapeStyle {
        contrast == .increased ? .secondary : .tertiary
    }

    var pageView: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .padding(20)
                    .accessibilityLabel("Scan of page \(item.source.kind == .folder ? pageIndex + 1 : item.selectedPage)")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading page")
            }
        }
    }

    @ViewBuilder
    var textView: some View {
        if let result {
            ScrollView {
                Text(displayText(result.response.naturalText))
                    .font(.system(size: textSize, design: .serif))
                    .lineSpacing(textSize * 0.37)
                    .foregroundStyle(result.response.naturalText == nil ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                if item.currentPage == item.selectedPage {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        VStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(queue.isPausing ? "Pausing…" : "Transcribing…")
                                .foregroundStyle(.secondary)
                            if !queue.isPausing, let attempt = item.currentAttempt, attempt.number > 1 {
                                Text("Attempt \(attempt.number) of \(attempt.total)")
                                    .font(.callout)
                                    .foregroundStyle(quietText)
                            } else if !queue.isPausing, queue.isSlowAttempt(item) {
                                Text("Taking longer than usual")
                                    .font(.callout)
                                    .foregroundStyle(quietText)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else if case .failed(let message) = item.status {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                        .help("Not transcribed yet")
                        .accessibilityLabel("Not transcribed yet")
                }
            }
        }
    }
}

func displayText(_ text: String?) -> AttributedString {
    guard let text else {
        return AttributedString("Blank page")
    }
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}
