import Foundation
import Testing
@testable import JMAPKit

private func decodeResponse(_ json: String) throws -> JMAPResponse {
    try JMAPCoding.makeDecoder().decode(JMAPResponse.self, from: Data(json.utf8))
}

private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JMAPCoding.makeEncoder().encode(value))
}

// MARK: - Request encoding

@Suite("Request encoding")
struct RequestEncodingTests {
    @Test func invocationEncodesAsTriple() throws {
        let inv = Requests.mailboxGet(account: "A1")
        let array = try #require(try jsonObject(inv) as? [Any])
        #expect(array.count == 3)
        #expect(array[0] as? String == "Mailbox/get")
        #expect(array[2] as? String == "mb")
        let args = try #require(array[1] as? [String: Any])
        #expect(args["accountId"] as? String == "A1")
        #expect(args["ids"] is NSNull)
    }

    @Test func requestCarriesUsingAndMethodCalls() throws {
        let req = JMAPRequest(using: Capability.mailAndSubmission, methodCalls: [Requests.identityGet(account: "A1")])
        let obj = try #require(try jsonObject(req) as? [String: Any])
        #expect(obj["using"] as? [String] == ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission"])
        #expect((obj["methodCalls"] as? [Any])?.count == 1)
        #expect(obj["createdIds"] == nil)
    }

    @Test func requestRoundTrips() throws {
        let req = JMAPRequest(using: [Capability.core], methodCalls: Requests.threadListPage(account: "A1", filter: Requests.inMailbox("f_inbox"), position: 0, limit: 50))
        let back = try JMAPCoding.makeDecoder().decode(JMAPRequest.self, from: JMAPCoding.makeEncoder().encode(req))
        #expect(back == req)
    }

    @Test func emailQueryUsesCollapseSortAndFilter() throws {
        let inv = Requests.emailQuery(account: "A1", filter: Requests.text("lunch"), position: 50, limit: 25)
        #expect(inv.name == "Email/query")
        #expect(inv.arguments["collapseThreads"] == true)
        #expect(inv.arguments["position"] == 50)
        #expect(inv.arguments["limit"] == 25)
        #expect(inv.arguments["filter"] == ["text": "lunch"])
        #expect(inv.arguments["sort"] == [["property": "receivedAt", "isAscending": false]])
    }

    @Test func changesCarrySinceState() {
        let inv = Requests.emailChanges(account: "A1", sinceState: "88")
        #expect(inv.name == "Email/changes")
        #expect(inv.arguments["sinceState"] == "88")
        #expect(inv.arguments["maxChanges"] == 500)
        #expect(Requests.mailboxChanges(account: "A1", sinceState: "12").name == "Mailbox/changes")
    }

    @Test func literalIDsAreSentAsPlainKey() {
        let inv = Requests.emailGet(account: "A1", ids: .ids(["m1", "m2"]), properties: ["id"], callID: "x")
        #expect(inv.arguments["ids"] == ["m1", "m2"])
        #expect(inv.arguments["#ids"] == nil)
        #expect(inv.arguments["properties"] == ["id"])
    }

    @Test func bodyValuesRequestFetchesTextAndHTML() {
        let inv = Requests.emailGet(account: "A1", ids: .ids(["m1"]), bodyValues: true, callID: "x")
        #expect(inv.arguments["fetchTextBodyValues"] == true)
        #expect(inv.arguments["fetchHTMLBodyValues"] == true)
    }
}

// MARK: - Back-references

@Suite("Back-references")
struct BackReferenceTests {
    @Test func threadListPageChainsQueryGetAndThread() throws {
        let calls = Requests.threadListPage(account: "A1", filter: nil, position: 0, limit: 50)
        #expect(calls.map(\.name) == ["Email/query", "Email/get", "Thread/get"])
        #expect(calls.map(\.callID) == ["q", "e", "t"])

        let get = calls[1].arguments
        #expect(get["ids"] == nil, "a referenced argument is sent as #ids only")
        #expect(get["#ids"] == ["resultOf": "q", "name": "Email/query", "path": "/ids"])

        let thread = calls[2].arguments
        #expect(thread["#ids"] == ["resultOf": "e", "name": "Email/get", "path": "/list/*/threadId"])
    }

