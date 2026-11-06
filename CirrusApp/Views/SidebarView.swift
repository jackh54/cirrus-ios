import SwiftUI
import JMAPKit

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    let store: AccountStore
    @Binding var selection: String?
    let onCompose: () -> Void

    var body: some View {
        List(selection: $selection) {
            if model.rejectedLoginIDs.contains(store.loginID) {
                Section {
                    Label("This account's app password was rejected.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Sign Out", role: .destructive) { model.signOut(loginID: store.loginID) }
                }
            }
            if store.folders.isEmpty && store.labels.isEmpty {
                Section { ProgressView("Loading mailboxes\u{2026}") }
            }
            Section("Folders") {
                ForEach(store.folders) { MailboxRow(mailbox: $0) }
            }
            if !store.labels.isEmpty {
                Section("Labels") {
                    ForEach(store.labels) { MailboxRow(mailbox: $0) }
                }
            }
        }
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.sync() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { AccountMenu(store: store) }
            ToolbarItem(placement: .bottomBar) {
                if store.isOffline { Label("Offline, showing saved mail", systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary) }
            }
            ToolbarSpacer(placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Compose", systemImage: "square.and.pencil", action: onCompose)
            }
        }
    }
}

private struct MailboxRow: View {
    let mailbox: Mailbox

    var body: some View {
        HStack {
            Label {
                Text(mailbox.name)
            } icon: {
                Image(systemName: mailbox.symbolName)
                    .foregroundStyle(Color(hex: mailbox.cirrusColor) ?? .accentColor)
            }
            Spacer()
            if mailbox.badgeCount > 0 {
                Text(mailbox.badgeCount, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .tag(mailbox.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mailbox.name)
        .accessibilityValue(mailbox.badgeCount > 0 ? "\(mailbox.badgeCount) \(mailbox.role == "drafts" ? "drafts" : "unread")" : "")
    }
}

/// Switches between the JMAP accounts of every login (one per mailbox the user belongs to).
struct AccountMenu: View {
    @Environment(AppModel.self) private var model
    let store: AccountStore

    var body: some View {
        Menu {
            Picker("Account", selection: Bindable(model).selectedStoreID) {
                ForEach(model.stores) { Text($0.name).tag(Optional($0.id)) }
            }
            Divider()
            Button("Add Account\u{2026}", systemImage: "plus") { model.isAddingAccount = true }
            Button("Sign Out of \(model.logins.first { $0.id == store.loginID }?.credentials.email ?? "Server")", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                model.signOut(loginID: store.loginID)
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .accessibilityLabel("Accounts")
        .accessibilityValue(store.name)
    }
}
