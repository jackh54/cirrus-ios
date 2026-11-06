import Foundation

/// The HTTP seam of the client; tests replace it with canned responses.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request, delegate: RedirectDelegate(authorization: request.value(forHTTPHeaderField: "Authorization")))
            guard let http = response as? HTTPURLResponse else { throw JMAPError.invalidResponse }
            return (data, http)
        } catch let error as URLError {
            throw JMAPError(transport: error)
        }
    }

    public func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectDelegate(authorization: request.value(forHTTPHeaderField: "Authorization")))
            guard let http = response as? HTTPURLResponse else { throw JMAPError.invalidResponse }
            return (bytes, http)
        } catch let error as URLError {
            throw JMAPError(transport: error)
        }
    }
}

/// Follows redirects but re-adds the Authorization header only when the target has the same scheme, host and port.
final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let authorization: String?

    init(authorization: String?) { self.authorization = authorization }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        RedirectPolicy.follow(request, from: response.url, authorization: authorization)
    }
}

public enum RedirectPolicy {
    /// Same scheme, host and port (default ports are normalised).
    public static func sameOrigin(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b, let sa = a.scheme?.lowercased(), let sb = b.scheme?.lowercased(),
              let ha = a.host?.lowercased(), let hb = b.host?.lowercased() else { return false }
        func port(_ u: URL, _ scheme: String) -> Int { u.port ?? (scheme == "https" ? 443 : 80) }
        return sa == sb && ha == hb && port(a, sa) == port(b, sb)
    }

    public static func follow(_ request: URLRequest, from origin: URL?, authorization: String?) -> URLRequest {
        var r = request
        if let authorization, sameOrigin(origin, request.url) {
            r.setValue(authorization, forHTTPHeaderField: "Authorization")
        } else {
            r.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return r
    }
}

/// The login: server base URL, the account email and an app password (created in the web app under Settings, Security).
public struct Credentials: Sendable, Codable, Hashable {
    public var serverURL: URL
    public var email: String
    public var password: String

    public init(serverURL: URL, email: String, password: String) {
        self.serverURL = serverURL
        self.email = email
        self.password = password
    }

    /// Turns what a user typed ("cirrus.example.com", "https://cirrus.example.com/mail") into a base URL, defaulting to https.
    public static func normalizedServerURL(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard var c = URLComponents(string: t), let scheme = c.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = c.host, host.contains(".") || host == "localhost" else { return nil }
        c.path = ""; c.query = nil; c.fragment = nil; c.user = nil; c.password = nil
        return c.url
    }

    var authorizationHeader: String {
        "Basic " + Data("\(email):\(password)".utf8).base64EncodedString()
    }
}
