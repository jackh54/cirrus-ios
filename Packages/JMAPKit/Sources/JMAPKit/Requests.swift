import Foundation

/// Builders for the method calls the app makes. Names, arguments and properties follow what the Cirrus server implements.
public enum Requests {
    public static let summaryProperties = ["id", "threadId", "mailboxIds", "keywords", "from", "to", "subject", "receivedAt", "preview", "hasAttachment"]
    public static let detailProperties = summaryProperties + [
        "blobId", "messageId", "inReplyTo", "references", "replyTo", "cc", "bcc", "sentAt", "bodyValues", "textBody", "htmlBody", "attachments",
    ]

    // MARK: Mailbox

    public static func mailboxGet(account: String, ids: IDSource = .all, callID: String = "mb") -> Invocation {
        var args: [String: JSONValue] = ["accountId": .string(account)]
        ids.add(to: &args)
        return Invocation(name: "Mailbox/get", arguments: args, callID: callID)
    }

    public static func mailboxChanges(account: String, sinceState: String, callID: String = "mbc") -> Invocation {
        Invocation(name: "Mailbox/changes", arguments: ["accountId": .string(account), "sinceState": .string(sinceState)], callID: callID)
    }

    // MARK: Email

    public static func emailQuery(account: String, filter: JSONValue? = nil, collapseThreads: Bool = true, position: Int = 0,
                                  limit: Int = 50, calculateTotal: Bool = false, callID: String = "q") -> Invocation {
        var args: [String: JSONValue] = [
            "accountId": .string(account),
            "sort": [["property": "receivedAt", "isAscending": false]],
            "collapseThreads": .bool(collapseThreads),
            "position": .int(position),
            "limit": .int(limit),
            "calculateTotal": .bool(calculateTotal),
        ]
        if let filter { args["filter"] = filter }
        return Invocation(name: "Email/query", arguments: args, callID: callID)
    }

    public static func emailGet(account: String, ids: IDSource, properties: [String]? = nil, bodyValues: Bool = false, callID: String) -> Invocation {
        var args: [String: JSONValue] = ["accountId": .string(account)]
        ids.add(to: &args)
        if let properties { args["properties"] = .strings(properties) }
        if bodyValues {
            args["fetchTextBodyValues"] = true
            args["fetchHTMLBodyValues"] = true
        }
        return Invocation(name: "Email/get", arguments: args, callID: callID)
    }

    public static func emailChanges(account: String, sinceState: String, maxChanges: Int = 500, callID: String = "ec") -> Invocation {
        Invocation(name: "Email/changes", arguments: [
            "accountId": .string(account), "sinceState": .string(sinceState), "maxChanges": .int(maxChanges),
        ], callID: callID)
    }

    public static func emailSet(account: String, create: [String: JSONValue]? = nil, update: [String: JSONValue]? = nil,
                                destroy: [String]? = nil, callID: String) -> Invocation {
        var args: [String: JSONValue] = ["accountId": .string(account)]
        if let create { args["create"] = .object(create) }
        if let update { args["update"] = .object(update) }
        if let destroy { args["destroy"] = .strings(destroy) }
        return Invocation(name: "Email/set", arguments: args, callID: callID)
    }

    // MARK: Thread and identity

    public static func threadGet(account: String, ids: IDSource, callID: String) -> Invocation {
        var args: [String: JSONValue] = ["accountId": .string(account)]
        ids.add(to: &args)
        return Invocation(name: "Thread/get", arguments: args, callID: callID)
    }

    public static func identityGet(account: String, callID: String = "id") -> Invocation {
        Invocation(name: "Identity/get", arguments: ["accountId": .string(account), "ids": .null], callID: callID)
    }

    // MARK: Compound requests

    /// One thread-list page: Email/query (collapsed), Email/get of those ids and Thread/get of their thread ids, all via back-references.
    /// Responses: `q` (QueryResponse), `e` (GetResponse<Email>), `t` (GetResponse<JMAPThread>).
    public static func threadListPage(account: String, filter: JSONValue?, position: Int, limit: Int) -> [Invocation] {
        [
            emailQuery(account: account, filter: filter, position: position, limit: limit, callID: "q"),
            emailGet(account: account, ids: .reference(.init(resultOf: "q", name: "Email/query", path: "/ids")),
                     properties: summaryProperties, callID: "e"),
            threadGet(account: account, ids: .reference(.init(resultOf: "e", name: "Email/get", path: "/list/*/threadId")), callID: "t"),
        ]
    }

