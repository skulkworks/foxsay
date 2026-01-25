import SwiftUI
import AppKit

/// Compact floating overlay for recording feedback
public struct OverlayView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var modeManager = VoiceModeManager.shared
    @ObservedObject private var appDetector = AppDetector.shared

    @State private var pulseOpacity: Double = 1.0

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: status left, app icon+name right
            HStack(spacing: 6) {
                // Pulsing red dot (opacity only, no scale)
                Circle()
                    .fill(Color.red)
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

                // Mode indicator (compact)
                if modeManager.currentMode != .none {
                    Text(modeManager.currentMode.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(modeColor))
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
                } else if let result = appState.lastResult, appState.isRecording == false {
                    Text(result.text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white)
                        .lineLimit(2)
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
        .frame(width: 220)
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

    private var modeColor: Color {
        switch modeManager.currentMode {
        case .none:
            return .gray
        case .markdown:
            return .blue
        case .javascript:
            return .yellow.opacity(0.8)
        case .php:
            return .purple
        case .python:
            return .green
        case .bash:
            return .orange
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

    private init() {}

    public func showOverlay() {
        // Check if overlay is enabled
        let showInputOverlay = UserDefaults.standard.object(forKey: "showInputOverlay") as? Bool ?? true
        guard showInputOverlay else { return }

        if window == nil {
            createWindow()
        }

        guard let window = window else { return }

        // Position at top center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 240
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
    }

    public func hideOverlay() {
        guard let window = window, isShowing else { return }

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
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 100)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
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
        .frame(width: 240, height: 100)
        .background(Color.gray.opacity(0.3))
}
