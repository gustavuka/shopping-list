import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var isSavingName = false
    @State private var confirmSignOut = false
    @State private var accountSheet: AccountSheet.Mode?

    private var isGuest: Bool { model.auth?.isGuest ?? true }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $displayName)
                        .characterLimit(TextLimit.displayName, text: $displayName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shown to your partner, e.g. “\(displayName.isEmpty ? "Ana" : displayName) added Milk”.")
                }

                Section {
                    if let lastSyncedAt = sync.status.lastSyncedAt {
                        LabeledContent("Last synced") {
                            Text(lastSyncedAt, style: .relative)
                        }
                    }
                    if sync.status.pendingCount > 0 {
                        LabeledContent("Waiting to sync", value: "\(sync.status.pendingCount)")
                    }
                }

                accountSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        saveName()
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                isGuest ? "Reset this phone?" : "Sign out?",
                isPresented: $confirmSignOut,
                titleVisibility: .visible
            ) {
                Button(isGuest ? "Reset" : "Sign out", role: .destructive) {
                    Task { await model.signOut() }
                }
            } message: {
                if sync.status.pendingCount > 0 {
                    Text("\(sync.status.pendingCount) changes haven't synced yet and will be lost.")
                } else if isGuest {
                    Text("Make sure you know your list's code and password to get back in.")
                } else {
                    Text("Your lists come back when you sign in again.")
                }
            }
            .sheet(item: $accountSheet) { mode in
                if let auth = model.auth {
                    AccountSheet(mode: mode, auth: auth)
                }
            }
            .onAppear { displayName = sync.memberNames[sync.userID] ?? "" }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if isGuest {
            Section {
                Button("Save as account", systemImage: "person.crop.circle.badge.plus") {
                    accountSheet = .upgradeGuest
                }
                Button("Sign in to an account", systemImage: "person.crop.circle") {
                    accountSheet = .signIn
                }
            } header: {
                Text("Account")
            } footer: {
                Text("You're a guest on this phone. Save as an account to keep your name and lists on any phone. Signing in to a different account replaces this guest.")
            }

            Section {
                Button("Reset this phone", role: .destructive) { confirmSignOut = true }
            } footer: {
                Text("Removes your lists from this phone. They're not deleted — rejoin them with their code and password.")
            }
        } else {
            Section("Account") {
                LabeledContent("Signed in as", value: model.auth?.email ?? "")
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            }
        }
    }

    private func saveName() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != sync.memberNames[sync.userID], !isSavingName else { return }
        isSavingName = true
        Task {
            defer { isSavingName = false }
            try? await sync.updateDisplayName(name)
        }
    }
}
