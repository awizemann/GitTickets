import Foundation

/// Parses HTTP `Retry-After` headers and computes exponential backoffs for
/// transient failures.
enum RateLimitBackoff {

    /// Returns the seconds-to-wait parsed from a `Retry-After` header value.
    /// Supports both delta-seconds (`"120"`) and HTTP-date forms
    /// (`"Wed, 21 Oct 2026 07:28:00 GMT"`). Returns `nil` if neither parses.
    static func parseRetryAfter(_ value: String, now: Date = Date()) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return seconds
        }
        if let date = httpDateFormatter.date(from: trimmed) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }

    /// Exponential backoff for retry attempts, capped at `maxDelay`.
    /// Attempt 0 → `base`, 1 → `base*2`, 2 → `base*4`, etc.
    static func exponentialDelay(
        attempt: Int,
        base: TimeInterval = 0.5,
        maxDelay: TimeInterval = 30
    ) -> TimeInterval {
        guard attempt >= 0 else { return base }
        let raw = base * pow(2, Double(attempt))
        return min(raw, maxDelay)
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        return formatter
    }()
}
