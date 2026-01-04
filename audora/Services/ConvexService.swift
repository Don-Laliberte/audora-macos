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
        print("   🔗 Convex deployment: \(getConvexDeploymentURL() ?? "not configured")")

        // Step 1: Generate an upload URL via Convex mutation
        let uploadUrl: String
        do {
            print("   📞 Calling mutation: files:generateUploadUrl")

            // Try explicit String type casting - ConvexMobile SDK may need this
            // First try with explicit String type
            do {
                let result: String = try await client.mutation("files:generateUploadUrl", with: [:])
                uploadUrl = result
                print("   ✅ Mutation returned String directly: \(uploadUrl)")
            } catch {
                // If explicit String casting fails, try Any and parse
                print("   ⚠️ Explicit String casting failed, trying Any type...")
                let result: Any = try await client.mutation("files:generateUploadUrl", with: [:])
                print("   ✅ Mutation response received")
                print("   📋 Response type: \(type(of: result))")
                print("   📋 Response value: \(result)")
                print("   📋 Response is Void: \(result is Void)")
                print("   📋 Response is Void.Type: \(type(of: result) == Void.self)")

                // Check if result is Void/empty tuple - this means mutation isn't returning anything
                if type(of: result) == Void.self || String(describing: result) == "()" {
                    print("   ❌ Mutation returned Void/empty")
                    print("   💡 The mutation works in dashboard but SDK returns void")
                    print("   💡 This might be a ConvexMobile SDK version or API issue")
                    print("   💡 Try updating ConvexMobile SDK or check SDK documentation")
                    throw ConvexError.uploadFailed("Mutation returned void - SDK may need update or different API call")
                }

                // Try multiple ways to extract the URL string
                if let urlString = result as? String {
                    uploadUrl = urlString
                    print("   ✅ Extracted URL as String: \(urlString)")
                } else if let resultDict = result as? [String: Any] {
                    print("   📋 Response is a dictionary with keys: \(resultDict.keys.joined(separator: ", "))")
                    // Try common key names
                    if let urlString = resultDict["uploadUrl"] as? String {
                        uploadUrl = urlString
                    } else if let urlString = resultDict["url"] as? String {
                        uploadUrl = urlString
                    } else if let urlString = resultDict["value"] as? String {
                        uploadUrl = urlString
                    } else {
                        // Log the entire dictionary for debugging
                        print("   ❌ Dictionary doesn't contain expected keys. Full response: \(resultDict)")
                        throw ConvexError.uploadFailed("Invalid response format: dictionary doesn't contain uploadUrl, url, or value keys")
                    }
                } else if let resultArray = result as? [Any], let firstItem = resultArray.first as? String {
                    // Handle array response (unlikely but possible)
                    uploadUrl = firstItem
                    print("   ✅ Extracted URL from array: \(uploadUrl)")
                } else {
                    // Last resort: try to extract URL from string representation
                    let resultDescription = String(describing: result)
                    print("   ⚠️ Trying to extract URL from string representation: \(resultDescription)")

                    // Check if the string representation contains a URL
                    if resultDescription.hasPrefix("http://") || resultDescription.hasPrefix("https://") {
                        uploadUrl = resultDescription
                        print("   ✅ Extracted URL from string representation: \(uploadUrl)")
                    } else {
                        print("   ❌ Unexpected response type. Description: \(resultDescription)")
                        print("   💡 The mutation might not be returning a string URL as expected")
                        print("   💡 Check that 'files:generateUploadUrl' mutation exists and returns a string")
                        throw ConvexError.uploadFailed("Invalid response format: expected String or [String: Any], got \(type(of: result)). Value: \(resultDescription)")
                    }
                }
            }
        } catch {
            print("❌ Failed to generate upload URL: \(error)")
            print("   💡 Troubleshooting:")
            print("      - Check if 'files:generateUploadUrl' mutation exists in Convex Functions")
            print("      - Verify CONVEX_DEPLOYMENT_URL matches your Convex dashboard")
            print("      - Ensure mutation is deployed (run 'npx convex dev' if using CLI)")
            throw ConvexError.uploadFailed("Failed to generate upload URL: \(error.localizedDescription)")
        }

        print("   📤 Upload URL generated: \(uploadUrl)")

        // Step 2: Upload the file to the generated URL
        guard let url = URL(string: uploadUrl) else {
            throw ConvexError.uploadFailed("Invalid upload URL")
        }

        // Determine content type based on file extension
        let fileExtension = audioFileURL.pathExtension.lowercased()
        let contentType: String
        switch fileExtension {
        case "m4a":
            contentType = "audio/m4a"
        case "mp3":
            contentType = "audio/mpeg"
        case "wav":
            contentType = "audio/wav"
        case "aac":
            contentType = "audio/aac"
        case "ogg", "oga":
            contentType = "audio/ogg"
        case "flac":
            contentType = "audio/flac"
        default:
            contentType = "audio/m4a" // Default to m4a for unknown audio extensions
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(audioData.count)", forHTTPHeaderField: "Content-Length")

        do {
            print("   📡 Uploading file to Convex storage...")
            let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConvexError.uploadFailed("Invalid response type")
            }

            print("   📊 HTTP Status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("   ❌ Upload failed. Response body: \(responseBody)")
                throw ConvexError.uploadFailed("Upload failed with status code: \(httpResponse.statusCode)")
            }

            // Step 3: Parse the response to get the storage ID
            // The response should contain a JSON object with a storageId field
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let storageId = jsonResponse["storageId"] as? String {
                print("✅ Audio file uploaded successfully!")
                print("   📁 Storage ID: \(storageId)")
                print("   📊 File size: \(audioData.count) bytes (\(String(format: "%.2f", Double(audioData.count) / 1024 / 1024)) MB)")
                print("   🔗 Verify in Convex Dashboard → Files section")
                return storageId
            } else if let responseString = String(data: data, encoding: .utf8),
                      !responseString.isEmpty,
                      responseString.hasPrefix("k") || responseString.count > 10 {
                // Some Convex implementations return the storage ID directly as a string
                // Storage IDs typically start with "k" and are long strings
                print("✅ Audio file uploaded successfully!")
                print("   📁 Storage ID: \(responseString)")
                print("   📊 File size: \(audioData.count) bytes (\(String(format: "%.2f", Double(audioData.count) / 1024 / 1024)) MB)")
                print("   🔗 Verify in Convex Dashboard → Files section")
                return responseString
            } else {
                // Log the raw response for debugging
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("⚠️ Upload succeeded but could not parse storage ID from response")
                print("   Raw response: \(responseString)")
                print("   Response length: \(data.count) bytes")
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
