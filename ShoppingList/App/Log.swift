import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ShoppingList"

    static let store = Logger(subsystem: subsystem, category: "store")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let auth = Logger(subsystem: subsystem, category: "auth")
}
