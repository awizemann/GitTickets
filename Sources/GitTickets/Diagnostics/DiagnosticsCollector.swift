import Foundation

/// Assembles a ``DiagnosticsBlob`` from a ``DiagnosticsPolicy``, the host
/// bundle, and the live system.
///
/// Hosts inject their own ``Bundle`` (typically `.main`) so SDK and host
/// version info come from the right place. Log tailing is delegated to
/// ``OSLogTailer``; redaction runs once at the end.
///
/// Surfaced publicly so host apps that present their own UI on top of
/// ``GitTickets/submit(_:)`` can pre-collect the diagnostics blob and show
/// the user exactly what they're about to send. Pass the resulting `text`
/// as ``Report/diagnosticsBlob`` so what the user sees in your form is
/// byte-identical to what gets posted to GitHub.
public enum DiagnosticsCollector {

    /// Collects diagnostics per the policy. Pure with respect to the inputs
    /// except for: process info, locale, bundle reads, filesystem volume
    /// metadata, and OSLog (when enabled).
    ///
    /// - Parameter logger: Optional logger that receives a warning when
    ///   OSLog access fails (entitlement missing, sandbox quirk). Helps
    ///   host apps distinguish "no entries" from "OSLog unavailable".
    public static func collect(
        policy: DiagnosticsPolicy,
        appBundle: Bundle = .main,
        logger: GitTicketsLogger? = nil,
        clock: @Sendable () -> Date = { Date() }
    ) -> DiagnosticsBlob {
        var sections: [(key: String, value: String)] = []

        if policy.includeOSVersion {
            sections.append(("OS", osDescription()))
        }
        if policy.includeAppVersion {
            sections.append(("App", appDescription(from: appBundle)))
        }
        if policy.includeDeviceModel {
            sections.append(("Device", DeviceInfo.humanReadableModel))
        }
        if policy.includeLocale {
            sections.append(("Locale", Locale.current.identifier))
        }
        if policy.includeFreeDisk {
            sections.append(("Free disk", freeDiskDescription()))
        }
        if policy.includeMemoryPressure {
            sections.append(("Memory (physical)", physicalMemoryDescription()))
        }

        var rendered = sections.map { "\($0.key): \($0.value)" }.joined(separator: "\n")

        if !policy.osLogSubsystems.isEmpty {
            let entries = OSLogTailer.recentEntries(
                subsystems: policy.osLogSubsystems,
                lookback: policy.osLogLookback,
                logger: logger,
                clock: clock
            )
            if !entries.isEmpty {
                if !rendered.isEmpty { rendered += "\n\n" }
                rendered += "Recent logs (\(Int(policy.osLogLookback))s):\n"
                rendered += entries.map { "  " + $0 }.joined(separator: "\n")
            }
        }

        let redacted = RedactionPipeline.redact(rendered, with: policy.redactors)
        return DiagnosticsBlob(text: redacted, sections: sections)
    }

    // MARK: - Field collectors

    private static func osDescription() -> String {
        #if os(macOS)
        let prefix = "macOS"
        #elseif os(iOS)
        let prefix = "iOS"
        #else
        let prefix = "Apple OS"
        #endif
        return "\(prefix) \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    private static func appDescription(from bundle: Bundle) -> String {
        let name = bundle.infoDictionary?["CFBundleName"] as? String
            ?? bundle.infoDictionary?["CFBundleExecutable"] as? String
            ?? "Unknown app"
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(name) \(version) (\(build))"
    }

    private static func freeDiskDescription() -> String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        else {
            return "unknown"
        }
        return formatBytes(Int64(capacity))
    }

    private static func physicalMemoryDescription() -> String {
        formatBytes(Int64(ProcessInfo.processInfo.physicalMemory))
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
