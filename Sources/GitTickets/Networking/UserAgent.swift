import Foundation
#if os(iOS)
import UIKit
#endif

/// Constructs the `User-Agent` header sent on all SDK requests.
///
/// Shape: `GitTickets/<sdk-version> (<platform>; <device-model>; <os-version>) <app-name>/<app-version>`.
/// Example: `GitTickets/1.0.0 (macOS; MacBook Pro (14-inch, M3); 26.0.0) MyApp/1.2.3`.
enum UserAgent {

    /// SDK version baked at compile time. Updated alongside CHANGELOG entries.
    static let sdkVersion = "1.0.0"

    /// Composes the final User-Agent string from the host bundle and the
    /// runtime device + OS.
    static func string(appBundle: Bundle = .main) -> String {
        let platform: String
        #if os(macOS)
        platform = "macOS"
        #elseif os(iOS)
        platform = "iOS"
        #else
        platform = "AppleOS"
        #endif

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let device = DeviceInfo.humanReadableModel
        let appName = appBundle.infoDictionary?["CFBundleName"] as? String
            ?? appBundle.infoDictionary?["CFBundleExecutable"] as? String
            ?? "App"
        let appVersion = appBundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

        return "GitTickets/\(sdkVersion) (\(platform); \(device); \(osVersion)) \(appName)/\(appVersion)"
    }
}
