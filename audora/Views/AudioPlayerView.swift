// AudioPlayerView.swift
// Audio player component for playing back meeting recordings

import AVFoundation
import SwiftUI
import AppKit

struct AudioPlayerView: View {
    let audioURL: URL?
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var updateTimer: Timer?
    
    var body: some View {
        if let audioURL = audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
            VStack(spacing: 12) {
                // Play/Pause button and time display
                HStack(spacing: 12) {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: openInFinder) {
                        Image(systemName: "folder")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 4)
                                    .cornerRadius(2)
                                
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: geometry.size.width * progress, height: 4)
                                    .cornerRadius(2)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if let player = player, duration > 0 {
                                            let progress = min(max(value.location.x / geometry.size.width, 0), 1)
                                            let newTime = Double(progress) * duration
                                            player.currentTime = newTime
                                            currentTime = player.currentTime
                                        }
                                    }
                            )
                        }
                        .frame(height: 4)
                        
                        // Time labels
                        HStack {
                            Text(timeString(from: currentTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(timeString(from: duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
            .onAppear {
                setupPlayer(url: audioURL)
            }
            .onDisappear {
                cleanup()
            }
        } else {
            EmptyView()
        }
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    private func setupPlayer(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            print("❌ Failed to setup audio player: \(error)")
        }
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
            updateTimer?.invalidate()
            updateTimer = nil
        } else {
            player.play()
            isPlaying = true
            startUpdateTimer()
        }
    }
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let player = self.player {
                self.currentTime = player.currentTime
                
                // Check if playback finished
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.currentTime = 0
                    self.updateTimer?.invalidate()
                    self.updateTimer = nil
                }
            }
        }
    }
    
    private func cleanup() {
        player?.stop()
        player = nil
        updateTimer?.invalidate()
        updateTimer = nil
        isPlaying = false
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func openInFinder() {
        guard let audioURL = audioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([audioURL])
    }
}

#Preview {
    AudioPlayerView(audioURL: nil)
        .padding()
}

