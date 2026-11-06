import SwiftUI
import JMAPKit

struct ThreadListView: View {
    let store: AccountStore
    let mailboxID: String
    @Binding var selection: String?
    @Binding var compose: ComposeContext?
    @State private var query = ""

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var rows: [ThreadRow] { isSearching ? store.searchRows : store.rows(in: mailboxID) }

    var body: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                ThreadRowView(row: row)
                    .tag(row.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { act(.trash, row) } label: { Label("Trash", systemImage: "trash") }
                        Button { act(.archive, row) } label: { Label("Archive", systemImage: "archivebox") }
                            .tint(.accentColor)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { act(.markRead(row.email.isUnread), row) } label: {
                            Label(row.email.isUnread ? "Read" : "Unread", systemImage: row.email.isUnread ? "envelope.open" : "envelope.badge")
                        }
                        .tint(.accentColor)
                        Button { act(.flag(!row.email.isFlagged), row) } label: {
                            Label(row.email.isFlagged ? "Unflag" : "Flag", systemImage: row.email.isFlagged ? "flag.slash" : "flag")
                        }
                        .tint(.orange)
                    }
                    .task {
                        if !isSearching, row.id == rows.last?.id { await store.loadMore(mailboxID: mailboxID) }
                    }
            }
            if !isSearching, store.canLoadMore(in: mailboxID), !rows.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .navigationTitle(store.mailbox(id: mailboxID)?.name ?? "Mail")
        .searchable(text: $query, prompt: "Search mail")
        .task(id: query) {
            guard isSearching else { store.clearSearch(); return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await store.search(query)
        }
        .task(id: mailboxID) { await store.refresh(mailboxID: mailboxID) }
        .refreshable {
            if isSearching { await store.search(query) } else {
                await store.refresh(mailboxID: mailboxID)
                await store.sync(refreshActive: false)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Compose", systemImage: "square.and.pencil") { compose = ComposeContext(mode: .new, original: nil) }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if rows.isEmpty {
            if isSearching {
                if store.isSearching { ProgressView() } else { ContentUnavailableView.search(text: query) }
            } else if store.loading.contains(mailboxID) {
                ProgressView()
            } else if store.isOffline {
                ContentUnavailableView("Offline", systemImage: "wifi.slash", description: Text("This mailbox has not been saved on this device yet."))
            } else {
                ContentUnavailableView("No messages", systemImage: "tray")
            }
        }
    }

    private func act(_ action: ThreadAction, _ row: ThreadRow) {
        if case .archive = action, selection == row.id { selection = nil }
        if case .trash = action, selection == row.id { selection = nil }
        Task { await store.perform(action, on: row, in: isSearching ? nil : mailboxID) }
    }
}

struct ThreadRowView: View {
    let row: ThreadRow
    @ScaledMetric(relativeTo: .body) private var dotSize = 10

    var body: some View {
        let email = row.email
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(email.isUnread ? Color.accentColor : .clear)
                .frame(width: dotSize, height: dotSize)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(email.senderName).font(.headline.weight(email.isUnread ? .semibold : .regular)).lineLimit(1)
                    if row.messageCount > 1 {
                        Text("\(row.messageCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if let date = email.receivedAt {
                        Text(date.listStamp).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Text(email.displaySubject).font(.subheadline.weight(email.isUnread ? .medium : .regular)).lineLimit(1)
                HStack(alignment: .top) {
                    Text(email.preview ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    if email.hasAttachment == true { Image(systemName: "paperclip").foregroundStyle(.secondary) }
                    if email.isFlagged { Image(systemName: "flag.fill").foregroundStyle(.orange) }
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        let e = row.email
        var parts = [e.isUnread ? "Unread" : nil, e.senderName, e.displaySubject, e.receivedAt.map { $0.formatted(date: .abbreviated, time: .shortened) }]
            .compactMap { $0 }
        if row.messageCount > 1 { parts.append("\(row.messageCount) messages") }
        if e.hasAttachment == true { parts.append("has attachment") }
        if e.isFlagged { parts.append("flagged") }
        if let p = e.preview, !p.isEmpty { parts.append(p) }
        return parts.joined(separator: ", ")
    }
}
