import Foundation

/// Wire-level relay client. Handles HMAC signing, JSON encoding, multipart
/// attachment uploads, and response shape validation.
///
/// Stateless and ``Sendable``. ``RelaySubmitter`` owns one of these.
struct RelayClient: Sendable {

    let baseURL: URL
    let secret: SharedSecret
    let http: HTTPClient
    let clock: @Sendable () -> Date

    static let signatureHeader = "X-GitTickets-Signature"
    static let timestampHeader = "X-GitTickets-Timestamp"
    static let idempotencyHeader = "X-GitTickets-Idempotency-Key"

    /// Default attachment-size byte limit surfaced to callers when the relay
    /// rejects with 413 and does not include a `byteLimit` in its error
    /// envelope. Operators that raise the relay's limit should also have
    /// the relay return `byteLimit` so clients report the real cap.
    static let defaultAttachmentByteLimit = 5_242_880

    init(
        baseURL: URL,
        secret: SharedSecret,
        http: HTTPClient = HTTPClient(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.secret = secret
        self.http = http
        self.clock = clock
    }

    // MARK: - POST /report

    func postReport(_ payload: RelayReportRequest) async throws -> RelayReportResponse {
        let body = try RelayJSON.encoder.encode(payload)
        let response = try await postSigned(
            path: "report",
            body: body,
            contentType: "application/json",
            idempotencyKey: payload.submissionID
        )
        return try decode(response, as: RelayReportResponse.self)
    }

    // MARK: - POST /attachment (multipart)

    func uploadAttachment(_ attachment: ReportAttachment) async throws -> RelayAttachmentResponse {
        let boundary = "gittickets-" + UUID().uuidString
        let body = try Self.encodeMultipart(attachment: attachment, boundary: boundary)
        let response = try await postSigned(
            path: "attachment",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            idempotencyKey: nil
        )
        return try decode(response, as: RelayAttachmentResponse.self)
    }

    // MARK: - POST /my-issues

    func fetchMyIssues(_ request: MyIssuesRequest) async throws -> MyIssuesResponse {
        let body = try RelayJSON.encoder.encode(request)
        let response = try await postSigned(
            path: "my-issues",
            body: body,
            contentType: "application/json",
            idempotencyKey: nil
        )
        return try decode(response, as: MyIssuesResponse.self)
    }

    // MARK: - Private helpers

    /// Builds a signed POST request, sends it via ``HTTPClient``, and maps
    /// the response status code into a ``GitTicketsError`` for non-2xx.
    ///
    /// The signing closure runs before every attempt, so each retry gets a
    /// fresh timestamp and a fresh signature — the relay's replay window is
    /// only a few minutes wide, and replaying the same `(timestamp,
    /// signature)` across retries would turn transient 5xx into permanent
    /// 401.
    private func postSigned(
        path: String,
        body: Data,
        contentType: String,
        idempotencyKey: String?
    ) async throws -> HTTPResponse {
        let url = baseURL.appendingPathComponent(path)
        let response: HTTPResponse
        do {
            response = try await http.sendRetrying { _ in
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                request.httpBody = body

                let timestamp = Self.formatTimestamp(clock())
                let signature = RelaySignature.sign(timestamp: timestamp, body: body, secret: secret)
                request.setValue(timestamp, forHTTPHeaderField: Self.timestampHeader)
                request.setValue(signature, forHTTPHeaderField: Self.signatureHeader)
                if let idempotencyKey {
                    request.setValue(idempotencyKey, forHTTPHeaderField: Self.idempotencyHeader)
                }
                return request
            }
        } catch {
            throw GitTicketsError.relayUnreachable(underlying: error)
        }
        try Self.validate(response)
        return response
    }

    private func decode<T: Decodable>(_ response: HTTPResponse, as type: T.Type) throws -> T {
        do {
            return try RelayJSON.decoder.decode(T.self, from: response.body)
        } catch {
            throw GitTicketsError.payloadInvalid(reason: "Could not decode \(T.self): \(error)")
        }
    }

    private static func validate(_ response: HTTPResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw GitTicketsError.signatureMismatch
        case 413:
            let envelope = try? RelayJSON.decoder.decode(RelayErrorEnvelope.self, from: response.body)
            let limit = envelope?.byteLimit ?? defaultAttachmentByteLimit
            throw GitTicketsError.attachmentTooLarge(byteLimit: limit)
        case 429:
            let retryAfter = response.header("Retry-After")
                .flatMap { RateLimitBackoff.parseRetryAfter($0) }
            throw GitTicketsError.rateLimited(retryAfter: retryAfter)
        default:
            let envelope = (try? RelayJSON.decoder.decode(RelayErrorEnvelope.self, from: response.body))
            throw GitTicketsError.relayRejected(statusCode: response.statusCode, message: envelope?.message ?? envelope?.error)
        }
    }

    static func formatTimestamp(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }

    // MARK: - Multipart encoding

    /// Sanitizes the caller-supplied filename so it can be safely embedded
    /// in a `Content-Disposition` quoted-string. Strips CR/LF (which would
    /// terminate the header section), strips quotes (which would close the
    /// quoted-string early), and limits to a conservative character set.
    /// Falls back to a generic name when sanitization leaves nothing usable.
    static func sanitizeFilename(_ raw: String) -> String {
        let stripped = raw.unicodeScalars.filter { scalar in
            let v = scalar.value
            if v < 0x20 || v == 0x7F { return false }   // control chars incl. CR/LF
            if scalar == "\"" || scalar == "\\" { return false }
            return true
        }
        let cleaned = String(String.UnicodeScalarView(stripped))
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "attachment" }
        // Hard cap on length to keep headers reasonable.
        if trimmed.count > 200 { return String(trimmed.prefix(200)) }
        return trimmed
    }

    /// Whitelist of MIME types the relay accepts. Anything else is rejected
    /// before the bytes go on the wire so a caller-controlled `mimeType`
    /// can't inject CRLF or extra parts into the multipart envelope.
    private static let allowedMimeTypes: Set<String> = [
        "image/png", "image/jpeg", "image/gif", "image/webp", "image/heic",
        "application/octet-stream", "text/plain",
    ]

    static func validateMimeType(_ mimeType: String) throws {
        let normalized = mimeType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowedMimeTypes.contains(normalized) else {
            throw GitTicketsError.payloadInvalid(
                reason: "Unsupported attachment MIME type: \(mimeType). Allowed: \(allowedMimeTypes.sorted().joined(separator: ", "))."
            )
        }
        // Defense in depth: even if a future change widens the allowlist,
        // refuse any value containing CR/LF so a header-injection vector
        // can't slip through the typo of one new entry.
        if normalized.contains("\r") || normalized.contains("\n") {
            throw GitTicketsError.payloadInvalid(reason: "Attachment MIME type contains illegal characters.")
        }
    }

    /// Multipart encoding for `POST /attachment`. One file part named `file`.
    static func encodeMultipart(attachment: ReportAttachment, boundary: String) throws -> Data {
        try validateMimeType(attachment.mimeType)
        let safeName = sanitizeFilename(attachment.filename)
        let safeMime = attachment.mimeType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(safeMime)\r\n\r\n".utf8))
        body.append(attachment.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
