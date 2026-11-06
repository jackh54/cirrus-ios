import Foundation

public enum JMAPError: Error, Sendable, Equatable, LocalizedError {
    case invalidServerURL
    case unauthorized
    case http(status: Int, detail: String?)
    case invalidResponse
    case noMailAccount
    /// A method-level `["error", {...}, callId]` response.
    case method(type: String, description: String?)
    case missingResponse(callID: String)
    /// The server could not be reached (offline, DNS, refused, timeout, TLS).
    case network(String)
    /// App Transport Security refused a plain http:// server.
    case insecureConnection

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "That does not look like a server address."
        case .unauthorized: "The email or app password was not accepted."
        case .http(let status, let detail): detail ?? "The server answered with HTTP \(status)."
        case .invalidResponse: "The server sent a response the app could not read."
        case .noMailAccount: "This login has no mail account."
        case .method(let type, let description): description ?? "The server reported \(type)."
        case .network(let reason): "Could not reach the server: \(reason)"
        case .insecureConnection: "The server uses plain http://, which iOS blocks. Use https://, or a local-network address for development."
        case .missingResponse(let id): "The server did not answer call \(id)."
        }
    }

    init(transport error: URLError) {
        switch error.code {
        case .appTransportSecurityRequiresSecureConnection: self = .insecureConnection
        case .cancelled: self = .network("cancelled")
        default: self = .network(error.localizedDescription)
        }
    }

    /// True for `cannotCalculateChanges`: the client must refetch instead of applying a delta.
    public var isCannotCalculateChanges: Bool {
        if case .method(let type, _) = self { return type == "cannotCalculateChanges" }
        return false
    }
}
