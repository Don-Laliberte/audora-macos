// ConvexService.swift
// Handles interactions with Convex backend with Clerk authentication

import Foundation
import ConvexMobile
import Clerk
import Combine

/// Authentication state for the app
enum AuthState: Equatable {
    case loading
    case authenticated(userId: String)
    case unauthenticated
}

/// Service for interacting with Convex backend with Clerk authentication
@MainActor
class ConvexService: ObservableObject {
    static let shared = ConvexService()

    private var client: ConvexClient?

    @Published var authState: AuthState = .loading
    @Published var errorMessage: String?

    private init() {
        // Initialize Convex client with deployment URL
        if let deploymentURL = getConvexDeploymentURL() {
            client = ConvexClient(deploymentUrl: deploymentURL)
            print("✅ Convex client initialized with URL: \(deploymentURL)")
        } else {
            print("⚠️ Convex deployment URL not configured")
        }

        authState = .unauthenticated
    }

    /// Gets the Convex deployment URL from environment or configuration
    private func getConvexDeploymentURL() -> String? {
        if let url = ProcessInfo.processInfo.environment["CONVEX_DEPLOYMENT_URL"], !url.isEmpty {
            return url
        }
        if let url = Bundle.main.object(forInfoDictionaryKey: "CONVEX_DEPLOYMENT_URL") as? String, !url.isEmpty {
            return url
        }
        return nil
    }

    // MARK: - Authentication

    /// Attempts to restore session from Clerk on app launch
    func loginFromCache() async -> Bool {
        // Check if Clerk has an active session
        if Clerk.shared.session != nil {
            // Get the user info from Clerk
            if let user = Clerk.shared.user {
                authState = .authenticated(userId: user.id)
                return true
            }
        }
        authState = .unauthenticated
        return false
    }

    /// Called after Clerk sign-in completes
    func onSignInComplete() {
        if let user = Clerk.shared.user {
            authState = .authenticated(userId: user.id)
        }
    }

    /// Signs out the current user
    func logout() async {
        do {
            try await Clerk.shared.signOut()
            authState = .unauthenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Transcription

    /// Gets a transcription session configuration from the backend
    func getTranscriptionSession() async throws -> TranscriptionSessionConfig {
        guard let client = client else {
            throw ConvexError.clientNotInitialized
        }

        print("🎙️ Fetching transcription session from backend...")
        let result: [String: String] = try await client.action("transcription:getSession", with: [:])

        guard let wsUrl = result["wsUrl"] else {
            throw ConvexError.netError("Invalid transcription session response")
        }

        return TranscriptionSessionConfig(
            wsUrl: wsUrl,
            authToken: result["authToken"],
            config: nil
        )
    }

    // MARK: - Notes Generation

    /// Generates meeting notes using the backend AI service
    func generateNotes(transcript: String, templateId: String? = nil) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let client = self.client else {
                    continuation.finish(throwing: ConvexError.clientNotInitialized)
                    return
                }

                do {
                    print("📝 Generating notes via backend...")
                    let result: String = try await client.action("notes:generate", with: ["transcript": transcript])
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    print("❌ Notes generation failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - File Upload

    /// Uploads an audio file to Convex object storage
    func uploadAudioFile(audioFileURL: URL, meetingId: UUID) async throws -> String? {
        guard let client = client else {
            throw ConvexError.clientNotInitialized
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioFileURL)
        } catch {
            throw ConvexError.fileReadFailed
        }

        print("📤 Uploading audio file: \(audioFileURL.lastPathComponent) (\(audioData.count) bytes)")

        // Generate upload URL
        let uploadUrl: String = try await client.mutation("files:generateUploadUrl", with: [:])

        guard let url = URL(string: uploadUrl) else {
            throw ConvexError.uploadFailed("Invalid upload URL")
        }

        let contentType = audioFileURL.pathExtension.lowercased() == "m4a" ? "audio/m4a" : "audio/mpeg"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ConvexError.uploadFailed("Upload failed")
            }

            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let storageId = jsonResponse["storageId"] as? String {
                print("✅ Audio uploaded! Storage ID: \(storageId)")
                return storageId
            }
            return String(data: data, encoding: .utf8)
        } catch {
            throw ConvexError.uploadFailed(error.localizedDescription)
        }
    }

    // MARK: - OpenAI Session

    /// Generates an ephemeral OpenAI Realtime session token from backend
    func generateOpenAISession() async throws -> [String: Any] {
        guard let client = client else {
            throw ConvexError.clientNotInitialized
        }

        print("🔑 Fetching ephemeral OpenAI session from backend...")
        let result: [String: String] = try await client.action("realtime:generateSession", with: [:])

        // Convert to [String: Any] for compatibility
        var sessionData: [String: Any] = [:]
        for (key, value) in result {
            sessionData[key] = value
        }

        print("   ✅ Session fetched successfully")
        return sessionData
    }

    /// Checks if Convex is properly configured
    func isConfigured() -> Bool {
        return client != nil
    }
}

// MARK: - Supporting Types

struct TranscriptionSessionConfig {
    let wsUrl: String
    let authToken: String?
    let config: [String: Any]?
}

// MARK: - Convex Errors

enum ConvexError: LocalizedError {
    case clientNotInitialized
    case fileReadFailed
    case uploadFailed(String)
    case netError(String)
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "Backend not configured. Please set CONVEX_DEPLOYMENT_URL."
        case .fileReadFailed:
            return "Failed to read audio file."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .netError(let message):
            return "Network error: \(message)"
        case .authenticationRequired:
            return "Please sign in to continue."
        }
    }
}
