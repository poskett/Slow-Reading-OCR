// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import OlmOCRCore
import SwiftUI

struct SetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            AppMark()
            content
                .frame(width: 400)
            Spacer(minLength: 0)
            footer
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    @ViewBuilder
    var content: some View {
        switch model.phase {
        case .checking:
            ProgressView().controlSize(.small)
        case .blocked(let problem):
            Text(problem)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case .needsModel, .failed:
            chooser
        case .downloading:
            downloading
        case .importing:
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Importing…")
                    .foregroundStyle(.secondary)
            }
        case .testing:
            testing
        case .ready:
            EmptyView()
        }
    }

    var chooser: some View {
        VStack(spacing: 20) {
            if case .failed(let message) = model.phase {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .help(model.modelDamaged ? model.loadError ?? "" : "")
            }
            HStack(spacing: 12) {
                ForEach(model.report?.supportedTiers ?? [], id: \.self) { tier in
                    TierCard(
                        tier: tier,
                        selected: model.selectedTier == tier,
                        recommended: tier == model.report?.recommendedTier,
                        installed: installedModelDirectory(tier) != nil
                    ) {
                        model.chooseTier(tier)
                    }
                }
            }
            VStack(spacing: 10) {
                Button {
                    if model.isModelInstalled && !model.modelDamaged {
                        model.useInstalledModel()
                    } else {
                        model.download()
                    }
                } label: {
                    Text(primaryTitle)
                        .frame(width: 200)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                if !model.isModelInstalled {
                    Button("Import from folder…") {
                        model.importModel()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("Use model files you have already downloaded")
                }
            }
            if let warning = model.report?.warnings(for: model.selectedTier).first {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    var testing: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(Int(context.date.timeIntervalSince(model.stepStarted)), 0)
            VStack(spacing: 14) {
                if let fraction = model.testFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 280)
                        .accessibilityLabel(model.testMessage)
                } else {
                    ProgressView().controlSize(.small)
                }
                VStack(spacing: 5) {
                    Text(model.testMessage)
                        .font(.headline)
                    Text(model.testDetail + (elapsed >= 15 ? " · \(elapsed) s" : ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if elapsed >= 40 {
                        Text("Still working. This can take a few minutes on some Macs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }

    var primaryTitle: String {
        if model.modelDamaged {
            return "Repair Model"
        }
        if model.isModelInstalled {
            return "Continue"
        }
        return model.hasPartialDownload ? "Resume Download" : "Download"
    }

    var downloading: some View {
        VStack(spacing: 14) {
            ProgressView(value: model.downloadProgress?.fraction ?? 0)
                .progressViewStyle(.linear)
            HStack {
                if let progress = model.downloadProgress {
                    Text("\(formatBytes(progress.bytesDone)) of \(formatBytes(progress.bytesTotal))")
                    Spacer()
                    if progress.currentFile.hasPrefix("Checking") {
                        Text("Verifying…")
                    } else if let seconds = progress.secondsRemaining {
                        Text(shortRemaining(seconds))
                    }
                } else {
                    Text("Connecting…")
                    Spacer()
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            Button("Pause") {
                model.pauseDownload()
            }
            .help("Pause the download. It resumes where it stopped.")
            .controlSize(.large)
        }
    }

    @ViewBuilder
    var footer: some View {
        switch model.phase {
        case .needsModel, .downloading, .failed:
            Text("OCR model runs locally on this Mac. No data leaves your computer.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .blocked:
            if let report = model.report {
                Button("Copy System Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.diagnosticText, forType: .string)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        default:
            EmptyView()
        }
    }
}

struct AppTitle: View {
    var body: some View {
        VStack(spacing: 3) {
            Text(appName)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("OCR for Researchers")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppMark: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            AppTitle()
        }
    }
}

struct TierCard: View {
    var tier: ModelTier
    var selected: Bool
    var recommended: Bool
    var installed: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tier.title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                        .font(.title3)
                }
                Text(tier.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    Text(installed ? "Installed" : formatBytes(tier.approximateDownloadBytes))
                    if recommended {
                        Text("·")
                        Text("Recommended")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 96)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.title), \(tier.summary)")
    }
}

func shortRemaining(_ seconds: Double) -> String {
    if seconds < 60 {
        return "Under a minute"
    }
    if seconds < 3600 {
        return "\(Int((seconds / 60).rounded())) min left"
    }
    return String(format: "%.1f h left", seconds / 3600)
}
