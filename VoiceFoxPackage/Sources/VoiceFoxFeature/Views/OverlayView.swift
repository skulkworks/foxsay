import SwiftUI
import AppKit

/// Spokenly-style floating overlay for recording feedback
public struct OverlayView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var modeManager = VoiceModeManager.shared

    @State private var waveformLevels: [CGFloat] = Array(repeating: 0.3, count: 20)

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack(spacing: 8) {
                // Pulsing red dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(appState.isRecording ? 1.0 : 0.5)
                    .scaleEffect(appState.isRecording ? 1.0 : 0.8)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: appState.isRecording)

                Text(statusText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Mode indicator
                if modeManager.currentMode != .none {
                    Text(modeManager.currentMode.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(modeColor)
                        )
                }
            }

            // Transcription text or placeholder
            Group {
                if appState.isTranscribing {
                    Text("Transcribing...")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .italic()
                } else if let result = appState.lastResult, appState.isRecording == false {
                    Text(result.text)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white)
                        .lineLimit(3)
                } else {
                    Text("Your voice, automatically\ntyped in real time...")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Waveform visualization
            WaveformView(audioLevel: audioEngine.audioLevel, isActive: appState.isRecording)
                .frame(height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.15))
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
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

/// Animated waveform visualization
struct WaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var levels: [CGFloat] = Array(repeating: 0.15, count: 30)
    @State private var animationTimer: Timer?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 28
        return baseHeight + (maxHeight - baseHeight) * levels[index]
    }

    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                updateLevels()
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        // Animate back to baseline
        withAnimation(.easeOut(duration: 0.3)) {
            levels = Array(repeating: 0.15, count: levels.count)
        }
    }

    private func updateLevels() {
        let baseLevel = CGFloat(audioLevel)
        withAnimation(.easeOut(duration: 0.05)) {
            levels = levels.enumerated().map { index, _ in
                // Create wave-like variation based on audio level
                let variation = CGFloat.random(in: 0.0...0.3)
                let centerDistance = abs(CGFloat(index) - CGFloat(levels.count) / 2) / CGFloat(levels.count)
                let centerBoost = 1.0 - centerDistance * 0.5
                return min(1.0, max(0.1, (baseLevel * 2 + variation) * centerBoost))
            }
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
        if window == nil {
            createWindow()
        }

        guard let window = window else { return }

        // Position at top center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 360
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.maxY - 120  // Near top of screen
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
            window.orderOut(nil)
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 140)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
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
        .frame(width: 360, height: 140)
        .background(Color.gray.opacity(0.3))
}
