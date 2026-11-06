import Foundation
import JMAPKit

/// What is kept on disk per JMAP account so launch is instant and mail reads offline. Plain Codable JSON, no secrets.
struct AccountCache: Codable, Sendable {
    struct ListEntry: Codable, Sendable {
        var ids: [String] = []
        var total: Int?
        var hasMore = true
    }

    var mailboxes: [Mailbox] = []
    var mailboxState: String?
    var emailState: String?
    var identities: [Identity] = []
    var lists: [String: ListEntry] = [:]
    var emails: [String: Email] = [:]
    var threads: [String: JMAPThread] = [:]
    /// Opened threads with bodies, newest use last; capped so the file stays small.
    var details: [String: [Email]] = [:]
    var detailOrder: [String] = []

    static let maxDetails = 60
    static let maxListLength = 200

    mutating func storeDetail(_ emails: [Email], threadID: String) {
        details[threadID] = emails
        detailOrder.removeAll { $0 == threadID }
        detailOrder.append(threadID)
        while detailOrder.count > Self.maxDetails { details[detailOrder.removeFirst()] = nil }
    }

    /// Keeps cached emails only while a list or an opened thread still refers to them.
    mutating func prune() {
        var keep = Set(lists.values.flatMap(\.ids))
        for mails in details.values { keep.formUnion(mails.map(\.id)) }
        emails = emails.filter { keep.contains($0.key) }
        let threadIDs = Set(emails.values.compactMap(\.threadId))
        threads = threads.filter { threadIDs.contains($0.key) }
    }
}

enum CacheFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cirrus", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    static func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JMAPCoding.makeDecoder().decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JMAPCoding.makeEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(prefix: String) {
        let p = prefix.replacingOccurrences(of: "/", with: "_")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for f in files where f.hasPrefix(p) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(f)) }
    }
}
