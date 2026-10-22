import SwiftUI

/// Join a room with its 6-character code and the password the partner chose.
struct JoinListView: View {
    let onJoined: (UUID) -> Void

    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var password = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var failures = 0
    @FocusState private var focused: Field?

    private enum Field { case code, password }

    init(initialCode: String?, onJoined: @escaping (UUID) -> Void) {
        self.onJoined = onJoined
        _code = State(initialValue: initialCode ?? "")
    }

    private var normalizedCode: String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Join a room")
                        .font(.title2.bold())
                    Text("Enter the code and password your partner shared.")
                        .foregroundStyle(.secondary)
                }

                TextField("ABC123", text: $code)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .code)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    .onChange(of: code) { _, new in
                        let limited = String(new.uppercased().prefix(6))
                        if limited != new { code = limited }
                        errorMessage = nil
                        if limited.count == 6 { focused = .password }
                    }

                TextField("Password", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .password)
                    .submitLabel(.join)
                    .onSubmit(join)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .onChange(of: password) { errorMessage = nil }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }

                Button(action: join) {
                    Group {
                        if isJoining { ProgressView() } else { Text("Join") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(normalizedCode.count != 6 || password.count < 4 || isJoining)
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.smooth, value: errorMessage)
            .sensoryFeedback(.error, trigger: failures)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
            .onAppear { focused = code.isEmpty ? .code : .password }
        }
        .presentationDetents([.medium, .large])
    }

    private func join() {
        // 4, not 6: rooms created before the 6-character minimum keep their passwords.
        guard normalizedCode.count == 6, password.count >= 4, !isJoining else { return }
        isJoining = true
        Task {
            defer { isJoining = false }
            do {
                let listID = try await sync.join(inviteCode: normalizedCode, password: password)
                onJoined(listID)
                dismiss()
            } catch JoinError.invalidCodeOrPassword {
                errorMessage = String(localized: "That code and password don't match a room. Check both and try again.")
                failures += 1
            } catch JoinError.tooManyAttempts {
                errorMessage = String(localized: "Too many tries. Wait a few minutes and try again.")
                failures += 1
            } catch {
                errorMessage = String(localized: "Couldn't join right now. Check your connection and try again.")
                failures += 1
            }
        }
    }
}
