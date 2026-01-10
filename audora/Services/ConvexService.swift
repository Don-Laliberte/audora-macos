// ConvexService.swift
// Handles interactions with Convex backend, including audio file uploads and transcription

import Foundation
import ConvexMobile

/// Service for interacting with Convex backend
@MainActor
class ConvexService {
    static let shared = ConvexService()

    private var convexClient: ConvexClient?

    private init() {
        // Initialize Convex client with deployment URL
        if let deploymentURL = getConvexDeploymentURL() {
            convexClient = ConvexClient(deploymentUrl: deploymentURL)
            print("✅ Convex client initialized with URL: \(deploymentURL)")
        } else {
            print("⚠️ Convex deployment URL not configured")
        }
    }

    /// Gets the Convex deployment URL from environment or configuration
    /// - Returns: The Convex deployment URL, or nil if not configured
    private func getConvexDeploymentURL() -> String? {
        // Check environment variable first
        if let url = ProcessInfo.processInfo.environment["CONVEX_DEPLOYMENT_URL"], !url.isEmpty {
            return url
        }

        // Check Info.plist (set via xcconfig)
        if let url = Bundle.main.object(forInfoDictionaryKey: "CONVEX_DEPLOYMENT_URL") as? String, !url.isEmpty {
            return url
        }

        return nil
    }

    // MARK: - Authentication

    /// Sets the authentication token for authenticated requests
    /// - Parameter token: The Clerk session token
    func setAuthToken(_ token: String) async {
        await convexClient?.setAuth(token: token)
        print("✅ Convex auth token set")
    }

    /// Clears the authentication token
    func clearAuthToken() async {
        await convexClient?.setAuth(token: nil)
        print("✅ Convex auth token cleared")
    }

    // MARK: - Transcription

    /// Gets a transcription session configuration from the backend
    /// - Returns: WebSocket URL and configuration for real-time transcription
    func getTranscriptionSession() async throws -> TranscriptionSessionConfig {
        guard let client = convexClient else {
            throw ConvexError.clientNotInitialized
        }

        print("🎙️ Fetching transcription session from backend...")
        let result: Any = try await client.action("transcription:getSession", with: [:])

        if let sessionData = result as? [String: Any],
           let wsUrl = sessionData["wsUrl"] as? String {
            print("   ✅ Transcription session received")
            return TranscriptionSessionConfig(
                wsUrl: wsUrl,
                authToken: sessionData["authToken"] as? String,
                config: sessionData["config"] as? [String: Any]
            )
        } else {
            throw ConvexError.netError("Invalid transcription session response")
        }
    }

    // MARK: - Notes Generation

    /// Generates meeting notes using the backend AI service
    /// - Parameters:
    ///   - transcript: The meeting transcript text
    ///   - templateId: Optional template ID for note generation
    /// - Returns: AsyncThrowingStream of note content chunks
    func generateNotes(transcript: String, templateId: String? = nil) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let client = self.convexClient else {
                    continuation.finish(throwing: ConvexError.clientNotInitialized)
                    return
                }

                do {
                    var args: [String: Any] = ["transcript": transcript]
                    if let templateId = templateId {
                        args["templateId"] = templateId
                    }

                    print("📝 Generating notes via backend...")
                    let result: Any = try await client.action("notes:generate", with: args)

                    if let notes = result as? String {
                        continuation.yield(notes)
                        continuation.finish()
                    } else if let notesData = result as? [String: Any],
                              let content = notesData["content"] as? String {
                        continuation.yield(content)
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: ConvexError.netError("Invalid notes response format"))
                    }
                } catch {
                    print("❌ Notes generation failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - File Upload

    /// Uploads an audio file to Convex object storage
    /// - Parameters:
    ///   - audioFileURL: Local file URL of the audio file to upload
    ///   - meetingId: The ID of the meeting this audio belongs to
    /// - Returns: The storage ID returned from Convex, or nil if upload failed
    func uploadAudioFile(audioFileURL: URL, meetingId: UUID) async throws -> String? {
        guard let client = convexClient else {
            throw ConvexError.clientNotInitialized
        }

        // Read the audio file data
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioFileURL)
        } catch {
            throw ConvexError.fileReadFailed
        }

        print("📤 Uploading audio file to Convex: \(audioFileURL.lastPathComponent) (\(audioData.count) bytes)")

        // Step 1: Generate an upload URL via Convex mutation
        let uploadUrl: String
        do {
            let result: String = try await client.mutation("files:generateUploadUrl", with: [:])
            uploadUrl = result
        } catch {
            print("❌ Failed to generate upload URL: \(error)")
            throw ConvexError.uploadFailed("Failed to generate upload URL: \(error.localizedDescription)")
        }

        // Step 2: Upload the file to the generated URL
        guard let url = URL(string: uploadUrl) else {
            throw ConvexError.uploadFailed("Invalid upload URL")
        }

        // Determine content type based on file extension
        let fileExtension = audioFileURL.pathExtension.lowercased()
        let contentType: String
        switch fileExtension {
        case "m4a": contentType = "audio/m4a"
        case "mp3": contentType = "audio/mpeg"
        case "wav": contentType = "audio/wav"
        case "aac": contentType = "audio/aac"
        case "ogg", "oga": contentType = "audio/ogg"
        case "flac": contentType = "audio/flac"
        default: contentType = "audio/m4a"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(audioData.count)", forHTTPHeaderField: "Content-Length")

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConvexError.uploadFailed("Invalid response type")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ConvexError.uploadFailed("Upload failed with status code: \(httpResponse.statusCode)")
            }

            // Parse the response to get the storage ID
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let storageId = jsonResponse["storageId"] as? String {
                print("✅ Audio file uploaded successfully! Storage ID: \(storageId)")
                return storageId
            } else if let responseString = String(data: data, encoding: .utf8),
                      !responseString.isEmpty {
                print("✅ Audio file uploaded successfully!")
                return responseString
            } else {
                return nil
            }
        } catch {
            print("❌ Failed to upload audio file: \(error)")
            throw ConvexError.uploadFailed(error.localizedDescription)
        }
    }

    /// Checks if Convex is properly configured
    /// - Returns: True if Convex client is initialized, false otherwise
    func isConfigured() -> Bool {
        return convexClient != nil
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
            return "Convex client is not initialized. Please configure CONVEX_DEPLOYMENT_URL."
        case .fileReadFailed:
            return "Failed to read audio file for upload."
        case .uploadFailed(let message):
            return "Failed to upload audio file: \(message)"
        case .netError(let message):
            return "Network error: \(message)"
        case .authenticationRequired:
            return "Authentication required. Please sign in."
        }
    }
}
