import Foundation

/// Build-time configuration injected from `Config/*.xcconfig` via Info.plist (see docs/setup.md).
struct AppConfig: Sendable {
    let supabaseURL: URL
    let supabaseKey: String

    static let current: AppConfig? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlString = info["SupabaseURL"] as? String,
              let url = URL(string: urlString),
              let key = info["SupabaseKey"] as? String, !key.isEmpty
        else { return nil }
        return AppConfig(supabaseURL: url, supabaseKey: key)
    }()
}
