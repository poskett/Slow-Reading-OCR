// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import AppKit
import Foundation
import OlmOCRCore

let appReleasesURL = "https://api.github.com/repos/poskett/slow-reading-ocr/releases/latest"

struct AppRelease {
    var version: String
    var page: URL
}

func isNewerVersion(_ candidate: String, than current: String) -> Bool {
    candidate.compare(current, options: .numeric) == .orderedDescending
}

func latestAppRelease() async throws -> AppRelease {
    let address = ProcessInfo.processInfo.environment["SLOWREADING_UPDATE_URL"] ?? appReleasesURL
    let (data, _) = try await URLSession.shared.data(from: URL(string: address)!)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let tag = json?["tag_name"] as? String,
        let page = (json?["html_url"] as? String).flatMap(URL.init(string:))
    else {
        throw URLError(.cannotParseResponse)
    }
    return AppRelease(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), page: page)
}

func installedRevision(_ tier: ModelTier) -> String? {
    guard let directory = installedModelDirectory(tier), let revision = readModelRevision(directory: directory),
        !revision.hasPrefix("imported")
    else {
        return nil
    }
    return revision
}

@MainActor
func askUpdate(title: String, message: String, button: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: button)
    alert.addButton(withTitle: "Later")
    return alert.runModal() == .alertFirstButtonReturn
}

@MainActor
func showMessage(_ title: String, details: String = "") {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = details
    alert.runModal()
}

extension AppModel {
    func checkForUpdatesIfDue() {
        let defaults = UserDefaults.standard
        let automatic = defaults.object(forKey: "checkForUpdates") as? Bool ?? true
        let last = defaults.double(forKey: "lastUpdateCheck")
        guard automatic, Date().timeIntervalSince1970 - last > 24 * 3600 else {
            return
        }
        defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        Task {
            await checkForUpdates(manual: false)
        }
    }

    func checkForUpdates(manual: Bool) async {
        let defaults = UserDefaults.standard
        let tier = selectedTier
        let release = try? await latestAppRelease()
        let remoteRevision = try? await listRemoteModel(repo: tier.repo).revision
        var foundUpdate = false

        if let release, isNewerVersion(release.version, than: appVersion) {
            foundUpdate = true
            if manual || defaults.string(forKey: "skippedAppVersion") != release.version {
                if askUpdate(
                    title: "\(appName) \(release.version) is available",
                    message: "You have version \(appVersion). Download the new version, then replace this app with it.",
                    button: "Download")
                {
                    NSWorkspace.shared.open(release.page)
                } else {
                    defaults.set(release.version, forKey: "skippedAppVersion")
                }
            }
        }

        if let remoteRevision, let installed = installedRevision(tier), remoteRevision != installed {
            foundUpdate = true
            if !queue.isRunning, manual || defaults.string(forKey: "skippedModelRevision") != remoteRevision {
                if askUpdate(
                    title: "The \(tier.title) model has changed",
                    message: "Updating may change how pages are read. Earlier transcripts stay as they are, and each manifest records the model version used.",
                    button: "Update Model")
                {
                    modelDamaged = true
                    download()
                } else {
                    defaults.set(remoteRevision, forKey: "skippedModelRevision")
                }
            }
        }

        guard manual, !foundUpdate else {
            return
        }
        if release == nil {
            showMessage("Couldn’t check for app updates", details: "Check your internet connection and try again.")
        } else {
            showMessage("\(appName) is up to date", details: "Version \(appVersion)")
        }
    }
}