    /// Every message of a thread with bodies. Responses: `t` (GetResponse<JMAPThread>), `e` (GetResponse<Email>).
    public static func threadDetail(account: String, threadID: String) -> [Invocation] {
        [
            threadGet(account: account, ids: .ids([threadID]), callID: "t"),
            emailGet(account: account, ids: .reference(.init(resultOf: "t", name: "Thread/get", path: "/list/*/emailIds")),
                     properties: detailProperties, bodyValues: true, callID: "e"),
        ]
    }

    /// Creates a plain-text draft (Email/set) and submits it (EmailSubmission/set). `onSuccessUpdateEmail` moves it out of Drafts.
    /// Responses: `draft` (SetResponse<CreatedObject>), `send` (EmailSubmission/set) and the implicit Email/set under `send`.
    public static func sendMessage(account: String, draft: Draft, identityID: String, draftsMailboxID: String, sentMailboxID: String?) -> [Invocation] {
        func addresses(_ list: [EmailAddress]) -> JSONValue {
            .array(list.map { a in
                var o: [String: JSONValue] = ["email": .string(a.email)]
                if let n = a.name, !n.isEmpty { o["name"] = .string(n) }
                return .object(o)
            })
        }
        var email: [String: JSONValue] = [
            "mailboxIds": [draftsMailboxID: true],
            "keywords": ["$draft": true],
            "from": addresses([draft.from]),
            "to": addresses(draft.to),
            "subject": .string(draft.subject),
            "textBody": [["partId": "1", "type": "text/plain"]],
            "bodyValues": ["1": ["value": .string(draft.body)]],
        ]
        if !draft.cc.isEmpty { email["cc"] = addresses(draft.cc) }
        if !draft.bcc.isEmpty { email["bcc"] = addresses(draft.bcc) }
        if !draft.inReplyTo.isEmpty { email["inReplyTo"] = .strings(draft.inReplyTo) }
        if !draft.references.isEmpty { email["references"] = .strings(draft.references) }
        if !draft.attachments.isEmpty {
            email["attachments"] = .array(draft.attachments.map { a in
                var o: [String: JSONValue] = ["blobId": .string(a.blobId ?? ""), "disposition": "attachment"]
                if let n = a.name { o["name"] = .string(n) }
                if let t = a.type { o["type"] = .string(t) }
                return .object(o)
            })
        }

        var patch: [String: JSONValue] = [
            "mailboxIds/" + draftsMailboxID: .null,
            "keywords/$draft": .null,
            "keywords/$seen": true,
        ]
        if let sentMailboxID { patch["mailboxIds/" + sentMailboxID] = true }
        return [
            emailSet(account: account, create: ["draft": .object(email)], callID: "draft"),
            Invocation(name: "EmailSubmission/set", arguments: [
                "accountId": .string(account),
                "create": ["s1": ["identityId": .string(identityID), "emailId": "#draft"]],
                "onSuccessUpdateEmail": ["#s1": .object(patch)],
            ], callID: "send"),
        ]
    }

    // MARK: Filters

    public static func inMailbox(_ id: String) -> JSONValue { ["inMailbox": .string(id)] }
    public static func text(_ query: String) -> JSONValue { ["text": .string(query)] }
}

/// A plain-text message to send.
public struct Draft: Sendable, Equatable {
    public var from: EmailAddress
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String
    public var body: String
    public var inReplyTo: [String]
    public var references: [String]
    public var attachments: [EmailBodyPart]

    public init(from: EmailAddress, to: [EmailAddress], cc: [EmailAddress] = [], bcc: [EmailAddress] = [], subject: String, body: String,
                inReplyTo: [String] = [], references: [String] = [], attachments: [EmailBodyPart] = []) {
        self.from = from; self.to = to; self.cc = cc; self.bcc = bcc; self.subject = subject; self.body = body
        self.inReplyTo = inReplyTo; self.references = references; self.attachments = attachments
    }
}
