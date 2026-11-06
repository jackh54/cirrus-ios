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

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "That does not look like a server address."
        case .unauthorized: "The email or app password was not accepted."
        case .http(let status, let detail): detail ?? "The server answered with HTTP \(status)."
        case .invalidResponse: "The server sent a response the app could not read."
        case .noMailAccount: "This login has no mail account."
        case .method(let type, let description): description ?? "The server reported \(type)."
        case .missingResponse(let id): "The server did not answer call \(id)."
        }
    }

    /// True for `cannotCalculateChanges`: the client must refetch instead of applying a delta.
    public var isCannotCalculateChanges: Bool {
        if case .method(let type, _) = self { return type == "cannotCalculateChanges" }
        return false
    }
}
