import SwiftUI

/// Shares the current list as a room: its code plus a password the user picks.
/// The password is only known right after setting it (the server stores a hash), so the share
/// message includes it then; later shares say "the password I gave you" and offer "Change password".
struct ShareRoomSheet: View {
    let list: ListRecord

    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var justSetPassword: String?
    @State private var isChangingPassword = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var needsPassword: Bool { !list.hasPassword || isChangingPassword }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, options: .nonRepeating)

                if needsPassword {
                    passwordForm
                } else {
                    roomDetails
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.smooth, value: needsPassword)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Steps

    private var passwordForm: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(isChangingPassword ? "New room password" : "Choose a room password")
                    .font(.title2.bold())
                Text("Your partner joins with the room code and this password. Use something you can say out loud.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            TextField("At least 4 characters", text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(savePassword)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: .capsule)

            Button(action: savePassword) {
                Group {
                    if isSaving { ProgressView() } else { Text("Save password") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(password.count < 4 || isSaving)
        }
    }

    @ViewBuilder
    private var roomDetails: some View {
        VStack(spacing: 8) {
            Text("Shop together")
                .font(.title2.bold())
            Text("Your partner taps **Join a room** and enters:")
                .foregroundStyle(.secondary)
        }

        if let code = list.inviteCode {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Code").foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(.title, design: .monospaced, weight: .bold))
                        .tracking(4)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Password").foregroundStyle(.secondary)
                    Text(justSetPassword ?? String(localized: "the one you chose"))
                        .font(justSetPassword == nil ? .body : .system(.title3, design: .monospaced, weight: .semibold))
                        .textSelection(.enabled)
                }
            }
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))

            ShareLink(item: message(code: code)) {
                Label("Send to partner", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Button("Change password") {
                password = ""
                isChangingPassword = true
            }
            .font(.footnote)
        } else {
            ProgressView()
                .task { await sync.syncNow() }
        }
    }

    // MARK: Actions

    private func savePassword() {
        guard password.count >= 4, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let chosen = password
        Task {
            defer { isSaving = false }
            do {
                try await sync.setPassword(chosen, for: list)
                justSetPassword = chosen
                isChangingPassword = false
            } catch {
                errorMessage = String(localized: "Couldn't save the password. You need to be online to share a room.")
            }
        }
    }

    private func message(code: String) -> String {
        let link = DeepLink.joinURL(code: code).absoluteString
        if let justSetPassword {
            return String(localized: """
            Join my shopping list "\(list.name)": open Shopping List, tap Join a room, and enter \
            code \(code) with password \(justSetPassword). Or tap \(link)
            """)
        }
        return String(localized: """
        Join my shopping list "\(list.name)": open Shopping List, tap Join a room, and enter \
        code \(code) with the password I gave you. Or tap \(link)
        """)
    }
}
