// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import Foundation

public enum ModelStoreError: LocalizedError {
    case missingFiles(URL, [String])
    case unreadableConfig(URL)

    public var errorDescription: String? {
        switch self {
        case .missingFiles(let url, let files):
            return "The model folder \(url.path) is incomplete. Missing: \(files.joined(separator: ", "))."
        case .unreadableConfig(let url):
            return "The model settings file in \(url.path) could not be read."
        }
    }
}

public enum ModelStore {
    public static let requiredFiles = [
        "config.json", "tokenizer.json", "tokenizer_config.json", "preprocessor_config.json",
    ]

    static let tokenKeysToLift = [
        "image_token_id", "video_token_id", "vision_start_token_id", "vision_end_token_id", "vision_token_id",
    ]

    public static let applicationSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Slow Reading", isDirectory: true)
        let earlier = base.appendingPathComponent("olmOCR", isDirectory: true)
        let manager = FileManager.default
        if !manager.fileExists(atPath: folder.path) && manager.fileExists(atPath: earlier.path) {
            try? manager.moveItem(at: earlier, to: folder)
        }
        return folder
    }()

    public static var modelsDirectory: URL {
        applicationSupport.appendingPathComponent("Models", isDirectory: true)
    }

    public static var jobsDirectory: URL {
        applicationSupport.appendingPathComponent("Jobs", isDirectory: true)
    }

    public static func modelFolder(_ tier: ModelTier) -> URL {
        modelsDirectory.appendingPathComponent(tier.folderName, isDirectory: true)
    }

    public static func folderSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in files {
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    public static func removeModelFiles(_ tier: ModelTier) throws {
        let folder = modelFolder(tier)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    public static func removeSavedPages() throws {
        if FileManager.default.fileExists(atPath: jobsDirectory.path) {
            try FileManager.default.removeItem(at: jobsDirectory)
        }
    }

    public static func huggingFaceCacheSnapshot(repo: String) -> URL? {
        let folder = "models--" + repo.replacingOccurrences(of: "/", with: "--")
        let snapshots = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent(folder)
            .appendingPathComponent("snapshots")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: snapshots, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return entries.max { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dateA < dateB
        }
    }

    public static func checkComplete(_ directory: URL) throws {
        var missing = requiredFiles.filter {
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        if !contents.contains(where: { $0.hasSuffix(".safetensors") }) {
            missing.append("model weights (.safetensors)")
        }
        if !missing.isEmpty {
            throw ModelStoreError.missingFiles(directory, missing)
        }
    }

    public static func configNeedsFix(_ directory: URL) throws -> Bool {
        let config = try readJSON(directory.appendingPathComponent("config.json"))
        let textConfig = config["text_config"] as? [String: Any] ?? [:]
        return tokenKeysToLift.contains { key in
            isMissing(config[key]) && !isMissing(textConfig[key])
        }
    }

    public static func prepare(_ directory: URL) throws -> URL {
        try checkComplete(directory)
        if try !configNeedsFix(directory) {
            return directory
        }
        if directory.standardizedFileURL.path.hasPrefix(modelsDirectory.standardizedFileURL.path) {
            try fixConfigInPlace(directory)
            return directory
        }
        let name = modelName(for: directory)
        let destination = modelsDirectory
            .appendingPathComponent("Linked", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try linkModelFolder(from: directory, to: destination)
        return destination
    }

    public static func fixConfigInPlace(_ directory: URL) throws {
        let url = directory.appendingPathComponent("config.json")
        var config = try readJSON(url)
        let textConfig = config["text_config"] as? [String: Any] ?? [:]
        var changed = false
        for key in tokenKeysToLift where isMissing(config[key]) && !isMissing(textConfig[key]) {
            config[key] = textConfig[key]
            changed = true
        }
        if changed {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        }
    }

    public static func importModel(from source: URL, tier: ModelTier) throws -> URL {
        try checkComplete(source)
        let destination = modelsDirectory.appendingPathComponent(tier.folderName, isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(atPath: source.path) where !item.hasPrefix(".") {
            let target = destination.appendingPathComponent(item)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(
                at: source.appendingPathComponent(item).resolvingSymlinksInPath(), to: target)
        }
        try fixConfigInPlace(destination)
        let info = ModelInfo(repo: tier.repo, revision: "imported from \(source.path)", files: [], installed: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(info).write(to: destination.appendingPathComponent("model_info.json"), options: .atomic)
        return destination
    }

    public static func modelName(for directory: URL) -> String {
        let components = directory.standardizedFileURL.pathComponents
        if let index = components.firstIndex(where: { $0.hasPrefix("models--") }) {
            return components[index].components(separatedBy: "--").last ?? directory.lastPathComponent
        }
        return directory.lastPathComponent
    }

    static func linkModelFolder(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(atPath: source.path) where item != "config.json" {
            let link = destination.appendingPathComponent(item)
            let target = source.appendingPathComponent(item).resolvingSymlinksInPath()
            if (try? link.checkResourceIsReachable()) == true || (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try fileManager.removeItem(at: link)
            }
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
        }
        var config = try readJSON(source.appendingPathComponent("config.json"))
        let textConfig = config["text_config"] as? [String: Any] ?? [:]
        for key in tokenKeysToLift where isMissing(config[key]) && !isMissing(textConfig[key]) {
            config[key] = textConfig[key]
        }
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination.appendingPathComponent("config.json"), options: .atomic)
    }

    static func readJSON(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ModelStoreError.unreadableConfig(url.deletingLastPathComponent())
        }
        return object
    }

    static func isMissing(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }
}
