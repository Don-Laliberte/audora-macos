// SignInView.swift
// Authentication view using Clerk

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @StateObject private var authService = AuthService.shared

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var isSigningIn: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text("Welcome to Audora")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Sign in to sync your meetings and notes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Sign in form
            VStack(spacing: 20) {
                // Sign in with Apple button
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task {
                        await handleAppleSignIn(result)
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(10)

                // Divider
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }
                .padding(.vertical, 10)

                // Email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .textContentType(.emailAddress)
                }

                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        if showPassword {
                            TextField("Password", text: $password)
                                .textContentType(.password)
                        } else {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                        }

                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }

                // Error message
                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                // Sign in button
                Button(action: signIn) {
                    if isSigningIn || authService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(email.isEmpty || password.isEmpty || isSigningIn)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 400)

            Spacer()

            // Footer
            VStack(spacing: 8) {
                Text("By signing in, you agree to our")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Link("Terms of Service", destination: URL(string: "https://audora.psycho-baller.com/terms")!)
                    Text("and")
                        .foregroundColor(.secondary)
                    Link("Privacy Policy", destination: URL(string: "https://audora.psycho-baller.com/privacy")!)
                }
                .font(.caption)
            }
            .padding(.bottom, 30)
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    private func signIn() {
        isSigningIn = true
        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch {
                // Error is handled by AuthService
            }
            isSigningIn = false
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success:
            do {
                try await authService.signInWithApple()
            } catch {
                // Error is handled by AuthService
            }
        case .failure(let error):
            print("❌ Apple Sign In failed: \(error)")
        }
    }
}

#Preview {
    SignInView()
}
