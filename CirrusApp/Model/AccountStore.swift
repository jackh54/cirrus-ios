import Foundation
import JMAPKit
import Observation

/// A thread-list row: the newest message of a thread (Email/query with collapseThreads) plus the thread's message ids.
struct ThreadRow: Identifiable, Hashable, Sendable {
    var email: Email
    var emailIDs: [String]
    var id: String { email.threadId ?? email.id }
    var messageCount: Int { max(emailIDs.count, 1) }
}

enum ThreadAction: Sendable {
    case archive, trash
    case markRead(Bool)
    case flag(Bool)
}

/// Everything for one JMAP account (one Cirrus mailbox): cache, sync and the actions the UI calls.
@MainActor @Observable
final class AccountStore: Identifiable {
    static let pageSize = 40

    let id: String
    let loginID: String
    let accountID: String
    private(set) var name: String
    private(set) var client: JMAPClient
    private(set) var cache: AccountCache
    private(set) var isOffline = false
    private(set) var loading: Set<String> = []
    private(set) var searchRows: [ThreadRow] = []
    private(set) var isSearching = false
    var lastError: String?
    var activeMailboxID: String?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var syncRequested = false

    init(loginID: String, accountID: String, name: String, client: JMAPClient) {
        self.loginID = loginID
        self.accountID = accountID
        self.id = "\(loginID)/\(accountID)"
        self.name = name
        self.client = client
        self.cache = CacheFiles.read(AccountCache.self, name: "\(loginID)/\(accountID)") ?? AccountCache()
    }

    func update(name: String, client: JMAPClient) {
        self.name = name
        self.client = client
    }

    // MARK: Derived data

