// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import Foundation
import IOKit.ps
import Metal

public enum ModelTier: String, Codable, CaseIterable, Sendable {
    case full
    case compact

    public var repo: String {
        switch self {
        case .full: return "mlx-community/olmOCR-2-7B-1025-8bit"
        case .compact: return "mlx-community/olmOCR-2-7B-1025-4bit"
        }
    }

    public var folderName: String {
        String(repo.split(separator: "/").last!)
    }

    public var title: String {
        switch self {
        case .full: return "Full"
        case .compact: return "Compact"
        }
    }

    public var summary: String {
        switch self {
        case .full:
            return "Best accuracy"
        case .compact:
            return "Smaller, faster"
        }
    }

    public var approximateDownloadBytes: Int64 {
        switch self {
        case .full: return 9_400_000_000
        case .compact: return 5_700_000_000
        }
    }

    public var peakMemoryBytes: Int64 {
        switch self {
        case .full: return 11_500_000_000
        case .compact: return 7_700_000_000
        }
    }

    public var requiredWorkingSetBytes: Int64 {
        peakMemoryBytes + 1_000_000_000
    }
}

public enum PowerSource: String, Sendable {
    case mains
    case battery
    case unknown
}

public struct SystemReport: Sendable {
    public var chip: String
    public var isAppleSilicon: Bool
    public var isTranslated: Bool
    public var physicalMemory: Int64
    public var gpuWorkingSetLimit: Int64
    public var availableMemory: Int64
    public var freeDiskSpace: Int64
    public var macOSVersion: String
    public var thermalState: ProcessInfo.ThermalState
    public var powerSource: PowerSource

    public var recommendedTier: ModelTier? {
        guard isAppleSilicon else {
            return nil
        }
        return ModelTier.allCases.first { gpuWorkingSetLimit >= $0.requiredWorkingSetBytes }
    }

    public var supportedTiers: [ModelTier] {
        guard isAppleSilicon else {
            return []
        }
        return ModelTier.allCases.filter { gpuWorkingSetLimit >= $0.requiredWorkingSetBytes }
    }

    public var blockingProblem: String? {
        if !isAppleSilicon {
            return "Slow Reading needs a Mac with Apple silicon (M1 or later). This Mac has an Intel processor."
        }
        if isTranslated {
            return "olmOCR is running under Rosetta. Quit it, choose the app in Finder, select File > Get Info, and untick “Open using Rosetta”."
        }
        if recommendedTier == nil {
            return "This Mac has \(formatBytes(physicalMemory)) of memory. Slow Reading needs at least 16 GB to run the model."
        }
        return nil
    }

    public func warnings(for tier: ModelTier) -> [String] {
        var messages: [String] = []
        if availableMemory < tier.peakMemoryBytes {
            messages.append(
                "Only \(formatBytes(availableMemory)) of memory is free right now. Closing other apps (especially web browsers) will make olmOCR faster and steadier.")
        }
        if thermalState == .serious || thermalState == .critical {
            messages.append("This Mac is hot. olmOCR will run slowly until it cools down.")
        }
        if powerSource == .battery {
            messages.append("This Mac is on battery. olmOCR uses a lot of power, so plug in for long jobs.")
        }
        return messages
    }

    public var diagnosticText: String {
        """
        Chip: \(chip)
        Apple silicon: \(isAppleSilicon)\(isTranslated ? " (running under Rosetta)" : "")
        Memory: \(formatBytes(physicalMemory)) (GPU limit \(formatBytes(gpuWorkingSetLimit)), \(formatBytes(availableMemory)) free now)
        Free disk space: \(formatBytes(freeDiskSpace))
        macOS: \(macOSVersion)
        Thermal state: \(thermalStateName(thermalState))
        Power: \(powerSource.rawValue)
        Recommended model: \(recommendedTier?.folderName ?? "none")
        """
    }
}

public func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
}

func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "normal"
    case .fair: return "warm"
    case .serious: return "hot"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
        return nil
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
        return nil
    }
    return String(cString: buffer)
}

func sysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
        return nil
    }
    return Int(value)
}

public func availableMemoryBytes() -> Int64 {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else {
        return 0
    }
    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    let pages = Int64(stats.free_count) + Int64(stats.inactive_count) + Int64(stats.purgeable_count)
        + Int64(stats.speculative_count)
    return pages * Int64(pageSize)
}

public func freeDiskBytes(at url: URL) -> Int64 {
    var probe = url
    while !FileManager.default.fileExists(atPath: probe.path) && probe.pathComponents.count > 1 {
        probe = probe.deletingLastPathComponent()
    }
    let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage ?? 0
}

public func currentPowerSource() -> PowerSource {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
    else {
        return .unknown
    }
    if type == kIOPMACPowerKey {
        return .mains
    }
    if type == kIOPMBatteryPowerKey {
        return .battery
    }
    return .unknown
}

func simulatedGigabytes(_ name: String) -> Int64? {
    guard let text = ProcessInfo.processInfo.environment[name], let value = Double(text) else {
        return nil
    }
    return Int64(value * 1_073_741_824)
}

public func gpuWorkingSetBytes() -> Int64 {
    if let simulated = simulatedGigabytes("SLOWREADING_SIMULATE_RAM_GB") {
        return simulated * 2 / 3
    }
    return Int64(MTLCreateSystemDefaultDevice()?.recommendedMaxWorkingSetSize ?? 0)
}

public func memoryCacheLimit(for modelName: String) -> Int {
    if let override = ProcessInfo.processInfo.environment["SLOWREADING_CACHE_LIMIT_MB"], let megabytes = Int(override) {
        return megabytes * 1_048_576
    }
    let tier: ModelTier = modelName.contains("8bit") ? .full : .compact
    let headroom = gpuWorkingSetBytes() - tier.peakMemoryBytes
    let limit = min(max(headroom / 4, 256_000_000), 4_000_000_000)
    return Int(limit)
}

public func checkSystem() -> SystemReport {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return SystemReport(
        chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
        isAppleSilicon: sysctlInt("hw.optional.arm64") == 1,
        isTranslated: sysctlInt("sysctl.proc_translated") == 1,
        physicalMemory: simulatedGigabytes("SLOWREADING_SIMULATE_RAM_GB") ?? Int64(ProcessInfo.processInfo.physicalMemory),
        gpuWorkingSetLimit: gpuWorkingSetBytes(),
        availableMemory: availableMemoryBytes(),
        freeDiskSpace: freeDiskBytes(at: ModelStore.modelsDirectory),
        macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
        thermalState: ProcessInfo.processInfo.thermalState,
        powerSource: currentPowerSource()
    )
}
