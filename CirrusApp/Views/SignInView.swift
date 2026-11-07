import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let isSheet: Bool

    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case server, email, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityHidden(true)
                        Text("Cirrus Mail").font(.title2.weight(.semibold))
                        Text("Sign in to your own Cirrus server.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Server URL", text: $server, prompt: Text(verbatim: "mail.example.com"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }
                } header: {
                    Text("Server")
                } footer: {
                    Text("The address you open Cirrus at in your browser.")
                }

                Section {
                    TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com"))
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("App password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Use an app password, not your account password. Create one in the Cirrus web app under Settings \u{2192} Security.")
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)") }
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            if isWorking { ProgressView() }
                            Text(isWorking ? "Signing in\u{2026}" : "Sign In").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSubmit)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSheet { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
    }

    private var canSubmit: Bool { !isWorking && !server.isEmpty && email.contains("@") && !password.isEmpty }

    private func signIn() async {
        guard canSubmit else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await model.signIn(server: server, email: email, password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
