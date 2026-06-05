import Foundation

/// Parses HTTP `Retry-After` headers and computes exponential backoffs for
/// transient failures.
enum RateLimitBackoff {

    /// Returns the seconds-to-wait parsed from a `Retry-After` header value.
    ///
    /// Supports delta-seconds (`"120"`) and all three HTTP-date forms
    /// required by RFC 7231 §7.1.1.1:
    /// - IMF-fixdate: `"Wed, 21 Oct 2026 07:28:00 GMT"`
    /// - RFC 850:     `"Wednesday, 21-Oct-26 07:28:00 GMT"`
    /// - asctime:     `"Wed Oct 21 07:28:00 2026"`
    ///
    /// Returns `nil` if none parses.
    static func parseRetryAfter(_ value: String, now: Date = Date()) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return seconds
        }
        for formatter in httpDateFormatters {
            if let date = formatter.date(from: trimmed) {
                return max(0, date.timeIntervalSince(now))
            }
        }
        return nil
    }

    /// Exponential backoff for retry attempts, capped at `maxDelay`.
    /// Attempt 0 → `base`, 1 → `base*2`, 2 → `base*4`, etc.
    ///
    /// When `jitter` is `true` (the default), the result is scaled by a
    /// random factor in `[0.5, 1.5)` to prevent synchronized clients from
    /// retrying in lockstep against a recovering relay.
    static func exponentialDelay(
        attempt: Int,
        base: TimeInterval = 0.5,
        maxDelay: TimeInterval = 30,
        jitter: Bool = true
    ) -> TimeInterval {
        guard attempt >= 0 else { return base }
        let raw = base * pow(2, Double(attempt))
        let capped = min(raw, maxDelay)
        guard jitter else { return capped }
        let scale = Double.random(in: 0.5..<1.5)
        return min(maxDelay, capped * scale)
    }

    private static let httpDateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",  // RFC 7231 IMF-fixdate
            "EEEE, dd-MMM-yy HH:mm:ss zzz",   // RFC 850
            "EEE MMM d HH:mm:ss yyyy",        // asctime (1- or 2-digit day)
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            return formatter
        }
    }()
}
