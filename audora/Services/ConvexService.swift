// ConvexService.swift
// Handles interactions with Convex backend, including audio file uploads

import Foundation
import ConvexMobile

/// Service for interacting with Convex backend
@MainActor
class ConvexService {
    static let shared = ConvexService()
    
    private var convexClient: ConvexClient?
    
    private init() {
        // Initialize Convex client with deployment URL
        // TODO: Replace with actual Convex deployment URL from environment/config
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
        
        // TODO: Add UserDefaults or config file support for deployment URL
        // For now, return nil if not set
        return nil
    }
    
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
            // TODO: Replace "audio:generateUploadUrl" with the actual mutation name from your Convex backend
            let result = try await client.mutation("audio:generateUploadUrl", with: [:])
            if let urlString = result as? String {
                uploadUrl = urlString
            } else if let resultDict = result as? [String: Any],
                      let urlString = resultDict["uploadUrl"] as? String {
                uploadUrl = urlString
            } else {
                throw ConvexError.uploadFailed("Invalid response from generateUploadUrl mutation")
            }
        } catch {
            print("❌ Failed to generate upload URL: \(error)")
            throw ConvexError.uploadFailed("Failed to generate upload URL: \(error.localizedDescription)")
        }
        
        // Step 2: Upload the file to the generated URL
        guard let url = URL(string: uploadUrl) else {
            throw ConvexError.uploadFailed("Invalid upload URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(audioData.count)", forHTTPHeaderField: "Content-Length")
        
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ConvexError.uploadFailed("Upload failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            
            // Step 3: Parse the response to get the storage ID
            // The response should contain a JSON object with a storageId field
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let storageId = jsonResponse["storageId"] as? String {
                print("✅ Audio file uploaded successfully. Storage ID: \(storageId)")
                return storageId
            } else if let responseString = String(data: data, encoding: .utf8),
                      !responseString.isEmpty {
                // Some Convex implementations return the storage ID directly as a string
                print("✅ Audio file uploaded successfully. Storage ID: \(responseString)")
                return responseString
            } else {
                print("⚠️ Upload succeeded but could not parse storage ID from response")
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

// MARK: - Convex Errors

enum ConvexError: LocalizedError {
    case clientNotInitialized
    case fileReadFailed
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "Convex client is not initialized. Please configure CONVEX_DEPLOYMENT_URL."
        case .fileReadFailed:
            return "Failed to read audio file for upload."
        case .uploadFailed(let message):
            return "Failed to upload audio file: \(message)"
        }
    }
}