    var folders: [Mailbox] { cache.mailboxes.filter { !$0.isLabel }.sorted { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) } }
    var labels: [Mailbox] { cache.mailboxes.filter(\.isLabel).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var identities: [Identity] { cache.identities }

    func mailbox(role: String) -> Mailbox? { cache.mailboxes.first { $0.role == role } }
    func mailbox(id: String) -> Mailbox? { cache.mailboxes.first { $0.id == id } }
    var inbox: Mailbox? { mailbox(role: "inbox") }

    func rows(in mailboxID: String) -> [ThreadRow] {
        (cache.lists[mailboxID]?.ids ?? []).compactMap(row(for:))
    }

    func canLoadMore(in mailboxID: String) -> Bool { cache.lists[mailboxID]?.hasMore ?? false }

    private func row(for emailID: String) -> ThreadRow? {
        guard let email = cache.emails[emailID] else { return nil }
        let ids = email.threadId.flatMap { cache.threads[$0]?.emailIds } ?? [emailID]
        return ThreadRow(email: email, emailIDs: ids)
    }

    func cachedThread(_ threadID: String) -> [Email]? { cache.details[threadID] }

    // MARK: Cache plumbing

    private func mutate(_ body: (inout AccountCache) -> Void) {
        body(&cache)
        persist()
    }

    private func persist() {
        saveTask?.cancel()
        let name = id
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            var copy = self.cache
            copy.lists = copy.lists.mapValues { var e = $0; e.ids = Array(e.ids.prefix(AccountCache.maxListLength)); return e }
            copy.prune()
            await Task.detached(priority: .utility) { CacheFiles.write(copy, name: name) }.value
        }
    }

    func wipe() {
        saveTask?.cancel()
        CacheFiles.remove(prefix: id)
    }

    private func handle(_ error: Error) {
        if let e = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed].contains(e.code) {
            isOffline = true
        } else {
            lastError = error.localizedDescription
        }
    }

    // MARK: Thread lists

    private struct Page {
        var ids: [String]
        var emails: [Email]
        var threads: [JMAPThread]
        var emailState: String
    }

    private func fetchPage(filter: JSONValue?, position: Int) async throws -> Page {
        let response = try await client.call(Requests.threadListPage(account: accountID, filter: filter, position: position, limit: Self.pageSize))
        let query = try response.result(QueryResponse.self, callID: "q")
        let emails = try response.result(GetResponse<Email>.self, callID: "e")
        let threads = try response.result(GetResponse<JMAPThread>.self, callID: "t")
        return Page(ids: query.ids, emails: emails.list, threads: threads.list, emailState: emails.state)
    }

    func refresh(mailboxID: String) async { await loadPage(mailboxID: mailboxID, position: 0) }

    func loadMore(mailboxID: String) async {
        guard let entry = cache.lists[mailboxID], entry.hasMore else { return }
        await loadPage(mailboxID: mailboxID, position: entry.ids.count)
    }

    private func loadPage(mailboxID: String, position: Int) async {
        guard !loading.contains(mailboxID) else { return }
        loading.insert(mailboxID)
        defer { loading.remove(mailboxID) }
        do {
            let page = try await fetchPage(filter: Requests.inMailbox(mailboxID), position: position)
            mutate { c in
                for e in page.emails { c.emails[e.id] = e }
                for t in page.threads { c.threads[t.id] = t }
                var entry = c.lists[mailboxID] ?? .init()
                entry.ids = position == 0 ? page.ids : entry.ids + page.ids.filter { !entry.ids.contains($0) }
                entry.hasMore = page.ids.count >= Self.pageSize
                c.lists[mailboxID] = entry
                if c.emailState == nil { c.emailState = page.emailState }
            }
            isOffline = false
            lastError = nil
        } catch {
            handle(error)
        }
    }

    // MARK: Search

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { searchRows = []; isSearching = false; return }
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await fetchPage(filter: Requests.text(q), position: 0)
            let threads = Dictionary(page.threads.map { ($0.id, $0.emailIds) }, uniquingKeysWith: { a, _ in a })
            let byID = Dictionary(page.emails.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            searchRows = page.ids.compactMap { byID[$0] }.map { ThreadRow(email: $0, emailIDs: $0.threadId.flatMap { threads[$0] } ?? [$0.id]) }
            isOffline = false
        } catch {
            if !Task.isCancelled { handle(error) }
        }
    }

    func clearSearch() { searchRows = []; isSearching = false }

    // MARK: Threads

    func loadThread(_ threadID: String) async throws -> [Email] {
        let response = try await client.call(Requests.threadDetail(account: accountID, threadID: threadID))
        let emails = try response.result(GetResponse<Email>.self, callID: "e").list
            .sorted { ($0.receivedAt ?? .distantPast) < ($1.receivedAt ?? .distantPast) }
        mutate { $0.storeDetail(emails, threadID: threadID) }
        isOffline = false
        return emails
    }

    func markRead(_ emailIDs: [String]) async {
        guard !emailIDs.isEmpty else { return }
        setKeywordLocally(Keyword.seen, true, emailIDs)
        do {
            try await setKeyword(Keyword.seen, true, emailIDs)
            await sync(refreshActive: false)
        } catch { handle(error) }
    }

    // MARK: Actions (swipe, toolbar)

    func perform(_ action: ThreadAction, on row: ThreadRow, in mailboxID: String?) async {
        let ids = row.emailIDs
        switch action {
        case .markRead(let read): setKeywordLocally(Keyword.seen, read, ids)
        case .flag(let on): setKeywordLocally(Keyword.flagged, on, ids)
        case .archive, .trash: removeLocally(threadID: row.id, from: mailboxID)
        }
        do {
            switch action {
            case .markRead(let read): try await setKeyword(Keyword.seen, read, ids)
            case .flag(let on): try await setKeyword(Keyword.flagged, on, ids)
            case .archive:
                guard let target = mailbox(role: "archive") else { throw JMAPError.method(type: "notFound", description: "This account has no Archive folder.") }
                try await move(ids, to: target.id, viewing: mailboxID)
            case .trash:
                guard let target = mailbox(role: "trash") else { throw JMAPError.method(type: "notFound", description: "This account has no Trash folder.") }
                let viewing = mailboxID.flatMap(mailbox(id:))?.role
                if viewing == "trash" || viewing == "junk" { try await destroy(ids) } else { try await move(ids, to: target.id, viewing: mailboxID) }
            }
            await sync(refreshActive: false)
        } catch {
            handle(error)
            lastError = error.localizedDescription
            if let mailboxID { await refresh(mailboxID: mailboxID) }
        }
    }

    private func setKeywordLocally(_ keyword: String, _ on: Bool, _ ids: [String]) {
        func patch(_ e: inout Email) {
            var k = e.keywords ?? [:]
            k[keyword] = on ? true : nil
            e.keywords = k
        }
        mutate { c in
            for id in ids { if c.emails[id] != nil { patch(&c.emails[id]!) } }
            for (tid, mails) in c.details where mails.contains(where: { ids.contains($0.id) }) {
                c.details[tid] = mails.map { var m = $0; if ids.contains(m.id) { patch(&m) }; return m }
            }
        }
        for i in searchRows.indices where ids.contains(searchRows[i].email.id) { patch(&searchRows[i].email) }
    }

    private func removeLocally(threadID: String, from mailboxID: String?) {
        mutate { c in
            if let mailboxID, var entry = c.lists[mailboxID] {
                entry.ids.removeAll { c.emails[$0]?.threadId == threadID }
                c.lists[mailboxID] = entry
            }
        }
        searchRows.removeAll { $0.id == threadID }
    }

    private func setKeyword(_ keyword: String, _ on: Bool, _ ids: [String]) async throws {
        let update = Dictionary(uniqueKeysWithValues: ids.map { ($0, JSONValue.object(["keywords/" + keyword: on ? true : .null])) })
        try await runSet(Requests.emailSet(account: accountID, update: update, callID: "s"))
    }

    private func destroy(_ ids: [String]) async throws {
        try await runSet(Requests.emailSet(account: accountID, destroy: ids, callID: "s"))
    }

    /// Moves each message from its current folder to `target`. Viewing a folder moves only that folder's messages; drafts never move.
    private func move(_ ids: [String], to target: String, viewing mailboxID: String?) async throws {
        let response = try await client.call([Requests.emailGet(account: accountID, ids: .ids(ids), properties: ["id", "mailboxIds"], callID: "g")])
        let emails = try response.result(GetResponse<Email>.self, callID: "g").list
        let folderIDs = Set(folders.map(\.id))
        let drafts = mailbox(role: "drafts")?.id
        let source = mailboxID.flatMap { folderIDs.contains($0) ? $0 : nil }
        var update: [String: JSONValue] = [:]
        for e in emails {
            guard let folder = e.mailboxIds?.keys.first(where: folderIDs.contains), folder != target, folder != drafts else { continue }
            if let source, folder != source { continue }
            update[e.id] = .object(["mailboxIds/" + folder: .null, "mailboxIds/" + target: true])
        }
        guard !update.isEmpty else { return }
        try await runSet(Requests.emailSet(account: accountID, update: update, callID: "s"))
    }

    private func runSet(_ call: Invocation) async throws {
        let response = try await client.call([call])
        let result = try response.result(SetResponse<JSONValue>.self, callID: call.callID)
        if let error = result.firstError { throw error }
    }

    // MARK: Compose

    func loadIdentities() async {
        do {
            let response = try await client.call([Requests.identityGet(account: accountID)])
            let list = try response.result(GetResponse<Identity>.self, callID: "id").list
            mutate { $0.identities = list }
        } catch { handle(error) }
    }

    func send(_ draft: Draft, identityID: String) async throws {
        guard let drafts = mailbox(role: "drafts") else { throw JMAPError.method(type: "notFound", description: "This account has no Drafts folder.") }
        let response = try await client.call(Requests.sendMessage(
            account: accountID, draft: draft, identityID: identityID, draftsMailboxID: drafts.id, sentMailboxID: mailbox(role: "sent")?.id))
        if let e = try response.result(SetResponse<CreatedObject>.self, callID: "draft").firstError { throw e }
        if let e = try response.results(SetResponse<JSONValue>.self, callID: "send", name: "EmailSubmission/set").firstError {
            var reason = e.localizedDescription
            if case .method(_, let description) = e, let description { reason = description }
            throw JMAPError.method(type: "notSent", description: "Not sent, the message is saved in Drafts. \(reason)")
        }
        await sync()
    }

    // MARK: Attachments

    func downloadAttachment(_ part: EmailBodyPart) async throws -> URL {
        guard let blobID = part.blobId else { throw JMAPError.invalidResponse }
        let raw = part.name ?? "attachment"
        let name = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "_")
        let data = try await client.download(accountID: accountID, blobID: blobID, name: name, type: part.type)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("attachments/\(blobID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Sync (Mailbox/changes and Email/changes from the stored state)

    func handle(stateChange states: [String: String]) {
        let mailboxChanged = states["Mailbox"].map { $0 != cache.mailboxState } ?? false
        let emailChanged = states["Email"].map { $0 != cache.emailState } ?? false
        if mailboxChanged || emailChanged { Task { await sync() } }
    }

    func sync(refreshActive: Bool = true) async {
        if isSyncing { syncRequested = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncRequested = false
            do {
                try await syncMailboxes()
                let changed = try await syncEmails()
                if cache.identities.isEmpty { await loadIdentities() }
                isOffline = false
                if changed, refreshActive, let active = activeMailboxID { await refresh(mailboxID: active) }
            } catch {
                handle(error)
            }
        } while syncRequested
    }

    private func syncMailboxes() async throws {
        guard let since = cache.mailboxState else { return try await reloadMailboxes() }
        let response = try await client.call([Requests.mailboxChanges(account: accountID, sinceState: since)])
        let changes: ChangesResponse
        do { changes = try response.result(ChangesResponse.self, callID: "mbc") } catch let e as JMAPError where e.isCannotCalculateChanges {
            return try await reloadMailboxes()
        }
        guard changes.newState != since || !changes.updated.isEmpty || !changes.created.isEmpty || !changes.destroyed.isEmpty else { return }
        var fetched: [Mailbox] = []
        let wanted = changes.created + changes.updated
        if !wanted.isEmpty {
            let get = try await client.call([Requests.mailboxGet(account: accountID, ids: .ids(wanted))])
            fetched = try get.result(GetResponse<Mailbox>.self, callID: "mb").list
        }
        mutate { c in
            c.mailboxes = Mailbox.merge(c.mailboxes, changes: changes, fetched: fetched)
            c.mailboxState = changes.newState
        }
    }

    private func reloadMailboxes() async throws {
        let response = try await client.call([Requests.mailboxGet(account: accountID)])
        let get = try response.result(GetResponse<Mailbox>.self, callID: "mb")
        mutate { c in
            c.mailboxes = get.list
            c.mailboxState = get.state
        }
    }

    /// Applies Email/changes to the cached messages. Returns true when anything changed.
    private func syncEmails() async throws -> Bool {
        guard var state = cache.emailState else { return false }
        var changed = false
        while true {
            let response = try await client.call([Requests.emailChanges(account: accountID, sinceState: state)])
            let changes: ChangesResponse
            do { changes = try response.result(ChangesResponse.self, callID: "ec") } catch let e as JMAPError where e.isCannotCalculateChanges {
                mutate { c in
                    c.lists = [:]; c.emails = [:]; c.threads = [:]; c.details = [:]; c.detailOrder = []; c.emailState = nil
                }
                return true
            }
            if !(changes.created.isEmpty && changes.updated.isEmpty && changes.destroyed.isEmpty) {
                changed = true
                var fresh: [Email] = []
                let known = Set(cache.emails.keys).union(cache.details.values.flatMap { $0.map(\.id) })
                let refetch = (changes.created + changes.updated).filter(known.contains)
                for chunk in stride(from: 0, to: refetch.count, by: 100).map({ Array(refetch[$0..<min($0 + 100, refetch.count)]) }) {
                    let get = try await client.call([Requests.emailGet(account: accountID, ids: .ids(chunk), properties: Requests.summaryProperties, callID: "g")])
                    fresh += try get.result(GetResponse<Email>.self, callID: "g").list
                }
                let destroyed = Set(changes.destroyed)
                mutate { c in
                    for id in destroyed {
                        c.emails[id] = nil
                        for key in c.lists.keys { c.lists[key]?.ids.removeAll { $0 == id } }
                    }
                    for tid in c.details.keys { c.details[tid]?.removeAll { destroyed.contains($0.id) } }
                    for e in fresh {
                        if c.emails[e.id] != nil { c.emails[e.id] = e }
                        for (tid, mails) in c.details where mails.contains(where: { $0.id == e.id }) {
                            c.details[tid] = mails.map { m in
                                guard m.id == e.id else { return m }
                                var n = m; n.keywords = e.keywords; n.mailboxIds = e.mailboxIds; return n
                            }
                        }
                    }
                }
            }
            state = changes.newState
            mutate { $0.emailState = state }
            if !changes.hasMoreChanges { break }
        }
        return changed
    }
}
