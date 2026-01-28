import SwiftUI
import AppKit

/// Compact floating overlay for recording feedback
public struct OverlayView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var modeManager = VoiceModeManager.shared
    @ObservedObject private var promptManager = PromptManager.shared
    @ObservedObject private var appDetector = AppDetector.shared

    @State private var pulseOpacity: Double = 1.0

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: status left, app icon+name right
            HStack(spacing: 6) {
                // Pulsing red dot (opacity only, no scale)
                Circle()
                    .fill(Color.tertiaryAccent)
                    .frame(width: 8, height: 8)
                    .opacity(pulseOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulseOpacity = 0.4
                        }
                    }

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                // Mode indicators (compact) - darker colors for better contrast
                if modeManager.markdownModeEnabled {
                    Text("Markdown")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(red: 0.0, green: 0.55, blue: 0.55)))
                }

                if let activePrompt = promptManager.activePrompt {
                    Text(activePrompt.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(red: 0.45, green: 0.25, blue: 0.65)))
                }

                Spacer()

                // Target app icon + name (right side)
                if let appName = appDetector.targetAppName {
                    HStack(spacing: 4) {
                        if let icon = appDetector.targetAppIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text(appName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }

            // Status text or result
            Group {
                if appState.isTranscribing {
                    Text("Transcribing...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .italic()
                } else {
                    Text("Listening...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Waveform visualization
            WaveformView(audioLevel: audioEngine.audioLevel, isActive: appState.isRecording)
                .frame(height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        )
    }

    private var statusText: String {
        if appState.isRecording {
            return "Recording..."
        } else if appState.isTranscribing {
            return "Processing..."
        } else {
            return "Ready"
        }
    }

}

/// Animated scrolling waveform visualization
struct WaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    private let barCount = 40
    @State private var levels: [CGFloat] = Array(repeating: 0.1, count: 40)

    // Get amplitude multiplier from UserDefaults
    private var amplitudeMultiplier: Double {
        let stored = UserDefaults.standard.double(forKey: "inputAmplitude")
        return stored > 0 ? stored : 10.0
    }

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(barCount - 1) * 1.5
            let barWidth = (geometry.size.width - totalSpacing) / CGFloat(barCount)

            HStack(spacing: 1.5) {
                ForEach(0..<levels.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: levels[index]))
                        .frame(width: max(2, barWidth), height: barHeight(for: levels[index], maxHeight: geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: audioLevel) { _, newLevel in
            if isActive {
                updateLevels(with: newLevel)
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                // Fade to baseline when stopped
                withAnimation(.easeOut(duration: 0.3)) {
                    levels = Array(repeating: 0.1, count: barCount)
                }
            }
        }
    }

    private func barHeight(for level: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let minHeight: CGFloat = 3
        return minHeight + (maxHeight - minHeight) * level
    }

    private func barColor(for level: CGFloat) -> Color {
        if level > 0.6 {
            return Color.white.opacity(0.9)
        } else if level > 0.3 {
            return Color.white.opacity(0.6)
        } else {
            return Color.white.opacity(0.35)
        }
    }

    private func updateLevels(with rawLevel: Float) {
        // Amplify the level for visibility (speech is often quiet)
        let amplified = min(1.0, CGFloat(rawLevel) * amplitudeMultiplier)

        // Add variation for visual interest
        let variation = CGFloat.random(in: -0.1...0.1)
        let newLevel = max(0.1, min(1.0, amplified + variation))

        // Shift left and append new level
        var newLevels = Array(levels.dropFirst())
        newLevels.append(newLevel)

        withAnimation(.linear(duration: 0.025)) {
            levels = newLevels
        }
    }
}

/// Window controller for the overlay
@MainActor
public class OverlayWindowController {
    public static let shared = OverlayWindowController()

    private var window: NSPanel?
    private var isShowing = false

    private let positionKey = "transcribeOverlayWindowPosition"

    private init() {}

    public func showOverlay() {
        // Check if overlay is enabled
        let showInputOverlay = UserDefaults.standard.object(forKey: "showInputOverlay") as? Bool ?? true
        guard showInputOverlay else { return }

        if window == nil {
            createWindow()
        }

        guard let window = window else { return }

        // Restore saved position or use default position
        if let savedPosition = UserDefaults.standard.dictionary(forKey: positionKey),
           let x = savedPosition["x"] as? CGFloat,
           let y = savedPosition["y"] as? CGFloat {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            // Default: top center of main screen
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 480
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.maxY - 90  // Near top of screen
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }

        isShowing = true
        SoundEffectManager.shared.playOpen()
    }

    public func hideOverlay() {
        guard let window = window, isShowing else { return }

        // Save window position before hiding
        let position: [String: CGFloat] = [
            "x": window.frame.origin.x,
            "y": window.frame.origin.y
        ]
        UserDefaults.standard.set(position, forKey: positionKey)

        SoundEffectManager.shared.playClose()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
            }
        })

        isShowing = false
    }

    public func toggleOverlay() {
        if isShowing {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func createWindow() {
        let contentView = OverlayView()
            .environmentObject(AppState.shared)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 100)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        window = panel
    }
}

#Preview {
    OverlayView()
        .environmentObject(AppState.shared)
        .frame(width: 480, height: 100)
        .background(Color.gray.opacity(0.3))
}