    @Test func threadDetailReferencesEmailIdsWithWildcard() {
        let calls = Requests.threadDetail(account: "A1", threadID: "t1")
        #expect(calls[0].arguments["ids"] == ["t1"])
        #expect(calls[1].arguments["#ids"] == ["resultOf": "t", "name": "Thread/get", "path": "/list/*/emailIds"])
        #expect(calls[1].arguments["fetchHTMLBodyValues"] == true)
    }

    @Test func referenceEncodesInsideTheWireTriple() throws {
        let inv = Requests.threadListPage(account: "A1", filter: nil, position: 0, limit: 5)[1]
        let array = try #require(try jsonObject(inv) as? [Any])
        let args = try #require(array[1] as? [String: Any])
        let ref = try #require(args["#ids"] as? [String: String])
        #expect(ref == ["resultOf": "q", "name": "Email/query", "path": "/ids"])
    }

    @Test func sendUsesCreationIdAndOnSuccessUpdate() throws {
        let draft = Draft(from: EmailAddress(name: "Me", email: "me@example.com"), to: [EmailAddress(email: "ada@example.org")],
                          subject: "Hi", body: "Hello", inReplyTo: ["abc@example.org"], references: ["root@example.com", "abc@example.org"])
        let calls = Requests.sendMessage(account: "A1", draft: draft, identityID: "A1", draftsMailboxID: "f_drafts", sentMailboxID: "f_sent")
        #expect(calls.map(\.name) == ["Email/set", "EmailSubmission/set"])

        let create = try #require(calls[0].arguments["create"]?["draft"])
        #expect(create["mailboxIds"] == ["f_drafts": true])
        #expect(create["keywords"] == ["$draft": true])
        #expect(create["from"] == [["email": "me@example.com", "name": "Me"]])
        #expect(create["inReplyTo"] == ["abc@example.org"])
        #expect(create["textBody"] == [["partId": "1", "type": "text/plain"]])
        #expect(create["bodyValues"] == ["1": ["value": "Hello"]])
        #expect(create["cc"] == nil)

        let sub = calls[1].arguments
        #expect(sub["create"] == ["s1": ["identityId": "A1", "emailId": "#draft"]])
        let patch = try #require(sub["onSuccessUpdateEmail"]?["#s1"])
        #expect(patch["mailboxIds/f_drafts"] == .null)
        #expect(patch["mailboxIds/f_sent"] == true)
        #expect(patch["keywords/$draft"] == .null)
    }

    @Test func forwardedAttachmentsAreReferencedByBlob() throws {
        let part = EmailBodyPart(blobId: "a_att1", name: "menu.pdf", type: "application/pdf")
        let draft = Draft(from: EmailAddress(email: "me@example.com"), to: [EmailAddress(email: "x@example.org")], subject: "Fwd: x", body: "", attachments: [part])
        let create = try #require(Requests.sendMessage(account: "A1", draft: draft, identityID: "A1", draftsMailboxID: "d", sentMailboxID: nil)[0].arguments["create"]?["draft"])
        #expect(create["attachments"] == [["blobId": "a_att1", "disposition": "attachment", "name": "menu.pdf", "type": "application/pdf"]])
    }
}

// MARK: - Response decoding

@Suite("Response decoding")
struct ResponseDecodingTests {
    @Test func sessionDecodesAndListsMailAccounts() throws {
        let session = try JMAPCoding.makeDecoder().decode(JMAPSession.self, from: Data(Fixtures.session.utf8))
        #expect(session.username == "me@example.com")
        #expect(session.apiUrl == "https://cirrus.example.com/jmap/api")
        #expect(session.mailAccounts.map(\.id) == ["01HZPERSONAL", "01HZSHARED"])
        #expect(session.mailAccounts.first?.account.isPersonal == true)
        #expect(session.accounts["01HZSHARED"]?.isPersonal == false)
    }

    @Test func mailboxGetDecodesRolesCountsAndLabels() throws {
        let list = try decodeResponse(Fixtures.mailboxGet).result(GetResponse<Mailbox>.self, callID: "mb")
        #expect(list.state == "12")
        #expect(list.list.map(\.role) == ["inbox", "junk", nil])
        #expect(list.list[0].unreadEmails == 3)
        #expect(list.list[0].isLabel == false)
        #expect(list.list[2].isLabel == true)
        #expect(list.list[2].cirrusColor == "#2B63E8")
    }

