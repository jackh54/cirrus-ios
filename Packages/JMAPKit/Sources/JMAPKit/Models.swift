import Foundation

// MARK: - Session (RFC 8620 §2)

public struct JMAPSession: Sendable, Codable, Equatable {
    public struct Account: Sendable, Codable, Equatable {
        public var name: String
        public var isPersonal: Bool
        public var isReadOnly: Bool
        public var accountCapabilities: [String: JSONValue]?
    }

    public var capabilities: [String: JSONValue]
    public var accounts: [String: Account]
    public var primaryAccounts: [String: String]
    public var username: String
    public var apiUrl: String
    public var downloadUrl: String
    public var uploadUrl: String
    public var eventSourceUrl: String?
    public var state: String

    /// Accounts that can hold mail: the primary mail account first, then by name.
    public var mailAccounts: [(id: String, account: Account)] {
        let primary = primaryAccounts[Capability.mail]
        return accounts
            .filter { $0.value.accountCapabilities?[Capability.mail] != nil }
            .map { (id: $0.key, account: $0.value) }
            .sorted { ($0.id == primary ? 0 : 1, $0.account.name) < ($1.id == primary ? 0 : 1, $1.account.name) }
    }
}

// MARK: - Mailbox (RFC 8621 §2)

public struct Mailbox: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var parentId: String?
    public var role: String?
    public var sortOrder: Int?
    public var totalEmails: Int?
    public var unreadEmails: Int?
    public var totalThreads: Int?
    public var unreadThreads: Int?
    public var isSubscribed: Bool?
    /// Cirrus vendor extension (`urn:cirrus:params:jmap:labels`): `folder` or `label`.
    public var cirrusKind: String?
    public var cirrusColor: String?

    public init(id: String, name: String, parentId: String? = nil, role: String? = nil, sortOrder: Int? = nil,
                totalEmails: Int? = nil, unreadEmails: Int? = nil, totalThreads: Int? = nil, unreadThreads: Int? = nil,
                isSubscribed: Bool? = nil, cirrusKind: String? = nil, cirrusColor: String? = nil) {
        self.id = id; self.name = name; self.parentId = parentId; self.role = role; self.sortOrder = sortOrder
        self.totalEmails = totalEmails; self.unreadEmails = unreadEmails; self.totalThreads = totalThreads
        self.unreadThreads = unreadThreads; self.isSubscribed = isSubscribed; self.cirrusKind = cirrusKind; self.cirrusColor = cirrusColor
    }

    /// Labels have `cirrusKind == "label"`; everything else (including servers without the extension) is a folder.
    public var isLabel: Bool { cirrusKind == "label" }
}

// MARK: - Email (RFC 8621 §4)

public struct EmailAddress: Sendable, Codable, Hashable {
    public var name: String?
    public var email: String

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return email
    }
}

public struct EmailBodyPart: Sendable, Codable, Hashable, Identifiable {
    public var partId: String?
    public var blobId: String?
    public var size: Int?
    public var name: String?
    public var type: String?
    public var charset: String?
    public var disposition: String?
    public var cid: String?

    public init(partId: String? = nil, blobId: String? = nil, size: Int? = nil, name: String? = nil, type: String? = nil,
                charset: String? = nil, disposition: String? = nil, cid: String? = nil) {
        self.partId = partId; self.blobId = blobId; self.size = size; self.name = name; self.type = type
        self.charset = charset; self.disposition = disposition; self.cid = cid
    }

    public var id: String { blobId ?? partId ?? name ?? "" }
}

public struct EmailBodyValue: Sendable, Codable, Hashable {
    public var value: String
    public var isEncodingProblem: Bool?
    public var isTruncated: Bool?

    public init(value: String, isEncodingProblem: Bool? = nil, isTruncated: Bool? = nil) {
        self.value = value; self.isEncodingProblem = isEncodingProblem; self.isTruncated = isTruncated
    }
}

