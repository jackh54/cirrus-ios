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
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JMAPError.invalidResponse }
        return (data, http)
    }

    public func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw JMAPError.invalidResponse }
        return (bytes, http)
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

    var authorizationHeader: String {
        "Basic " + Data("\(email):\(password)".utf8).base64EncodedString()
    }
}