    @Test func threadListPageDecodesAllThreeResponses() throws {
        let r = try decodeResponse(Fixtures.threadListPage)
        let query = try r.result(QueryResponse.self, callID: "q")
        #expect(query.ids == ["m2", "m9"])
        #expect(query.canCalculateChanges == false)
        #expect(query.total == 2)

        let emails = try r.result(GetResponse<Email>.self, callID: "e")
        #expect(emails.list.count == 2)
        let first = emails.list[0]
        #expect(first.isUnread == false)
        #expect(first.isFlagged == true)
        #expect(first.mailboxIds == ["f_inbox": true, "l_work": true])
        #expect(first.from?.first?.displayName == "Ada")
        #expect(first.to?.first?.displayName == "me@example.com")
        #expect(emails.list[1].isUnread == true)
        #expect(emails.list[1].from?.first?.displayName == "news@example.net", "an empty name falls back to the address")
        #expect(emails.list[1].to == nil)

        let threads = try r.result(GetResponse<JMAPThread>.self, callID: "t")
        #expect(threads.list.first { $0.id == "t1" }?.emailIds == ["m1", "m2"])
    }

    @Test func datesParseWithAndWithoutFractionalSeconds() throws {
        let emails = try decodeResponse(Fixtures.threadListPage).result(GetResponse<Email>.self, callID: "e").list
        let a = try #require(emails[0].receivedAt), b = try #require(emails[1].receivedAt)
        #expect(a == Date(timeIntervalSince1970: 1_793_871_000))
        #expect(b.timeIntervalSince1970 == 1_793_815_200.25)
    }

    @Test func emailDetailExposesBodiesAndAttachments() throws {
        let get = try decodeResponse(Fixtures.emailDetail).result(GetResponse<Email>.self, callID: "e")
        #expect(get.notFound == ["gone"])
        let email = try #require(get.list.first)
        #expect(email.plainText == "Friday works")
        #expect(email.htmlText == "<p>Friday works</p>")
        #expect(email.fileAttachments.map(\.name) == ["menu.pdf"])
        #expect(email.fileAttachments.first?.blobId == "a_att1")
        #expect(email.messageId == ["abc@example.org"])
        #expect(email.references == ["root@example.com"])
    }

    @Test func plainTextMessagesHaveNoHTML() throws {
        let email = try JMAPCoding.makeDecoder().decode(Email.self, from: Data(Fixtures.plainTextOnly.utf8))
        #expect(email.htmlText == nil, "htmlBody falls back to the text part, which is not HTML")
        #expect(email.plainText == "just text")
    }

    @Test func changesDecode() throws {
        let email = try decodeResponse(Fixtures.emailChanges).result(ChangesResponse.self, callID: "ec")
        #expect(email.oldState == "88" && email.newState == "91")
        #expect(email.created == ["m10"] && email.updated == ["m2"] && email.destroyed == ["m5"])
        #expect(email.hasMoreChanges == false)

        let mb = try decodeResponse(Fixtures.mailboxChanges).result(ChangesResponse.self, callID: "mbc")
        #expect(mb.updatedProperties?.count == 4)
    }

    @Test func mailboxMergeAppliesDelta() throws {
        let current = try decodeResponse(Fixtures.mailboxGet).result(GetResponse<Mailbox>.self, callID: "mb").list + [Mailbox(id: "l_old", name: "Old", sortOrder: 1000)]
        let changes = try decodeResponse(Fixtures.mailboxChanges).result(ChangesResponse.self, callID: "mbc")
        var inbox = current[0]
        inbox.unreadEmails = 9
        let merged = Mailbox.merge(current, changes: changes, fetched: [inbox])
        #expect(merged.map(\.id) == ["f_inbox", "f_spam", "l_work"])
        #expect(merged[0].unreadEmails == 9)
    }

    @Test func setResponsesDecodeCreatedAndImplicitUpdate() throws {
        let r = try decodeResponse(Fixtures.sendResult)
        let draft = try r.result(SetResponse<CreatedObject>.self, callID: "draft")
        #expect(draft.created?["draft"]?.id == "d1")
        #expect(draft.firstError == nil)

        let sub = try r.results(SetResponse<JSONValue>.self, callID: "send", name: "EmailSubmission/set")
        #expect(sub.created?["s1"]?["undoStatus"] == "final")

        let implicit = try r.methodResponses.last.map { try JMAPResponse(methodResponses: [$0]).result(SetResponse<CreatedObject>.self, callID: "send") }
        #expect(implicit?.updated?["d1"] == .null)
        #expect(implicit?.newState == "90")
    }

