import Foundation

/// Stand-in user ID until email OTP sign-in lands. The server overwrites `created_by` / `updated_by`
/// with the authenticated user, so rows written with this ID are corrected on first sync.
enum LocalIdentity {
    private static let key = "localUserID"

    static var userID: UUID {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) {
            return stored
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
