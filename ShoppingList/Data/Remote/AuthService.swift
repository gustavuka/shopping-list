import Foundation
import Observation
import OSLog
import Supabase

/// Who this phone is: a guest (anonymous Supabase user) or an email + password account
/// (docs/decisions/0007-guest-users-and-room-passwords.md, 0008-optional-email-accounts.md).
/// The session lives in the Keychain, so a returning user is signed in synchronously at launch.
/// Upgrading a guest keeps the same user id, so rooms and name carry over.
@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case signedOut
        case signedIn(userID: UUID)
    }

    private(set) var state: State
    /// nil for guests.
    private(set) var email: String?
    var isGuest: Bool { email == nil }
    @ObservationIgnored let client: SupabaseClient
    @ObservationIgnored var onStateChange: (State) -> Void = { _ in }
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(client: SupabaseClient) {
        self.client = client
        // Possibly expired; the SDK refreshes it in the background. Good enough to render the list now.
        let session = client.auth.currentSession
        state = session.map { .signedIn(userID: $0.user.id) } ?? .signedOut
        email = session.flatMap { Self.accountEmail(of: $0.user) }
        listener = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                self?.handle(event: event, session: session)
            }
        }
    }

    /// Creates this phone's guest user. `name` becomes the profile's display name.
    @discardableResult
    func signInAsGuest(name: String) async throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = try await client.auth.signInAnonymously(data: ["display_name": .string(name)])
        update(.signedIn(userID: session.user.id))
        return session.user.id
    }

    /// Creates an email + password account. No confirmation email is sent (confirmations are off).
    func createAccount(email: String, password: String, name: String) async throws {
        let response = try await client.auth.signUp(
            email: Self.normalize(email),
            password: password,
            data: ["display_name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines))]
        )
        guard let session = response.session else { throw AccountError.confirmationRequired }
        apply(session)
    }

    func signIn(email: String, password: String) async throws {
        apply(try await client.auth.signIn(email: Self.normalize(email), password: password))
    }

    /// Turns this phone's guest into an account. Same user id: rooms, items and name are kept.
    func upgradeGuest(email: String, password: String) async throws {
        let user = try await client.auth.update(user: UserAttributes(email: Self.normalize(email), password: password))
        guard !user.isAnonymous, let email = user.email else { throw AccountError.confirmationRequired }
        self.email = email
    }

    /// Forgets this phone's guest user. Its rooms stay; rejoin them with code + password.
    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            // Usually offline. Local state is dropped regardless.
            Logger.auth.error("Sign out failed: \(error)")
        }
        email = nil
        update(.signedOut)
    }

    private func apply(_ session: Session) {
        email = Self.accountEmail(of: session.user)
        update(.signedIn(userID: session.user.id))
    }

    private static func accountEmail(of user: User) -> String? {
        user.isAnonymous ? nil : user.email
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func handle(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedOut:
            email = nil
            update(.signedOut)
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            if let session {
                apply(session)
            } else if event == .initialSession {
                update(.signedOut)
            }
        default:
            break
        }
    }

    private func update(_ newState: State) {
        guard newState != state else { return }
        state = newState
        onStateChange(newState)
    }
}

enum AccountError: LocalizedError {
    /// The project requires email confirmation, which this app doesn't support yet.
    case confirmationRequired

    var errorDescription: String? {
        String(localized: "This account needs email confirmation, which isn't supported yet.")
    }
}

extension AuthService {
    /// A user-facing message for a failed account action.
    static func message(for error: any Error) -> String {
        if let error = error as? AccountError { return error.errorDescription ?? "" }
        guard let error = error as? AuthError else {
            return String(localized: "Something went wrong. Check your connection and try again.")
        }
        switch error.errorCode {
        case .invalidCredentials:
            return String(localized: "Wrong email or password.")
        case .emailExists, .userAlreadyExists:
            return String(localized: "There's already an account with this email. Sign in instead.")
        case .weakPassword:
            return String(localized: "Use a password with at least 6 characters.")
        case .validationFailed:
            return String(localized: "Check the email address and try again.")
        default:
            return String(localized: "Something went wrong. Check your connection and try again.")
        }
    }

    /// Builds the Supabase client. Tests that need several users at once pass `persistSession: false`
    /// so each client keeps its session in memory instead of sharing the Keychain entry.
    static func makeClient(url: URL, key: String, persistSession: Bool = true) -> SupabaseClient {
        let auth: SupabaseClientOptions.AuthOptions = persistSession
            ? .init(emitLocalSessionAsInitialSession: true)
            : .init(storage: InMemoryAuthStorage(), emitLocalSessionAsInitialSession: true)
        return SupabaseClient(supabaseURL: url, supabaseKey: key, options: .init(auth: auth))
    }
}

private final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()  // guards `values`; the SDK may call from any thread

    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}
