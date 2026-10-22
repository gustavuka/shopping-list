import Foundation

/// Per-list high-water mark of server `updated_at`, for delta fetches. Per list (not global) so a
/// newly joined list gets fully fetched even though its rows are older than our other cursors.
struct SyncCursors {
    private let defaults: UserDefaults
    private let key: String

    init(userID: UUID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = "syncCursors.\(userID.uuidString)"
    }

    subscript(listID: UUID) -> Date? {
        get {
            (defaults.dictionary(forKey: key)?[listID.uuidString] as? Double).map(Date.init(timeIntervalSince1970:))
        }
        nonmutating set {
            var all = defaults.dictionary(forKey: key) ?? [:]
            all[listID.uuidString] = newValue?.timeIntervalSince1970
            defaults.set(all, forKey: key)
        }
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
