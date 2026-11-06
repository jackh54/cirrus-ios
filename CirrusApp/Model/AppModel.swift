import Foundation
import JMAPKit
import Observation
import BackgroundTasks

@MainActor @Observable
final class AppModel {
    static let refreshTaskID = "org.jackh54.Cirrus.refresh"
    private static let selectedKey = "selectedAccountID"

    private(set) var logins: [Login] = []
    private(set) var stores: [AccountStore] = []
    private(set) var didBootstrap = false
    private(set) var rejectedLoginIDs: Set<String> = []
    var isAddingAccount = false
    var selectedStoreID: String? {
        didSet { UserDefaults.standard.set(selectedStoreID, forKey: Self.selectedKey) }
    }

    @ObservationIgnored private let transport = URLSessionTransport()
    @ObservationIgnored private var streams: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var inForeground = false

    var selectedStore: AccountStore? { stores.first { $0.id == selectedStoreID } ?? stores.first }

    // MARK: Launch

    func bootstrap() async {
        guard !didBootstrap else { return }
        logins = LoginStore.load()
        selectedStoreID = UserDefaults.standard.string(forKey: Self.selectedKey)
        // Cached sessions first, so the app opens on cached mail without waiting for the network.
        for login in logins {
            if let session = CacheFiles.read(JMAPSession.self, name: "session-\(login.id)") { applySession(session, for: login) }
        }
        didBootstrap = true
        for login in logins { Task { await refreshSession(login) } }
        if inForeground { startStreams() }
    }

    private func refreshSession(_ login: Login) async {
        do {
            let session = try await JMAPClient.discover(credentials: login.credentials, transport: transport)
            CacheFiles.write(session, name: "session-\(login.id)")
            rejectedLoginIDs.remove(login.id)
            applySession(session, for: login)
            for store in stores where store.loginID == login.id { Task { await store.sync() } }
        } catch JMAPError.unauthorized {
            rejectedLoginIDs.insert(login.id)
        } catch {
            // Offline: keep working from the cached session.
        }
    }

    private func applySession(_ session: JMAPSession, for login: Login) {
        var kept: [AccountStore] = stores.filter { $0.loginID != login.id }
        for (accountID, account) in session.mailAccounts {
            let client = JMAPClient(session: session, credentials: login.credentials, transport: transport)
            if let existing = stores.first(where: { $0.id == "\(login.id)/\(accountID)" }) {
                existing.update(name: account.name, client: client)
                kept.append(existing)
            } else {
                kept.append(AccountStore(loginID: login.id, accountID: accountID, name: account.name, client: client))
            }
        }
        for gone in stores where gone.loginID == login.id && !kept.contains(where: { $0.id == gone.id }) { gone.wipe() }
        stores = kept.sorted { ($0.loginID, $0.name) < ($1.loginID, $1.name) }
        if selectedStoreID == nil || !stores.contains(where: { $0.id == selectedStoreID }) { selectedStoreID = stores.first?.id }
    }

    // MARK: Sign in and out

    func signIn(server: String, email: String, password: String) async throws {
        guard let url = Credentials.normalizedServerURL(server) else { throw JMAPError.invalidServerURL }
        let credentials = Credentials(serverURL: url, email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        let session = try await JMAPClient.discover(credentials: credentials, transport: transport)
        guard !session.mailAccounts.isEmpty else { throw JMAPError.noMailAccount }
        let existing = logins.first { $0.credentials.serverURL == url && $0.credentials.email.lowercased() == credentials.email.lowercased() }
        let login = Login(id: existing?.id ?? UUID().uuidString, credentials: credentials)
        try LoginStore.save(login)
        CacheFiles.write(session, name: "session-\(login.id)")
        logins.removeAll { $0.id == login.id }
        logins.append(login)
        rejectedLoginIDs.remove(login.id)
        applySession(session, for: login)
        selectedStoreID = stores.first { $0.loginID == login.id }?.id
        isAddingAccount = false
        for store in stores where store.loginID == login.id { Task { await store.sync() } }
        if inForeground { startStreams() }
    }

    func signOut(loginID: String) {
        streams[loginID]?.cancel()
        streams[loginID] = nil
        for store in stores where store.loginID == loginID { store.wipe() }
        stores.removeAll { $0.loginID == loginID }
        logins.removeAll { $0.id == loginID }
        rejectedLoginIDs.remove(loginID)
        CacheFiles.remove(prefix: "session-\(loginID)")
        LoginStore.delete(id: loginID)
        if !stores.contains(where: { $0.id == selectedStoreID }) { selectedStoreID = stores.first?.id }
    }

    // MARK: Foreground (EventSource) and background refresh

    func enterForeground() {
        inForeground = true
        guard didBootstrap else { return }
        for store in stores { Task { await store.sync() } }
        startStreams()
    }

    func enterBackground() {
        inForeground = false
        for task in streams.values { task.cancel() }
        streams = [:]
        scheduleRefresh()
    }

    private func startStreams() {
        for login in logins where streams[login.id] == nil {
            let loginID = login.id
            streams[loginID] = Task { [weak self] in
                var failures = 0
                while !Task.isCancelled {
                    guard let self, let client = self.stores.first(where: { $0.loginID == loginID })?.client else { return }
                    do {
                        for try await change in client.stateChanges() {
                            failures = 0
                            for (accountID, states) in change.changed {
                                self.stores.first { $0.loginID == loginID && $0.accountID == accountID }?.handle(stateChange: states)
                            }
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        failures += 1
                    }
                    // The server ends a stream after a few minutes; reconnect quickly, back off when it keeps failing.
                    try? await Task.sleep(for: .seconds(min(60, 2 * (failures + 1))))
                }
            }
        }
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Best-effort sync for background app refresh: advances the cached mailbox and message states.
    func backgroundSync() async {
        await bootstrap()
        for login in logins { await refreshSession(login) }
        for store in stores { await store.sync(refreshActive: false) }
        scheduleRefresh()
    }
}
