import SwiftUI

/// Email + password: create an account, sign in, or turn this phone's guest into an account
/// (docs/decisions/0008-optional-email-accounts.md).
struct AccountSheet: View {
    enum Mode: Identifiable {
        case createAccount
        case signIn
        /// Keeps the current guest's user id, rooms and name.
        case upgradeGuest

        var id: Self { self }
    }

    let mode: Mode
    let auth: AuthService
    /// Prefilled from the welcome screen when creating an account.
    var suggestedName = ""

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var failures = 0
    @FocusState private var focused: Field?

    private enum Field { case name, email, password }

    private var asksForName: Bool { mode == .createAccount }

    private var canSubmit: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        return trimmedEmail.contains("@") && trimmedEmail.contains(".") && password.count >= 6
            && (!asksForName || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if asksForName {
                        TextField("Your name", text: $name)
                            .textContentType(.givenName)
                            .focused($focused, equals: .name)
                            .accessibilityIdentifier("account.name")
                            .submitLabel(.next)
                            .onSubmit { focused = .email }
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .accessibilityIdentifier("account.email")
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                    SecureField("Password (at least 6 characters)", text: $password)
                        // Not `.newPassword`: iOS's "Strong Password" flow needs an associated domain
                        // (webcredentials), which requires the paid developer account. Add both together.
                        .textContentType(mode == .signIn ? .password : nil)
                        .focused($focused, equals: .password)
                        .accessibilityIdentifier("account.password")
                        .submitLabel(.go)
                        .onSubmit(submit)
                } footer: {
                    Text(footer)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(actionTitle, systemImage: "checkmark", role: .confirm, action: submit)
                            .disabled(!canSubmit)
                    }
                }
            }
            .sensoryFeedback(.error, trigger: failures)
            .onAppear {
                name = suggestedName
                focused = asksForName && name.isEmpty ? .name : .email
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch mode {
        case .createAccount: String(localized: "Create account")
        case .signIn: String(localized: "Sign in")
        case .upgradeGuest: String(localized: "Save your account")
        }
    }

    private var actionTitle: String {
        mode == .signIn ? String(localized: "Sign in") : String(localized: "Create")
    }

    private var footer: String {
        switch mode {
        case .createAccount:
            String(localized: "Sign in on any phone to get your name and rooms back.")
        case .signIn:
            String(localized: "Your rooms come back automatically.")
        case .upgradeGuest:
            String(localized: "Keeps everything you have now — your name, lists and rooms — and lets you sign in on another phone.")
        }
    }

    private func submit() {
        guard canSubmit, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        // Success swaps the whole screen (welcome → list) underneath this sheet. Release focus first:
        // SwiftUI crashes if a focused field's view is torn down mid-focus-update.
        focused = nil
        Task {
            defer { isWorking = false }
            do {
                switch mode {
                case .createAccount: try await auth.createAccount(email: email, password: password, name: name)
                case .signIn: try await auth.signIn(email: email, password: password)
                case .upgradeGuest: try await auth.upgradeGuest(email: email, password: password)
                }
                dismiss()
            } catch {
                errorMessage = AuthService.message(for: error)
                failures += 1
            }
        }
    }
}
