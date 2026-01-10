// AuthService.swift
// Handles Clerk authentication for the application

import Foundation
import Combine
import ClerkSDK

/// Service for managing user authentication via Clerk
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isSignedIn: Bool = false
    @Published var currentUser: User?
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Configure Clerk with publishable key from environment
        configureClerk()

        // Observe auth state changes
        observeAuthState()
    }

    /// Configures Clerk SDK with the publishable key
    private func configureClerk() {
        guard let publishableKey = getClerkPublishableKey() else {
            print("⚠️ Clerk publishable key not configured")
            isLoading = false
            errorMessage = "Authentication not configured. Please set CLERK_PUBLISHABLE_KEY in Config.xcconfig"
            return
        }

        // Configure Clerk SDK
        Clerk.configure(publishableKey: publishableKey)
        print("✅ Clerk configured successfully")
    }

    /// Gets the Clerk publishable key from environment or configuration
    private func getClerkPublishableKey() -> String? {
        // Check environment variable
        if let key = ProcessInfo.processInfo.environment["CLERK_PUBLISHABLE_KEY"], !key.isEmpty {
            return key
        }

        // Check Info.plist (set via xcconfig)
        if let key = Bundle.main.object(forInfoDictionaryKey: "CLERK_PUBLISHABLE_KEY") as? String, !key.isEmpty {
            return key
        }

        return nil
    }

    /// Observes authentication state changes from Clerk
    private func observeAuthState() {
        Task {
            // Listen for auth state changes
            for await client in Clerk.shared.$client.values {
                await MainActor.run {
                    self.isLoading = false
                    if let session = client?.lastActiveSession {
                        self.isSignedIn = true
                        self.currentUser = session.user
                    } else {
                        self.isSignedIn = false
                        self.currentUser = nil
                    }
                }
            }
        }
    }

    /// Gets the current session token for API calls
    /// - Returns: The session token string, or nil if not signed in
    func getSessionToken() async -> String? {
        guard let session = Clerk.shared.client?.lastActiveSession else {
            return nil
        }

        do {
            let token = try await session.getToken()
            return token?.jwt
        } catch {
            print("❌ Failed to get session token: \(error)")
            return nil
        }
    }

    /// Signs in with email and password
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let signIn = try await SignIn.create(strategy: .identifier(email, password: password))

            // Check if sign in is complete
            if signIn.status == .complete {
                // Session is automatically set by Clerk
                print("✅ Sign in successful")
            } else {
                // Handle additional steps (2FA, etc.) if needed
                print("⚠️ Sign in requires additional steps: \(signIn.status)")
                errorMessage = "Additional verification required"
            }
        } catch {
            print("❌ Sign in failed: \(error)")
            errorMessage = error.localizedDescription
            throw error
        }

        isLoading = false
    }

    /// Signs in with Apple (native)
    func signInWithApple() async throws {
        isLoading = true
        errorMessage = nil

        do {
            // Use Clerk's native Sign in with Apple
            _ = try await SignIn.create(strategy: .oauth(.apple))
            print("✅ Sign in with Apple successful")
        } catch {
            print("❌ Sign in with Apple failed: \(error)")
            errorMessage = error.localizedDescription
            throw error
        }

        isLoading = false
    }

    /// Signs out the current user
    func signOut() async {
        do {
            try await Clerk.shared.client?.lastActiveSession?.revoke()
            isSignedIn = false
            currentUser = nil
            print("✅ Signed out successfully")
        } catch {
            print("❌ Sign out failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}
