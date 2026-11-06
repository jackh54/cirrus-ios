import Foundation

public enum Capability {
    public static let core = "urn:ietf:params:jmap:core"
    public static let mail = "urn:ietf:params:jmap:mail"
    public static let submission = "urn:ietf:params:jmap:submission"
    public static let cirrusLabels = "urn:cirrus:params:jmap:labels"
    public static let mailAndSubmission = [core, mail, submission]
}

/// One method call or response: encoded as the JSON triple `[name, arguments, callId]`.
public struct Invocation: Sendable, Hashable, Codable {
    public var name: String
    public var arguments: JSONValue
    public var callID: String

    public init(name: String, arguments: [String: JSONValue], callID: String) {
        self.name = name
        self.arguments = .object(arguments)
        self.callID = callID
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        name = try c.decode(String.self)
        arguments = try c.decode(JSONValue.self)
        callID = try c.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(name)
        try c.encode(arguments)
        try c.encode(callID)
    }
}

/// RFC 8620 §3.7: a reference to part of an earlier response in the same request.
public struct ResultReference: Sendable, Hashable, Codable {
    public var resultOf: String
    public var name: String
    public var path: String

    public init(resultOf: String, name: String, path: String) {
        self.resultOf = resultOf
        self.name = name
        self.path = path
    }

    var json: JSONValue { ["resultOf": .string(resultOf), "name": .string(name), "path": .string(path)] }
}

/// Where a method's `ids` come from: a literal list, every object (null), or an earlier result (sent as `#ids`).
public enum IDSource: Sendable, Hashable {
    case all
    case ids([String])
    case reference(ResultReference)

    func add(to args: inout [String: JSONValue], key: String = "ids") {
        switch self {
        case .all: args[key] = .null
        case .ids(let ids): args[key] = .strings(ids)
        case .reference(let r): args["#" + key] = r.json
        }
    }
}

public struct JMAPRequest: Sendable, Codable, Equatable {
    public var using: [String]
    public var methodCalls: [Invocation]
    public var createdIds: [String: String]?

    public init(using: [String], methodCalls: [Invocation], createdIds: [String: String]? = nil) {
        self.using = using
        self.methodCalls = methodCalls
        self.createdIds = createdIds
    }
}

public struct JMAPResponse: Sendable, Codable {
    public var methodResponses: [Invocation]
    public var sessionState: String?
    public var createdIds: [String: String]?

    public init(methodResponses: [Invocation], sessionState: String? = nil, createdIds: [String: String]? = nil) {
        self.methodResponses = methodResponses
        self.sessionState = sessionState
        self.createdIds = createdIds
    }

    /// Decodes the response for `callID`. A method-level error response is thrown as `JMAPError.method`.
    public func result<T: Decodable>(_ type: T.Type = T.self, callID: String) throws -> T {
        guard let inv = methodResponses.first(where: { $0.callID == callID }) else { throw JMAPError.missingResponse(callID: callID) }
        if inv.name == "error" {
            throw JMAPError.method(type: inv.arguments["type"]?.stringValue ?? "serverFail", description: inv.arguments["description"]?.stringValue)
        }
        let data = try JMAPCoding.makeEncoder().encode(inv.arguments)
        return try JMAPCoding.makeDecoder().decode(T.self, from: data)
    }

    /// All responses sharing a call id (EmailSubmission/set answers with an implicit Email/set under the same id).
    public func results<T: Decodable>(_ type: T.Type = T.self, callID: String, name: String) throws -> T {
        guard let inv = methodResponses.first(where: { $0.callID == callID && ($0.name == name || $0.name == "error") }) else {
            throw JMAPError.missingResponse(callID: callID)
        }
        return try JMAPResponse(methodResponses: [inv]).result(T.self, callID: callID)
    }
}
