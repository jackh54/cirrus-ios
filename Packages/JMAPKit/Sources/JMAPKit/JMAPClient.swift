import Foundation

public struct JMAPClient: Sendable {
    public let session: JMAPSession
    public let credentials: Credentials
    private let transport: any HTTPTransport

    public init(session: JMAPSession, credentials: Credentials, transport: any HTTPTransport = URLSessionTransport()) {
        self.session = session
        self.credentials = credentials
        self.transport = transport
    }

    // MARK: Session discovery

    /// Fetches `/.well-known/jmap` (the server redirects to the session resource) with HTTP Basic credentials.
    /// If that fails for any reason other than rejected credentials, `/jmap/session` is tried directly.
    public static func discover(credentials: Credentials, transport: any HTTPTransport = URLSessionTransport()) async throws -> JMAPSession {
        guard var comps = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false),
              comps.scheme == "https" || comps.scheme == "http", comps.host != nil else { throw JMAPError.invalidServerURL }
        comps.query = nil
        func fetch(_ path: String) async throws -> JMAPSession {
            comps.path = path
            guard let url = comps.url else { throw JMAPError.invalidServerURL }
            var request = URLRequest(url: url)
            request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await transport.data(for: request)
            try check(response, data: data)
            do { return try JMAPCoding.makeDecoder().decode(JMAPSession.self, from: data) } catch { throw JMAPError.invalidResponse }
        }
        do {
            return try await fetch("/.well-known/jmap")
        } catch JMAPError.unauthorized {
            throw JMAPError.unauthorized
        } catch JMAPError.insecureConnection {
            throw JMAPError.insecureConnection
        } catch {
            return try await fetch("/jmap/session")
        }
    }

    // MARK: API calls

    public func call(_ calls: [Invocation], using: [String] = Capability.mailAndSubmission) async throws -> JMAPResponse {
        guard let url = URL(string: session.apiUrl) else { throw JMAPError.invalidResponse }
        var request = authorized(URLRequest(url: url))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JMAPCoding.makeEncoder().encode(JMAPRequest(using: using, methodCalls: calls))
        let (data, response) = try await transport.data(for: request)
        try Self.check(response, data: data)
        do { return try JMAPCoding.makeDecoder().decode(JMAPResponse.self, from: data) } catch { throw JMAPError.invalidResponse }
    }

    // MARK: Blobs

    public func upload(accountID: String, data: Data, contentType: String) async throws -> UploadResponse {
        guard let url = URL(string: expand(session.uploadUrl, ["accountId": accountID])) else { throw JMAPError.invalidResponse }
        var request = authorized(URLRequest(url: url))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (body, response) = try await transport.data(for: request)
        try Self.check(response, data: body)
        return try JMAPCoding.makeDecoder().decode(UploadResponse.self, from: body)
    }

    public func downloadURL(accountID: String, blobID: String, name: String, type: String? = nil) -> URL? {
        URL(string: expand(session.downloadUrl, ["accountId": accountID, "blobId": blobID, "name": name, "type": type ?? "application/octet-stream"]))
    }

    public func download(accountID: String, blobID: String, name: String, type: String? = nil) async throws -> Data {
        guard let url = downloadURL(accountID: accountID, blobID: blobID, name: name, type: type) else { throw JMAPError.invalidResponse }
        let (data, response) = try await transport.data(for: authorized(URLRequest(url: url)))
        try Self.check(response, data: data)
        return data
    }

    // MARK: EventSource (RFC 8620 §7.3)

    /// A stream of state changes. It ends when the server closes the connection (Cirrus does so after 5 minutes); the caller reconnects.
    public func stateChanges(types: [String] = ["Email", "Mailbox"], ping: Int = 30) -> AsyncThrowingStream<StateChange, Error> {
        let template = session.eventSourceUrl
        let client = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let template,
                          let url = URL(string: client.expand(template, ["types": types.joined(separator: ","), "closeafter": "no", "ping": String(ping)])) else {
                        throw JMAPError.invalidResponse
                    }
                    var request = client.authorized(URLRequest(url: url))
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 3600
                    let (bytes, response) = try await client.transport.bytes(for: request)
                    try Self.check(response, data: Data())
                    var parser = EventSourceParser()
                    for try await line in bytes.lines {
                        if let change = parser.feed(line: line) { continuation.yield(change) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Helpers

    func authorized(_ request: URLRequest) -> URLRequest {
        var r = request
        r.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        return r
    }

    /// Expands RFC 6570 style `{name}` placeholders with percent-encoded values; unknown placeholders become empty.
    func expand(_ template: String, _ values: [String: String]) -> String {
        var out = template
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "/&=+?#"))
        for (key, value) in values {
            out = out.replacingOccurrences(of: "{\(key)}", with: value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
        }
        return out.replacingOccurrences(of: #"\{[A-Za-z]+\}"#, with: "", options: .regularExpression)
    }

    static func check(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw JMAPError.unauthorized
        default:
            let detail = (try? JMAPCoding.makeDecoder().decode(JSONValue.self, from: data))?["detail"]?.stringValue
            throw JMAPError.http(status: response.statusCode, detail: detail)
        }
    }
}

/// Line-based Server-Sent Events parser. `AsyncBytes.lines` drops blank lines, so an event is emitted on its `data:` line.
public struct EventSourceParser: Sendable {
    private var event = "message"

    public init() {}

    public mutating func feed(line: String) -> StateChange? {
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            defer { event = "message" }
            guard event == "state" else { return nil }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return try? JMAPCoding.makeDecoder().decode(StateChange.self, from: Data(payload.utf8))
        }
        return nil
    }
}

extension Mailbox {
    /// Applies a Mailbox/changes delta: drops destroyed ids and replaces or appends the refetched mailboxes.
    public static func merge(_ current: [Mailbox], changes: ChangesResponse, fetched: [Mailbox]) -> [Mailbox] {
        var byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for id in changes.destroyed { byID[id] = nil }
        for m in fetched { byID[m.id] = m }
        return byID.values.sorted { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }
    }
}
