#if DEBUG
import Foundation
import JMAPKit

/// Debug builds only: signs in from environment variables and runs the main flows against a dev server, logging results to a file.
/// Env: CIRRUS_DEBUG_SERVER, CIRRUS_DEBUG_EMAIL, CIRRUS_DEBUG_PASSWORD, CIRRUS_DEBUG_LOG (optional: CIRRUS_DEBUG_SCRIPT=1 runs the flows).
@MainActor enum DebugDriver {
    static func run(_ model: AppModel) async {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["CIRRUS_DEBUG_SERVER"], let email = env["CIRRUS_DEBUG_EMAIL"], let password = env["CIRRUS_DEBUG_PASSWORD"] else { return }
        let logPath = env["CIRRUS_DEBUG_LOG"] ?? NSTemporaryDirectory() + "cirrus-debug.log"
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        func log(_ s: String) {
            if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(Data((s + "\n").utf8)); try? h.close() }
        }
        if model.selectedStore == nil {
            do { try await model.signIn(server: server, email: email, password: password); log("sign-in ok") } catch { log("sign-in FAILED: \(error.localizedDescription)"); return }
        }
        guard let store = model.selectedStore, env["CIRRUS_DEBUG_SCRIPT"] == "1" else { return }
        await store.sync()
        log("mailboxes: " + store.cache.mailboxes.map { "\($0.name)(\($0.role ?? "-"),\($0.unreadThreads ?? 0))" }.joined(separator: ", "))
        guard let inbox = store.inbox else { log("no inbox"); return }
        do {
            let r = try await store.client.call(Requests.threadListPage(account: store.accountID, filter: Requests.inMailbox(inbox.id), position: 0, limit: 40))
            log("raw ok: \(r.methodResponses.map(\.name))")
            _ = try r.result(QueryResponse.self, callID: "q"); log("q ok")
            _ = try r.result(GetResponse<Email>.self, callID: "e"); log("e ok")
            _ = try r.result(GetResponse<JMAPThread>.self, callID: "t"); log("t ok")
        } catch { log("raw FAILED: \(error)") }
        await store.refresh(mailboxID: inbox.id)
        var rows = store.rows(in: inbox.id)
        log("inbox rows: \(rows.count); error: \(store.lastError ?? "none"); offline: \(store.isOffline); list ids: \(store.cache.lists[inbox.id]?.ids.count ?? -1); emails: \(store.cache.emails.count)")
        guard let first = rows.first else { return }
        do {
            let emails = try await store.loadThread(first.id)
            log("thread \(emails.count) msgs; html: \(emails.last?.htmlText != nil); text chars: \(emails.last?.plainText.count ?? 0); attachments: \(emails.last?.fileAttachments.count ?? 0)")
        } catch { log("thread FAILED: \(error.localizedDescription)") }
        for (i, r) in rows.enumerated() {
            if let e = try? await store.loadThread(r.id), let last = e.last { log("row \(i): \(last.displaySubject) html=\(last.htmlText != nil) att=\(last.fileAttachments.count) msgs=\(e.count)") }
        }
        await store.perform(.flag(!first.email.isFlagged), on: first, in: inbox.id)
        log("flag: error \(store.lastError ?? "none")")
        if rows.count > 1 {
            let target = rows[1]
            await store.perform(.archive, on: target, in: inbox.id)
            log("archive: error \(store.lastError ?? "none"); rows now \(store.rows(in: inbox.id).count)")
        }
        await store.refresh(mailboxID: inbox.id)
        rows = store.rows(in: inbox.id)
        log("after refresh: \(rows.count) rows; first flagged: \(rows.first?.email.isFlagged ?? false)")
        if store.identities.isEmpty { await store.loadIdentities() }
        guard let identity = store.identities.first else { log("no identity"); return }
        let draft = Draft(from: EmailAddress(name: identity.name, email: identity.email), to: [EmailAddress(email: email)],
                          subject: "Hello from Cirrus iOS", body: "Sent by the debug driver.")
        do { try await store.send(draft, identityID: identity.id); log("send ok") } catch { log("send FAILED: \(error.localizedDescription)") }
        if let sent = store.mailbox(role: "sent") { await store.refresh(mailboxID: sent.id); log("sent rows: \(store.rows(in: sent.id).map { $0.email.displaySubject })") }
    }
}
#endif
