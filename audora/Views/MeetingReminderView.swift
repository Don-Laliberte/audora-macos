import SwiftUI

struct MeetingReminderView: View {
    let appName: String
    let onRecord: () -> Void
    let onIgnore: () -> Void
    let onSettings: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false
    @State private var isPulsing = false
    @State private var progress: CGFloat = 0.0
    private let duration: TimeInterval = 10.0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Icon or Indicator
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                        .animation(
                            .easeInOut(duration: 1).repeatForever(
                                autoreverses: true
                            ),
                            value: isPulsing
                        )
                }
                .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Meeting Detected")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)

                    Text("in \(appName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onRecord) {
                        Text("Record")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.red)
                                    .shadow(
                                        color: Color.red.opacity(0.3),
                                        radius: 4,
                                        x: 0,
                                        y: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("Ignore \(appName)", action: onIgnore)
                        Button("Settings...", action: onSettings)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(12)

            // Minimalist Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 2)

                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * progress, height: 2)
                        .animation(.linear(duration: 0.05), value: progress)
                }
            }
            .frame(height: 2)
        }
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        .frame(width: 320)
        .onAppear {
            isPulsing = true
        }
        .onReceive(timer) { _ in
            // Pause timer if user is hovering over the view
            if isHovering { return }

            if progress < 1.0 {
                progress += 0.05 / duration
            } else {
                timer.upstream.connect().cancel()
                onDismiss()
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    MeetingReminderView(
        appName: "Zoom",
        onRecord: {},
        onIgnore: {},
        onSettings: {},
        onDismiss: {}
    )
    .padding()
    .background(Color.blue)
}
