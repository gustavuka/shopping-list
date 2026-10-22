import Foundation

/// `shoppinglist://join/ABC123` — sent when sharing a room (see ShareRoomSheet).
/// The password is never part of the link; it's shared separately.
enum DeepLink: Equatable {
    case join(code: String)

    static let scheme = "shoppinglist"

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == "join" else { return nil }
        let code = url.pathComponents.dropFirst().first ?? ""
        guard !code.isEmpty else { return nil }
        self = .join(code: code.uppercased())
    }

    static func joinURL(code: String) -> URL {
        URL(string: "\(scheme)://join/\(code)")!
    }
}
