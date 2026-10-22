import Foundation
import Observation
import Supabase
import SwiftData

/// App-wide composition root. Owns long-lived services and the per-user `Session`
/// (store + sync), which exists only while signed in.
@MainActor
@Observable
final class AppModel {
    /// Everything scoped to one signed-in user.
    struct Session {
        let userID: UUID
        let store: ListStore
        let sync: SyncEngine
    }

    let container: ModelContainer
    let network = NetworkMonitor()
    /// nil when the build has no Supabase configuration (see docs/setup.md).
    let auth: AuthService?
    private(set) var session: Session?
    /// A room to join, from a link or the welcome screen ("" = empty join form); consumed by `SessionRootView`.
    var pendingJoinCode: String?

    @ObservationIgnored private let remote: (any RemoteSyncing)?
    private static let lastUserKey = "lastUserID"

    init(container: ModelContainer, config: AppConfig?) {
        self.container = container
        if let config {
            let client = AuthService.makeClient(url: config.supabaseURL, key: config.supabaseKey)
            remote = SupabaseRemote(client: client)
            auth = AuthService(client: client)
        } else {
            remote = nil
            auth = nil
        }

        auth?.onStateChange = { [weak self] state in self?.authChanged(state) }
        network.onReconnect = { [weak self] in self?.session?.sync.start() }
        if let auth { authChanged(auth.state) }

        #if DEBUG
        // UI tests start from the sign-in screen regardless of what this simulator's Keychain holds.
        if ProcessInfo.processInfo.arguments.contains("-signOutOnLaunch") {
            Task { await signOut() }
        }
        #endif
    }

    /// Signed-in session with an in-memory store and an offline backend — for UI tests and screenshots.
    /// Launch with `-uiTesting` (add `-seeded` for sample items).
    init(demoContainer container: ModelContainer, seeded: Bool) {
        self.container = container
        auth = nil
        let demoRemote = PreviewRemote()
        remote = demoRemote
        let userID = UUID()
        let store = ListStore(context: container.mainContext, currentUserID: userID)
        let sync = SyncEngine(
            context: container.mainContext,
            remote: demoRemote,
            userID: userID,
            cursors: SyncCursors(userID: userID, defaults: UserDefaults(suiteName: "uiTesting") ?? .standard)
        )
        store.onLocalChange = { [weak sync] in sync?.kick() }
        session = Session(userID: userID, store: store, sync: sync)
        if seeded {
            PreviewSupport.seed(store)
        }
    }

    /// Single entry point for every URL the app is opened with.
    func handle(_ url: URL) {
        if case .join(let code) = DeepLink(url: url) {
            pendingJoinCode = code
        }
    }

    func signOut() async {
        session?.sync.stop()
        await auth?.signOut()  // → .signedOut → closeSession()
    }

    private func authChanged(_ state: AuthService.State) {
        switch state {
        case .signedIn(let userID) where session?.userID != userID:
            openSession(for: userID)
        case .signedIn:
            break
        case .signedOut:
            closeSession()
        }
    }

    private func openSession(for userID: UUID) {
        guard let remote else { return }
        session?.sync.shutdown()  // switching accounts: nothing may keep running for the previous user
        let store = ListStore(context: container.mainContext, currentUserID: userID)

        // A different account on this device must not see (or sync) the previous one's data.
        let defaults = UserDefaults.standard
        if let previous = defaults.string(forKey: Self.lastUserKey).flatMap(UUID.init(uuidString:)), previous != userID {
            store.wipeLocalData()
            SyncCursors(userID: previous).reset()
        }
        defaults.set(userID.uuidString, forKey: Self.lastUserKey)

        let sync = SyncEngine(context: container.mainContext, remote: remote, userID: userID)
        store.onLocalChange = { [weak sync] in sync?.kick() }
        session = Session(userID: userID, store: store, sync: sync)
    }

    private func closeSession() {
        guard let session else { return }
        session.sync.shutdown()
        session.store.wipeLocalData()
        SyncCursors(userID: session.userID).reset()
        UserDefaults.standard.removeObject(forKey: Self.lastUserKey)
        self.session = nil
    }
}
