// AudioRecordingManager.swift
// Handles saving audio recordings to disk

import AVFoundation
import Foundation
import Combine

/// Manages audio file recording and saving
class AudioRecordingManager: ObservableObject {
    static let shared = AudioRecordingManager()
    
    private var micAudioFile: AVAudioFile?
    private var systemAudioFile: AVAudioFile?
    private var micFileURL: URL?
    private var systemFileURL: URL?
    private var micFormat: AVAudioFormat?
    private var systemFormat: AVAudioFormat?
    
    private let documentsDirectory: URL
    private let recordingsDirectory: URL
    
    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        recordingsDirectory = documentsDirectory.appendingPathComponent("Recordings")
        
        // Ensure recordings directory exists
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    }
    
    /// Starts recording audio for a meeting
    /// - Parameter meetingId: The ID of the meeting
    @MainActor
    func startRecording(for meetingId: UUID) {
        print("🎙️ Starting audio recording for meeting: \(meetingId)")
        
        // Create file URLs for this meeting
        micFileURL = recordingsDirectory.appendingPathComponent("\(meetingId.uuidString)_mic.caf")
        systemFileURL = recordingsDirectory.appendingPathComponent("\(meetingId.uuidString)_system.caf")
        
        // Clean up any existing files
        if let micFileURL = micFileURL {
            try? FileManager.default.removeItem(at: micFileURL)
        }
        if let systemFileURL = systemFileURL {
            try? FileManager.default.removeItem(at: systemFileURL)
        }
    }
    
    /// Records a microphone audio buffer
    /// - Parameters:
    ///   - buffer: The audio buffer to record
    ///   - format: The audio format
    func recordMicBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        // Initialize mic file if needed
        if micAudioFile == nil, let fileURL = micFileURL {
            do {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false
                ]
                
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                micAudioFile = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
                micFormat = format
                print("✅ Created mic audio file: \(fileURL.lastPathComponent)")
            } catch {
                print("❌ Failed to create mic audio file: \(error)")
            }
        }
        
        // Write buffer to file
        if let file = micAudioFile {
            do {
                try file.write(from: buffer)
            } catch {
                print("❌ Failed to write mic audio buffer: \(error)")
            }
        }
    }
    
    /// Records a system audio buffer
    /// - Parameters:
    ///   - buffer: The audio buffer to record
    ///   - format: The audio format
    func recordSystemBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        // Initialize system file if needed
        if systemAudioFile == nil, let fileURL = systemFileURL {
            do {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false
                ]
                
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                systemAudioFile = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
                systemFormat = format
                print("✅ Created system audio file: \(fileURL.lastPathComponent)")
            } catch {
                print("❌ Failed to create system audio file: \(error)")
            }
        }
        
        // Write buffer to file
        if let file = systemAudioFile {
            do {
                try file.write(from: buffer)
            } catch {
                print("❌ Failed to write system audio buffer: \(error)")
            }
        }
    }
    
    /// Stops recording and saves the audio file
    /// - Parameter meetingId: The ID of the meeting
    /// - Returns: The URL of the saved audio file, or nil if failed
    @MainActor
    func stopRecordingAndSave(for meetingId: UUID) -> URL? {
        print("🛑 Stopping audio recording for meeting: \(meetingId)")
        
        // Close audio files
        micAudioFile = nil
        systemAudioFile = nil
        
        // Create output file URL
        let outputURL = recordingsDirectory.appendingPathComponent("\(meetingId.uuidString).m4a")
        
        // Prefer mic audio if available, otherwise use system audio
        if let micURL = micFileURL, FileManager.default.fileExists(atPath: micURL.path) {
            print("✅ Using mic audio file")
            if let savedURL = convertToM4A(sourceURL: micURL, outputURL: outputURL) {
                try? FileManager.default.removeItem(at: micURL)
                if let systemURL = systemFileURL {
                    try? FileManager.default.removeItem(at: systemURL)
                }
                return savedURL
            }
        } else if let systemURL = systemFileURL, FileManager.default.fileExists(atPath: systemURL.path) {
            print("✅ Using system audio file")
            if let savedURL = convertToM4A(sourceURL: systemURL, outputURL: outputURL) {
                try? FileManager.default.removeItem(at: systemURL)
                return savedURL
            }
        }
        
        print("⚠️ No audio files were recorded")
        return nil
    }
    
    
    private func convertToM4A(sourceURL: URL, outputURL: URL) -> URL? {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 128000
            ])
            
            let bufferSize: AVAudioFrameCount = 4096
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!
            
            sourceFile.framePosition = 0
            while sourceFile.framePosition < sourceFile.length {
                try sourceFile.read(into: buffer)
                try outputFile.write(from: buffer)
            }
            
            return outputURL
        } catch {
            print("❌ Failed to convert audio file: \(error)")
            return nil
        }
    }
}

