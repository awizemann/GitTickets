import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Resolves the device's `utsname` machine identifier into a human-readable
/// model name where known, falling back to the raw identifier otherwise.
///
/// The mapping table covers recent Apple devices through mid-2026. Unknown
/// or simulator identifiers return the raw string so bug reports stay
/// informative even on unmapped hardware.
enum DeviceInfo {

    /// The raw `utsname.machine` identifier — `"iPhone16,1"`, `"Mac15,3"`,
    /// `"arm64"` on simulator, etc.
    static var machineIdentifier: String {
        var info = utsname()
        uname(&info)
        let machineSize = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: machineSize) {
                String(validatingCString: $0) ?? "unknown"
            }
        }
    }

    /// Best-effort human-readable name for ``machineIdentifier``.
    /// Returns the raw identifier for unknown values.
    static var humanReadableModel: String {
        humanReadable(for: machineIdentifier)
    }

    /// Exposed for testing.
    static func humanReadable(for identifier: String) -> String {
        if let mapped = Self.modelTable[identifier] {
            return mapped
        }
        if isSimulatorEnv {
            // Simulator reports the host architecture; surface that.
            return "Simulator (\(identifier))"
        }
        return identifier
    }

    private static var isSimulatorEnv: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    }

    // Mapping table — extend as new hardware ships. Last update: 2026-06-04.
    // Pulled from gist consensus; commercial mappings keep drifting so we
    // intentionally only include shipped models we can name confidently.
    static let modelTable: [String: String] = [
        // iPhone
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        // iPad
        "iPad13,16": "iPad Air (5th generation)",
        "iPad13,17": "iPad Air (5th generation)",
        "iPad14,1": "iPad mini (6th generation)",
        "iPad14,2": "iPad mini (6th generation)",
        "iPad14,3": "iPad Pro 11-inch (4th generation)",
        "iPad14,4": "iPad Pro 11-inch (4th generation)",
        "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
        // Mac
        "Mac14,2": "MacBook Air (M2, 2022)",
        "Mac14,15": "MacBook Air (15-inch, M2, 2023)",
        "Mac15,12": "MacBook Air (13-inch, M3, 2024)",
        "Mac15,13": "MacBook Air (15-inch, M3, 2024)",
        "Mac14,5": "MacBook Pro (14-inch, M2 Pro)",
        "Mac14,9": "MacBook Pro (14-inch, M2 Pro)",
        "Mac14,10": "MacBook Pro (16-inch, M2 Pro)",
        "Mac15,3": "MacBook Pro (14-inch, M3)",
        "Mac15,6": "MacBook Pro (14-inch, M3 Pro)",
        "Mac15,7": "MacBook Pro (16-inch, M3 Pro)",
        "Mac15,8": "MacBook Pro (14-inch, M3 Max)",
        "Mac15,9": "MacBook Pro (16-inch, M3 Max)",
        "Mac16,1": "MacBook Pro (14-inch, M4)",
        "Mac16,6": "MacBook Pro (14-inch, M4 Pro)",
        "Mac16,7": "MacBook Pro (16-inch, M4 Pro)",
        "Mac16,8": "MacBook Pro (14-inch, M4 Max)",
        "Mac16,5": "MacBook Pro (16-inch, M4 Max)",
        "Mac14,3": "Mac mini (M2)",
        "Mac14,12": "Mac mini (M2 Pro)",
        "Mac16,10": "Mac mini (M4)",
        "Mac16,11": "Mac mini (M4 Pro)",
        "Mac14,13": "Mac Studio (M2 Max, 2023)",
        "Mac14,14": "Mac Studio (M2 Ultra, 2023)",
        "Mac15,14": "Mac Studio (M4 Max, 2025)",
        "Mac15,4": "iMac (24-inch, M3, 2023)",
        "Mac15,5": "iMac (24-inch, M3, 2023)",
        "Mac16,2": "iMac (24-inch, M4, 2024)",
        "Mac16,3": "iMac (24-inch, M4, 2024)",
    ]
}
