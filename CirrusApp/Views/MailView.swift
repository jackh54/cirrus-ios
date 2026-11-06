import SwiftUI
import JMAPKit

/// The mail UI of one account: mailboxes, thread list and reader (a stack on iPhone, columns on iPad).
struct MailView: View {
    let store: AccountStore
    @State private var mailboxID: String?
    @State private var threadID: String?
    @State private var column: NavigationSplitViewColumn = .sidebar
    @State private var compose: ComposeContext?

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            SidebarView(store: store, selection: $mailboxID, onCompose: { compose = ComposeContext(mode: .new, original: nil) })
        } content: {
            if let mailboxID {
                ThreadListView(store: store, mailboxID: mailboxID, selection: $threadID, compose: $compose)
            } else {
                ContentUnavailableView("Select a mailbox", systemImage: "tray")
            }
        } detail: {
            if let threadID {
                ThreadView(store: store, threadID: threadID, compose: $compose)
                    .id(threadID)
            } else {
                ContentUnavailableView("No message selected", systemImage: "envelope")
            }
        }
        .sheet(item: $compose) { context in
            ComposeView(store: store, context: context)
        }
        .task(id: store.inbox?.id) {
            if mailboxID == nil, let inbox = store.inbox { mailboxID = inbox.id }
        }
        .onChange(of: mailboxID) { _, new in
            store.activeMailboxID = new
            threadID = nil
        }
        .onAppear { store.activeMailboxID = mailboxID }
        #if DEBUG
        .task(id: store.rows(in: mailboxID ?? "").count) {
            // Debug builds only: CIRRUS_DEBUG_OPEN=thread:<row index> or compose, for screenshots.
            guard let open = ProcessInfo.processInfo.environment["CIRRUS_DEBUG_OPEN"], let id = mailboxID else { return }
            let rows = store.rows(in: id)
            if open.hasPrefix("thread:"), let i = Int(open.dropFirst(7)), rows.indices.contains(i) { threadID = rows[i].id; column = .detail }
            if open.hasPrefix("subject:"), let r = rows.first(where: { $0.email.displaySubject.contains(open.dropFirst(8)) }) { threadID = r.id; column = .detail }
            if open == "compose", !rows.isEmpty, compose == nil { compose = ComposeContext(mode: .new, original: nil) }
            if open.hasPrefix("reply:"), let i = Int(open.dropFirst(6)), rows.indices.contains(i), compose == nil {
                compose = ComposeContext(mode: .reply, original: rows[i].email)
            }
        }
        #endif
        .alert("Something went wrong", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
