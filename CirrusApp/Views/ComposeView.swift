import SwiftUI
import JMAPKit

/// What opens the compose sheet: a new message, or a reply, reply-all or forward of `original`.
struct ComposeContext: Identifiable {
    let id = UUID()
    let mode: ComposeMode
    let original: Email?
}

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AccountStore
    let context: ComposeContext

    @State private var identityID = ""
    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var showCcBcc = false
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var attachments: [EmailBodyPart] = []
    @State private var inReplyTo: [String] = []
    @State private var references: [String] = []
    @State private var isSending = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var seeded = false
    @FocusState private var focus: Field?

    private enum Field { case to, subject, body }

    private var identity: Identity? { store.identities.first { $0.id == identityID } ?? store.identities.first }
    private var recipients: [EmailAddress] { parseAddresses(to) + parseAddresses(cc) + parseAddresses(bcc) }
    private var isDirty: Bool { !to.isEmpty || !subject.isEmpty || !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && context.mode == .new }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.identities.count > 1 {
                        Picker("From", selection: $identityID) {
                            ForEach(store.identities) { Text("\($0.name) <\($0.email)>").tag($0.id) }
                        }
                    } else if let identity {
                        LabeledContent("From", value: identity.email)
                    }
                    LabeledContent("To") {
                        TextField("", text: $to, axis: .vertical)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .to)
                            .accessibilityLabel("To")
                    }
                    if showCcBcc {
                        LabeledContent("Cc") { TextField("", text: $cc, axis: .vertical).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Cc") }
                        LabeledContent("Bcc") { TextField("", text: $bcc, axis: .vertical).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Bcc") }
                    } else {
                        Button("Add Cc and Bcc") { showCcBcc = true }.font(.subheadline)
                    }
                    LabeledContent("Subject") {
                        TextField("", text: $subject, axis: .vertical)
                            .focused($focus, equals: .subject)
                            .accessibilityLabel("Subject")
                    }
                }
                if !attachments.isEmpty {
                    Section("Attachments") {
                        ForEach(attachments) { part in
                            Label(part.name ?? "Attachment", systemImage: "paperclip")
                        }
                        .onDelete { attachments.remove(atOffsets: $0) }
                    }
                }
                Section {
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 240)
                        .focused($focus, equals: .body)
                        .accessibilityLabel("Message body")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await send() } } label: {
                        if isSending { ProgressView() } else { Text("Send").fontWeight(.semibold) }
                    }
                    .disabled(isSending || recipients.isEmpty || identity == nil)
                }
            }
            .confirmationDialog("Discard this message?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .alert("Could not send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .interactiveDismissDisabled(isDirty || isSending)
            .task { await seed() }
        }
    }

    private var title: String {
        switch context.mode {
        case .new: "New Message"
        case .reply: "Reply"
        case .replyAll: "Reply All"
        case .forward: "Forward"
        }
    }

    private func seed() async {
        guard !seeded else { return }
        seeded = true
        if store.identities.isEmpty { await store.loadIdentities() }
        let mine = store.identities.map(\.email)
        let seed = ComposeBuilder.seed(mode: context.mode, original: context.original, myAddresses: mine.isEmpty ? [store.name] : mine)
        to = formatAddresses(seed.to)
        cc = formatAddresses(seed.cc)
        showCcBcc = !seed.cc.isEmpty
        subject = seed.subject
        messageBody = seed.body
        attachments = seed.attachments
        inReplyTo = seed.inReplyTo
        references = seed.references
        // Answer from the address the message was sent to, when it is one of mine.
        let recipients = ((context.original?.to ?? []) + (context.original?.cc ?? [])).map { $0.email.lowercased() }
        identityID = store.identities.first { recipients.contains($0.email.lowercased()) }?.id ?? store.identities.first?.id ?? ""
        focus = seed.to.isEmpty ? .to : .body
    }

    private func send() async {
        guard let identity else { return }
        isSending = true
        defer { isSending = false }
        let draft = Draft(
            from: EmailAddress(name: identity.name, email: identity.email),
            to: parseAddresses(to), cc: parseAddresses(cc), bcc: parseAddresses(bcc),
            subject: subject, body: messageBody, inReplyTo: inReplyTo, references: references, attachments: attachments)
        do {
            try await store.send(draft, identityID: identity.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
