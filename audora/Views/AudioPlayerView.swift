import SwiftUI
import AVFoundation

struct AudioPlayerView: View {
    @StateObject private var playerManager = AudioPlayerManager()
    let audioURL: URL?
    
    var body: some View {
        Group {
            if let audioURL = audioURL {
                audioPlayerContent(audioURL: audioURL)
            } else {
                placeholderContent
            }
        }
    }
    
    private func audioPlayerContent(audioURL: URL) -> some View {
        VStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    // Progress track
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * playerManager.progress, height: 4)
                        .cornerRadius(2)
                    
                    // Draggable thumb
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * playerManager.progress - 6)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                                    playerManager.seek(to: newProgress)
                                }
                        )
                }
            }
            .frame(height: 12)
            
            // Controls and info
            HStack(spacing: 16) {
                // Skip backward button
                Button(action: {
                    playerManager.skipBackward()
                }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                
                // Play/Pause button
                Button(action: {
                    playerManager.togglePlayback()
                }) {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                
                // Skip forward button
                Button(action: {
                    playerManager.skipForward()
                }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                
                Spacer()
                
                // Time display
                Text(playerManager.currentTimeString)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                
                Text("/")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(playerManager.durationString)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                
                // Speed control
                Menu {
                    ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button(action: {
                            playerManager.setPlaybackRate(speed)
                        }) {
                            HStack {
                                Text("\(speed, specifier: "%.2f")x")
                                if playerManager.playbackRate == speed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(playerManager.playbackRate, specifier: "%.2f")x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            playerManager.loadAudio(url: audioURL)
        }
        .onDisappear {
            playerManager.cleanup()
        }
    }
    
    private var placeholderContent: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text("No audio file available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Audio Player Manager

@MainActor
class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var playbackRate: Double = 1.0
    @Published var isReady = false
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    var currentTimeString: String {
        formatTime(currentTime)
    }
    
    var durationString: String {
        formatTime(duration)
    }
    
    func loadAudio(url: URL) {
        cleanup()
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.enableRate = true
            audioPlayer?.rate = Float(playbackRate)
            
            duration = audioPlayer?.duration ?? 0.0
            isReady = duration > 0
            
            if isReady {
                startTimer()
            }
        } catch {
            print("❌ Failed to load audio: \(error)")
            isReady = false
        }
    }
    
    func togglePlayback() {
        guard let player = audioPlayer else { return }
        
        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.play()
            startTimer()
        }
        
        isPlaying = player.isPlaying
    }
    
    func skipBackward() {
        guard let player = audioPlayer else { return }
        let newTime = max(0, player.currentTime - 10)
        player.currentTime = newTime
        updateProgress()
    }
    
    func skipForward() {
        guard let player = audioPlayer else { return }
        let newTime = min(duration, player.currentTime + 10)
        player.currentTime = newTime
        updateProgress()
    }
    
    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        let newTime = progress * duration
        player.currentTime = newTime
        updateProgress()
    }
    
    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        audioPlayer?.rate = Float(rate)
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateProgress() {
        guard let player = audioPlayer, duration > 0 else { return }
        currentTime = player.currentTime
        progress = currentTime / duration
        isPlaying = player.isPlaying
        
        // Auto-stop when finished
        if progress >= 1.0 && isPlaying {
            player.pause()
            player.currentTime = 0
            isPlaying = false
            progress = 0
            currentTime = 0
        }
    }
    
    func cleanup() {
        stopTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        duration = 0
        isReady = false
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    AudioPlayerView(audioURL: nil)
        .frame(width: 600)
        .padding()
}

#Preview("With Audio") {
    // For preview, you can use a sample audio file path
    AudioPlayerView(audioURL: nil)
        .frame(width: 600)
        .padding()
}