    @Test func notCreatedSurfacesAsAnError() throws {
        let sub = try decodeResponse(Fixtures.sendRejected).results(SetResponse<JSONValue>.self, callID: "send", name: "EmailSubmission/set")
        #expect(sub.created == nil)
        #expect(sub.notCreated?["s1"]?.type == "forbiddenToSend")
        #expect(sub.firstError == .method(type: "forbiddenToSend", description: "Daily sending limit reached"))
    }

    @Test func methodErrorsAreThrown() throws {
        let r = try decodeResponse(Fixtures.methodError)
        #expect(throws: JMAPError.method(type: "cannotCalculateChanges", description: "State is too old")) {
            try r.result(ChangesResponse.self, callID: "ec")
        }
        do { _ = try r.result(ChangesResponse.self, callID: "ec") } catch let e as JMAPError { #expect(e.isCannotCalculateChanges) }
    }

    @Test func missingCallIsReported() throws {
        let r = try decodeResponse(Fixtures.emailChanges)
        #expect(throws: JMAPError.missingResponse(callID: "zzz")) { try r.result(ChangesResponse.self, callID: "zzz") }
    }
}

// MARK: - Client and EventSource

private struct MockTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) -> (Int, Data)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, data) = handler(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        throw JMAPError.invalidResponse
    }
}

@Suite("Client")
struct ClientTests {
    let credentials = Credentials(serverURL: URL(string: "https://cirrus.example.com/some/path?x=1")!, email: "me@example.com", password: "app-pass")

    @Test func discoveryUsesWellKnownAndBasicAuth() async throws {
        let seen = LockedBox<URLRequest?>(nil)
        let transport = MockTransport { req in seen.value = req; return (200, Data(Fixtures.session.utf8)) }
        let session = try await JMAPClient.discover(credentials: credentials, transport: transport)
        #expect(session.state == "a1b2c3d4e5f60708")
        #expect(seen.value?.url?.absoluteString == "https://cirrus.example.com/.well-known/jmap")
        #expect(seen.value?.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("me@example.com:app-pass".utf8).base64EncodedString())
    }

    @Test func serverURLsAreNormalised() {
        #expect(Credentials.normalizedServerURL("cirrus.example.com")?.absoluteString == "https://cirrus.example.com")
        #expect(Credentials.normalizedServerURL("  https://cirrus.example.com/mail/?a=1 ")?.absoluteString == "https://cirrus.example.com")
        #expect(Credentials.normalizedServerURL("ftp://x.example.com") == nil)
        #expect(Credentials.normalizedServerURL("nodots") == nil)
        #expect(Credentials.normalizedServerURL("") == nil)
    }

    @Test func discoveryFallsBackToSessionURL() async throws {
        let seen = LockedBox<[String]>([])
        let transport = MockTransport { req in
            seen.value.append(req.url!.path)
            return req.url!.path == "/jmap/session" ? (200, Data(Fixtures.session.utf8)) : (301, Data())
        }
        let session = try await JMAPClient.discover(credentials: credentials, transport: transport)
        #expect(session.username == "me@example.com")
        #expect(seen.value == ["/.well-known/jmap", "/jmap/session"])
    }

    @Test func redirectKeepsAuthorizationOnlyOnSameOrigin() {
        let auth = "Basic abc"
        var same = URLRequest(url: URL(string: "http://localhost:5173/jmap/session")!)
        same.setValue("stale", forHTTPHeaderField: "Authorization")
        let from = URL(string: "http://localhost:5173/.well-known/jmap")
        #expect(RedirectPolicy.follow(same, from: from, authorization: auth).value(forHTTPHeaderField: "Authorization") == auth)

        // Default ports are normalised.
        let https = URLRequest(url: URL(string: "https://cirrus.example.com:443/jmap/session")!)
        #expect(RedirectPolicy.follow(https, from: URL(string: "https://cirrus.example.com/x"), authorization: auth).value(forHTTPHeaderField: "Authorization") == auth)

        for target in ["http://evil.example/jmap/session", "http://localhost:5174/jmap/session", "https://localhost:5173/jmap/session"] {
            var other = URLRequest(url: URL(string: target)!)
            other.setValue(auth, forHTTPHeaderField: "Authorization")
            #expect(RedirectPolicy.follow(other, from: from, authorization: auth).value(forHTTPHeaderField: "Authorization") == nil, "\(target)")
        }
    }

