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
        let response = try await postSigned(path: "report", body: body)
        return try decode(response, as: RelayReportResponse.self)
    }

    // MARK: - POST /attachment (multipart)

    func uploadAttachment(_ attachment: ReportAttachment) async throws -> RelayAttachmentResponse {
        let boundary = "gittickets-" + UUID().uuidString
        let body = Self.encodeMultipart(attachment: attachment, boundary: boundary)
        let url = baseURL.appendingPathComponent("attachment")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let timestamp = Self.formatTimestamp(clock())
        let signature = RelaySignature.sign(timestamp: timestamp, body: body, secret: secret)
        request.setValue(timestamp, forHTTPHeaderField: Self.timestampHeader)
        request.setValue(signature, forHTTPHeaderField: Self.signatureHeader)

        let response = try await http.send(request)
        try Self.validate(response)
        return try decode(response, as: RelayAttachmentResponse.self)
    }

    // MARK: - POST /my-issues

    func fetchMyIssues(_ request: MyIssuesRequest) async throws -> MyIssuesResponse {
        let body = try RelayJSON.encoder.encode(request)
        let response = try await postSigned(path: "my-issues", body: body)
        return try decode(response, as: MyIssuesResponse.self)
    }

    // MARK: - Private helpers

    private func postSigned(path: String, body: Data) async throws -> HTTPResponse {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let timestamp = Self.formatTimestamp(clock())
        let signature = RelaySignature.sign(timestamp: timestamp, body: body, secret: secret)
        request.setValue(timestamp, forHTTPHeaderField: Self.timestampHeader)
        request.setValue(signature, forHTTPHeaderField: Self.signatureHeader)

        let response: HTTPResponse
        do {
            response = try await http.send(request)
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
            throw GitTicketsError.attachmentTooLarge(byteLimit: 5_242_880)
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

    /// Multipart encoding for `POST /attachment`. One file part named `file`.
    static func encodeMultipart(attachment: ReportAttachment, boundary: String) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(attachment.filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(attachment.mimeType)\r\n\r\n".utf8))
        body.append(attachment.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
