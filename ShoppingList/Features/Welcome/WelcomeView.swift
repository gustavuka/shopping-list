import SwiftUI

/// First launch. Fastest path: a name → guest user → new list or join a room
/// (docs/decisions/0007-guest-users-and-room-passwords.md). Or create an account / sign in with
/// email + password (0008-optional-email-accounts.md); a guest can also upgrade later in Settings.
struct WelcomeView: View {
    let auth: AuthService

    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var failures = 0
    @State private var accountSheet: AccountSheet.Mode?
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 104, height: 104)
                    .background(Color.accentColor.gradient, in: .rect(cornerRadius: 28))
                    .symbolEffect(.bounce, value: isWorking)
                    .accessibilityHidden(true)

                Text("Shopping List")
                    .font(.largeTitle.bold())
                Text("One list, two phones, always in sync.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Your name", text: $name)
                    .textContentType(.givenName)
                    .submitLabel(.go)
                    .focused($isNameFocused)
                    .onSubmit { start(joining: false) }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .glassEffect(.regular.interactive(), in: .capsule)
                Text("Your partner sees it, like “\(trimmedName.isEmpty ? "Ana" : trimmedName) got Milk”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    start(joining: false)
                } label: {
                    label(String(localized: "Start a new list"))
                }
                .buttonStyle(.glassProminent)

                Button {
                    start(joining: true)
                } label: {
                    label(model.pendingJoinCode.map { String(localized: "Join room \($0)") }
                          ?? String(localized: "Join a room"))
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .disabled(trimmedName.isEmpty || isWorking)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Create account") { accountSheet = .createAccount }
                    Text("·").foregroundStyle(.tertiary)
                    Button("Sign in") { accountSheet = .signIn }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isWorking)

                Text("No account needed — you can create one later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Spacer()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .animation(.smooth, value: errorMessage)
        .sensoryFeedback(.error, trigger: failures)
        .onChange(of: accountSheet) { _, sheet in
            if sheet != nil { isNameFocused = false }  // see AccountSheet.submit
        }
        .sheet(item: $accountSheet) { mode in
            AccountSheet(mode: mode, auth: auth, suggestedName: trimmedName)
        }
        .onAppear {
            isNameFocused = true
            LaunchTimer.firstFrameRendered("welcome")
        }
    }

    private func label(_ title: String) -> some View {
        Group {
            if isWorking { ProgressView() } else { Text(title) }
        }
        .frame(maxWidth: .infinity)
    }

    private func start(joining: Bool) {
        guard !trimmedName.isEmpty, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        isNameFocused = false  // the screen is about to be replaced; see AccountSheet.submit
        if joining, model.pendingJoinCode == nil {
            model.pendingJoinCode = ""  // opens an empty join form once the session starts
        }
        Task {
            defer { isWorking = false }
            do {
                try await auth.signInAsGuest(name: trimmedName)
            } catch {
                errorMessage = String(localized: "Couldn't get started. The first launch needs an internet connection — check it and try again.")
                failures += 1
            }
        }
    }
}
