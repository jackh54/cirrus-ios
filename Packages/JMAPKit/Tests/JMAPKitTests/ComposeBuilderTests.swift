import Foundation
import Testing
@testable import JMAPKit

@Suite("Compose builder")
struct ComposeBuilderTests {
    private func email() throws -> Email {
        let r = try JMAPCoding.makeDecoder().decode(JMAPResponse.self, from: Data(Fixtures.emailDetail.utf8))
        var e = try r.result(GetResponse<Email>.self, callID: "e").list[0]
        e.cc = [EmailAddress(name: "Bob", email: "bob@example.org"), EmailAddress(email: "ME@example.com")]
        e.to = [EmailAddress(email: "me@example.com"), EmailAddress(email: "carol@example.org")]
        return e
    }

    @Test func replyGoesToSenderAndThreads() throws {
        let seed = ComposeBuilder.seed(mode: .reply, original: try email(), myAddresses: ["me@example.com"], locale: Locale(identifier: "en_US"))
        #expect(seed.to == [EmailAddress(name: "Ada", email: "ada@example.org")])
        #expect(seed.cc.isEmpty)
        #expect(seed.subject == "Re: Lunch?")
        #expect(seed.inReplyTo == ["abc@example.org"])
        #expect(seed.references == ["root@example.com", "abc@example.org"])
        #expect(seed.body.contains("Ada wrote:"))
        #expect(seed.body.contains("> Friday works"))
    }

    @Test func replyAllDropsMyAddressesAndDuplicates() throws {
        let seed = ComposeBuilder.seed(mode: .replyAll, original: try email(), myAddresses: ["me@example.com"])
        #expect(seed.to.map(\.email) == ["ada@example.org"])
        #expect(seed.cc.map(\.email).sorted() == ["bob@example.org", "carol@example.org"])
    }

    @Test func subjectPrefixIsNotRepeated() throws {
        var e = try email()
        #expect(ComposeBuilder.seed(mode: .reply, original: e, myAddresses: []).subject == "Re: Lunch?")
        e.subject = "Lunch?"
        #expect(ComposeBuilder.seed(mode: .reply, original: e, myAddresses: []).subject == "Re: Lunch?")
        #expect(ComposeBuilder.seed(mode: .forward, original: e, myAddresses: []).subject == "Fwd: Lunch?")
    }

    @Test func forwardQuotesHeadersAndKeepsAttachments() throws {
        let seed = ComposeBuilder.seed(mode: .forward, original: try email(), myAddresses: ["me@example.com"])
        #expect(seed.to.isEmpty)
        #expect(seed.body.contains("Forwarded message"))
        #expect(seed.body.contains("From: Ada <ada@example.org>"))
        #expect(seed.attachments.map(\.blobId) == ["a_att1"])
        #expect(seed.inReplyTo.isEmpty)
    }

    @Test func replyToOwnMessageGoesToItsRecipients() throws {
        var e = try email()
        e.from = [EmailAddress(email: "me@example.com")]
        let seed = ComposeBuilder.seed(mode: .reply, original: e, myAddresses: ["me@example.com"])
        #expect(seed.to.map(\.email) == ["carol@example.org"])
    }

    @Test func newMessageIsEmpty() {
        #expect(ComposeBuilder.seed(mode: .new, original: nil, myAddresses: []) == ComposeSeed())
    }

    @Test func htmlOnlyBodiesAreStrippedForQuoting() throws {
        var e = try email()
        e.textBody = []
        e.bodyValues = ["2": EmailBodyValue(value: "<style>p{}</style><p>Hello&nbsp;<b>there</b></p><p>Bye &amp; thanks</p>")]
        #expect(e.bestPlainText == "Hello there\nBye & thanks")
    }
}