public struct Email: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var blobId: String?
    public var threadId: String?
    public var mailboxIds: [String: Bool]?
    public var keywords: [String: Bool]?
    public var size: Int?
    public var receivedAt: Date?
    public var sentAt: Date?
    public var messageId: [String]?
    public var inReplyTo: [String]?
    public var references: [String]?
    public var from: [EmailAddress]?
    public var to: [EmailAddress]?
    public var cc: [EmailAddress]?
    public var bcc: [EmailAddress]?
    public var replyTo: [EmailAddress]?
    public var subject: String?
    public var hasAttachment: Bool?
    public var preview: String?
    public var bodyValues: [String: EmailBodyValue]?
    public var textBody: [EmailBodyPart]?
    public var htmlBody: [EmailBodyPart]?
    public var attachments: [EmailBodyPart]?

    public init(id: String, threadId: String? = nil, mailboxIds: [String: Bool]? = nil, keywords: [String: Bool]? = nil,
                receivedAt: Date? = nil, from: [EmailAddress]? = nil, to: [EmailAddress]? = nil, subject: String? = nil,
                hasAttachment: Bool? = nil, preview: String? = nil) {
        self.id = id; self.threadId = threadId; self.mailboxIds = mailboxIds; self.keywords = keywords
        self.receivedAt = receivedAt; self.from = from; self.to = to; self.subject = subject
        self.hasAttachment = hasAttachment; self.preview = preview
    }

    public var isUnread: Bool { keywords?[Keyword.seen] != true }
    public var isFlagged: Bool { keywords?[Keyword.flagged] == true }
    public var isDraft: Bool { keywords?[Keyword.draft] == true }

    /// The text of the HTML body parts, or nil when the message has none (plain-text messages list their text part in `htmlBody` too).
    public var htmlText: String? {
        let parts = (htmlBody ?? []).filter { $0.type?.lowercased() == "text/html" }
        let joined = parts.compactMap { $0.partId.flatMap { bodyValues?[$0]?.value } }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    public var plainText: String {
        (textBody ?? []).compactMap { $0.partId.flatMap { bodyValues?[$0]?.value } }.joined(separator: "\n")
    }

    /// Real attachments (not inline images referenced by Content-ID).
    public var fileAttachments: [EmailBodyPart] {
        (attachments ?? []).filter { $0.blobId != nil }
    }
}

public enum Keyword {
    public static let seen = "$seen"
    public static let flagged = "$flagged"
    public static let draft = "$draft"
}

public struct JMAPThread: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var emailIds: [String]

    public init(id: String, emailIds: [String]) {
        self.id = id
        self.emailIds = emailIds
    }
}

public struct Identity: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var email: String
    public var textSignature: String?
    public var htmlSignature: String?
}

// MARK: - Method responses

public struct GetResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public var accountId: String
    public var state: String
    public var list: [T]
    public var notFound: [String]?
}

public struct ChangesResponse: Codable, Sendable, Equatable {
    public var accountId: String
    public var oldState: String
    public var newState: String
    public var hasMoreChanges: Bool
    public var created: [String]
    public var updated: [String]
    public var destroyed: [String]
    public var updatedProperties: [String]?
}

public struct QueryResponse: Codable, Sendable, Equatable {
    public var accountId: String
    public var queryState: String
    public var canCalculateChanges: Bool
    public var position: Int
    public var ids: [String]
    public var total: Int?
    public var limit: Int?
}

public struct SetError: Codable, Sendable, Equatable {
    public var type: String
    public var description: String?
    public var properties: [String]?
}

public struct CreatedObject: Codable, Sendable, Equatable {
    public var id: String
    public var blobId: String?
    public var threadId: String?
    public var size: Int?
}

public struct SetResponse<Created: Codable & Sendable>: Codable, Sendable {
    public var accountId: String
    public var oldState: String?
    public var newState: String?
    public var created: [String: Created]?
    public var updated: [String: JSONValue]?
    public var destroyed: [String]?
    public var notCreated: [String: SetError]?
    public var notUpdated: [String: SetError]?
    public var notDestroyed: [String: SetError]?

    /// The first failure reported by the server, if any, as an error the UI can show.
    public var firstError: JMAPError? {
        let all = [notCreated, notUpdated, notDestroyed].compactMap { $0 }.flatMap { $0.values }
        guard let e = all.first else { return nil }
        return .method(type: e.type, description: e.description)
    }
}

public struct UploadResponse: Codable, Sendable, Equatable {
    public var accountId: String
    public var blobId: String
    public var type: String
    public var size: Int
}

/// An EventSource `state` event (RFC 8620 §7.1): `changed[accountId][type] = newState`.
public struct StateChange: Codable, Sendable, Equatable {
    public var changed: [String: [String: String]]

    public init(changed: [String: [String: String]]) { self.changed = changed }

    private enum CodingKeys: String, CodingKey { case changed }
}
