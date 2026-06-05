import Foundation
import OSLog

/// Reads recent OSLog entries for a set of subsystems, formatted as
/// one line per entry.
///
/// Uses `OSLogStore(scope: .currentProcessIdentifier)` which does not
/// require the system-wide `com.apple.developer.os.log` entitlement —
/// we only surface log entries the host app itself emitted.
///
/// Apps that don't opt in via ``DiagnosticsPolicy/osLogSubsystems`` get
/// no log data at all, which is the intended default.
enum OSLogTailer {

    /// Returns formatted log lines for the given subsystems within the
    /// lookback window.
    ///
    /// Returns an empty array on any failure (logs are best-effort
    /// diagnostic context, never a hard requirement) but reports the failure
    /// via the optional `logger` so hosts can distinguish "no entries in
    /// window" from "OSLog access denied".
    static func recentEntries(
        subsystems: [String],
        lookback: TimeInterval,
        logger: GitTicketsLogger? = nil,
        clock: @Sendable () -> Date = { Date() }
    ) -> [String] {
        guard !subsystems.isEmpty else { return [] }

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let lookbackDate = clock().addingTimeInterval(-lookback)
            let position = store.position(date: lookbackDate)
            let predicate = NSPredicate(format: "subsystem IN %@", subsystems)
            let entries = try store.getEntries(at: position, matching: predicate)

            return entries.compactMap { entry -> String? in
                guard let logEntry = entry as? OSLogEntryLog else { return nil }
                return formatLine(logEntry)
            }
        } catch {
            logger?.log(
                level: .warning,
                message: "OSLog tailer failed to read entries — diagnostics blob will omit the Recent logs section.",
                error: error
            )
            return []
        }
    }

    static func formatLine(_ entry: OSLogEntryLog) -> String {
        let time = Self.timeFormatter.string(from: entry.date)
        return "\(time)Z \(entry.subsystem) [\(levelTag(entry.level))] \(entry.composedMessage)"
    }

    static func levelTag(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        case .undefined: return "undefined"
        @unknown default: return "unknown"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Pin to UTC so a log captured on a device in Tokyo and read on a
        // server in UTC don't appear nine hours apart. The `Z` suffix in
        // formatLine makes the zone explicit to the reader.
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