    @Test func transportErrorsAreDistinguishedFromRejectedCredentials() {
        #expect(JMAPError(transport: URLError(.appTransportSecurityRequiresSecureConnection)) == .insecureConnection)
        if case .network = JMAPError(transport: URLError(.cannotConnectToHost)) {} else { Issue.record("expected .network") }
        #expect(JMAPError.unauthorized.errorDescription?.contains("not accepted") == true)
    }

    @Test func discoveryMaps401ToUnauthorized() async {
        let transport = MockTransport { _ in (401, Data()) }
        await #expect(throws: JMAPError.unauthorized) { try await JMAPClient.discover(credentials: credentials, transport: transport) }
    }

    @Test func discoveryRejectsNonHTTPURLs() async {
        let bad = Credentials(serverURL: URL(string: "ftp://x.example")!, email: "a@b.c", password: "p")
        await #expect(throws: JMAPError.invalidServerURL) { try await JMAPClient.discover(credentials: bad, transport: MockTransport { _ in (200, Data()) }) }
    }

    @Test func callPostsJSONToApiUrl() async throws {
        let session = try JMAPCoding.makeDecoder().decode(JMAPSession.self, from: Data(Fixtures.session.utf8))
        let seen = LockedBox<URLRequest?>(nil)
        let transport = MockTransport { req in seen.value = req; return (200, Data(Fixtures.mailboxGet.utf8)) }
        let client = JMAPClient(session: session, credentials: credentials, transport: transport)
        let response = try await client.call([Requests.mailboxGet(account: "01HZPERSONAL")])
        #expect(try response.result(GetResponse<Mailbox>.self, callID: "mb").list.count == 3)
        #expect(seen.value?.httpMethod == "POST")
        #expect(seen.value?.url?.absoluteString == "https://cirrus.example.com/jmap/api")
        #expect(seen.value?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: try #require(seen.value?.httpBody)) as? [String: Any]
        #expect((body?["using"] as? [String])?.contains(Capability.mail) == true)
    }

    @Test func downloadURLExpandsTemplate() throws {
        let session = try JMAPCoding.makeDecoder().decode(JMAPSession.self, from: Data(Fixtures.session.utf8))
        let client = JMAPClient(session: session, credentials: credentials, transport: MockTransport { _ in (200, Data()) })
        let url = client.downloadURL(accountID: "01HZPERSONAL", blobID: "a_att1", name: "lunch menu.pdf", type: "application/pdf")
        #expect(url?.absoluteString == "https://cirrus.example.com/jmap/download/01HZPERSONAL/a_att1/lunch%20menu.pdf?accept=application%2Fpdf")
    }

    @Test func problemDetailIsSurfaced() async throws {
        let session = try JMAPCoding.makeDecoder().decode(JMAPSession.self, from: Data(Fixtures.session.utf8))
        let body = Data(#"{"type":"urn:ietf:params:jmap:error:limit","status":400,"detail":"Too many method calls"}"#.utf8)
        let client = JMAPClient(session: session, credentials: credentials, transport: MockTransport { _ in (400, body) })
        await #expect(throws: JMAPError.http(status: 400, detail: "Too many method calls")) { try await client.call([]) }
    }

    @Test func eventSourceParserEmitsStateEventsOnly() {
        var p = EventSourceParser()
        #expect(p.feed(line: ":") == nil)
        #expect(p.feed(line: "event: ping") == nil)
        #expect(p.feed(line: #"data: {"interval":30}"#) == nil)
        #expect(p.feed(line: "event: state") == nil)
        let change = p.feed(line: #"data: {"@type":"StateChange","changed":{"01HZPERSONAL":{"Email":"91","Mailbox":"13"}}}"#)
        #expect(change == StateChange(changed: ["01HZPERSONAL": ["Email": "91", "Mailbox": "13"]]))
        #expect(p.feed(line: #"data: {"changed":{}}"#) == nil, "the event name resets after each data line")
    }
}

final class LockedBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
