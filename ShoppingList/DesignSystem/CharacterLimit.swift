import SwiftUI

/// Server-side limits mirrored in the UI, so typing past them is impossible instead of failing on sync.
enum TextLimit {
    /// `profiles.display_name` (see supabase/migrations).
    static let displayName = 50
}

extension View {
    /// Truncates `text` to `limit` characters as it's typed.
    func characterLimit(_ limit: Int, text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            if new.count > limit { text.wrappedValue = String(new.prefix(limit)) }
        }
    }
}
