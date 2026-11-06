import SwiftUI
import QuickLook
import JMAPKit

struct ThreadView: View {
    let store: AccountStore
    let threadID: String
    @Binding var compose: ComposeContext?

    @State private var emails: [Email] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var previewURL: URL?
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let first = emails.first {
                    Text(first.displaySubject)
                        .font(.title3.weight(.semibold))
                        .padding([.horizontal, .top])
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(emails) { email in
                    MessageView(
                        email: email,
                        isExpanded: expanded.contains(email.id),
                        toggle: { toggle(email.id) },
                        reply: { compose = ComposeContext(mode: $0, original: email) },
                        open: { part in Task { await open(part) } }
                    )
                    Divider()
                }
                if let error {
                    ContentUnavailableView("Could not load this message", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if isLoading && emails.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let last = emails.last {
                    Menu {
                        Button("Reply", systemImage: "arrowshape.turn.up.left") { compose = ComposeContext(mode: .reply, original: last) }
                        Button("Reply All", systemImage: "arrowshape.turn.up.left.2") { compose = ComposeContext(mode: .replyAll, original: last) }
                        Button("Forward", systemImage: "arrowshape.turn.up.right") { compose = ComposeContext(mode: .forward, original: last) }
                    } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                }
            }
        }
        .quickLookPreview($previewURL)
        .task { await load() }
    }

    private func load() async {
        if let cached = store.cachedThread(threadID) {
            emails = cached
            expandDefault()
        }
        do {
            emails = try await store.loadThread(threadID)
            error = nil
            expandDefault()
            let unread = emails.filter(\.isUnread).map(\.id)
            await store.markRead(unread)
        } catch {
            if emails.isEmpty { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    /// The newest message and every unread one start open.
    private func expandDefault() {
        guard expanded.isEmpty else { return }
        expanded = Set(emails.filter(\.isUnread).map(\.id))
        if let last = emails.last { expanded.insert(last.id) }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func open(_ part: EmailBodyPart) async {
        do { previewURL = try await store.downloadAttachment(part) } catch { self.error = error.localizedDescription }
    }
}

struct MessageView: View {
    let email: Email
    let isExpanded: Bool
    let toggle: () -> Void
    let reply: (ComposeMode) -> Void
    let open: (EmailBodyPart) -> Void

    @State private var loadImages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) { header }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Collapses the message" : "Expands the message")
            if isExpanded {
                content
                attachments
            }
        }
        .padding()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(email.senderName).font(.headline)
                if isExpanded {
                    Text("To: " + formatAddresses(email.to ?? [])).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    if let cc = email.cc, !cc.isEmpty { Text("Cc: " + formatAddresses(cc)).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                } else {
                    Text(email.preview ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let date = email.sentAt ?? email.receivedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if isExpanded {
                    Menu {
                        Button("Reply", systemImage: "arrowshape.turn.up.left") { reply(.reply) }
                        Button("Reply All", systemImage: "arrowshape.turn.up.left.2") { reply(.replyAll) }
                        Button("Forward", systemImage: "arrowshape.turn.up.right") { reply(.forward) }
                    } label: { Image(systemName: "arrowshape.turn.up.left").padding(6) }
                        .accessibilityLabel("Reply options")
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        if let html = email.htmlText {
            HTMLMessageBody(html: html, loadImages: $loadImages)
        } else {
            Text(email.bestPlainText.isEmpty ? "(no content)" : email.bestPlainText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var attachments: some View {
        let files = email.fileAttachments
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(files) { part in
                    Button { open(part) } label: {
                        Label {
                            Text(part.name ?? "Attachment")
                            if let size = part.size { Text(Int64(size), format: .byteCount(style: .file)).foregroundStyle(.secondary) }
                        } icon: { Image(systemName: "paperclip") }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Attachment \(part.name ?? "file")")
                    .accessibilityHint("Opens a preview")
                }
            }
        }
    }
}

/// An HTML message with remote images blocked until the reader asks for them.
struct HTMLMessageBody: View {
    let html: String
    @Binding var loadImages: Bool
    @State private var height: CGFloat = 20

    private var hasRemoteImages: Bool {
        html.range(of: #"(?i)(<img[^>]+src\s*=\s*["']?\s*https?:|url\(\s*["']?https?:|background\s*=\s*["']?https?:)"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasRemoteImages && !loadImages {
                Button { loadImages = true } label: { Label("Load images", systemImage: "photo") }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .accessibilityHint("Remote images are blocked to protect your privacy")
            }
            HTMLBodyView(html: html, allowRemoteImages: loadImages, height: $height)
                .frame(height: height)
        }
    }
}
