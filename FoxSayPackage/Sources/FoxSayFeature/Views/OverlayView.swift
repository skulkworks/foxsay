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
        ZStack(alignment: .bottom) {
            if appState.overlayErrorMessage != nil {
                // Error state - no waveform, just error message
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.35))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Microphone Detected")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Connect a microphone and try again")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            } else {
                // Normal recording state
                // Background visualization - fills entire overlay
                WaveformView(audioLevel: audioEngine.audioLevel, isActive: appState.isRecording)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.85)

                // Text content floating on top
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
                            .foregroundColor(.white)

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
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Status text
                    Group {
                        if appState.isTranscribing {
                            Text("Transcribing...")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.85))
                                .italic()
                        } else {
                            Text("Listening...")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 440, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.10))
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

// MARK: - Visualization Style

/// Available audio visualization styles
public enum VisualizationStyle: String, CaseIterable, Identifiable {
    case scrolling = "scrolling"
    case spectrum = "spectrum"
    case pulsing = "pulsing"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scrolling: return "Scrolling"
        case .spectrum: return "Spectrum"
        case .pulsing: return "Pulsing"
        }
    }

    public var description: String {
        switch self {
        case .scrolling: return "Classic scrolling waveform"
        case .spectrum: return "Gradient frequency bars"
        case .pulsing: return "Centered pulsing bars"
        }
    }
}

/// Container view that switches between visualization styles
struct WaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    private var visualizationStyle: VisualizationStyle {
        let stored = UserDefaults.standard.string(forKey: "visualizationStyle") ?? "scrolling"
        return VisualizationStyle(rawValue: stored) ?? .scrolling
    }

    var body: some View {
        switch visualizationStyle {
        case .scrolling:
            ScrollingWaveformView(audioLevel: audioLevel, isActive: isActive)
        case .spectrum:
            SpectrumVisualizationView(audioLevel: audioLevel, isActive: isActive)
        case .pulsing:
            PulsingVisualizationView(audioLevel: audioLevel, isActive: isActive)
        }
    }
}

// MARK: - Scrolling Waveform (Original)

/// Animated scrolling waveform visualization
struct ScrollingWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    private let barCount = 48
    @State private var levels: [CGFloat] = Array(repeating: 0.02, count: 48)

    // Get amplitude multiplier from UserDefaults (default 10 = normal scale)
    private var amplitudeMultiplier: Double {
        let stored = UserDefaults.standard.double(forKey: "inputAmplitude")
        return stored > 0 ? stored : 10.0
    }

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(barCount - 1) * 2
            let barWidth = (geometry.size.width - totalSpacing) / CGFloat(barCount)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<levels.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barGradient(for: levels[index]))
                        .frame(width: max(3, barWidth), height: barHeight(for: levels[index], maxHeight: geometry.size.height))
                        .shadow(color: barColor(for: levels[index]).opacity(levels[index] * 0.6), radius: levels[index] * 6, x: 0, y: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onChange(of: audioLevel) { _, newLevel in
            if isActive {
                updateLevels(with: newLevel)
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                withAnimation(.easeOut(duration: 0.1)) {
                    levels = Array(repeating: 0.02, count: barCount)
                }
            }
        }
    }

    private func barHeight(for level: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let minHeight: CGFloat = 3
        return minHeight + (maxHeight - minHeight) * level
    }

    private func barGradient(for level: CGFloat) -> LinearGradient {
        let color = barColor(for: level)
        return LinearGradient(
            colors: [color, color.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func barColor(for level: CGFloat) -> Color {
        // Green (low) → Yellow (mid) → Orange → Red (high)
        if level < 0.3 {
            // Green zone
            let t = level / 0.3
            return interpolateScrollColor(
                from: Color(red: 0.2, green: 0.8, blue: 0.3),   // Green
                to: Color(red: 0.6, green: 0.9, blue: 0.2),     // Yellow-green
                t: t
            )
        } else if level < 0.55 {
            // Yellow zone
            let t = (level - 0.3) / 0.25
            return interpolateScrollColor(
                from: Color(red: 0.6, green: 0.9, blue: 0.2),   // Yellow-green
                to: Color(red: 1.0, green: 0.85, blue: 0.1),    // Yellow
                t: t
            )
        } else if level < 0.75 {
            // Orange zone
            let t = (level - 0.55) / 0.2
            return interpolateScrollColor(
                from: Color(red: 1.0, green: 0.85, blue: 0.1),  // Yellow
                to: Color(red: 1.0, green: 0.5, blue: 0.1),     // Orange
                t: t
            )
        } else {
            // Red zone
            let t = (level - 0.75) / 0.25
            return interpolateScrollColor(
                from: Color(red: 1.0, green: 0.5, blue: 0.1),   // Orange
                to: Color(red: 1.0, green: 0.25, blue: 0.2),    // Red
                t: t
            )
        }
    }

    private func interpolateScrollColor(from: Color, to: Color, t: CGFloat) -> Color {
        let fromComponents = NSColor(from).cgColor.components ?? [0, 0, 0, 1]
        let toComponents = NSColor(to).cgColor.components ?? [0, 0, 0, 1]

        let r = fromComponents[0] + (toComponents[0] - fromComponents[0]) * t
        let g = fromComponents[1] + (toComponents[1] - fromComponents[1]) * t
        let b = fromComponents[2] + (toComponents[2] - fromComponents[2]) * t

        return Color(red: r, green: g, blue: b)
    }

    private func updateLevels(with rawLevel: Float) {
        // Use amplitude setting directly (default 10 gives reasonable scale)
        let amplified = min(1.0, CGFloat(rawLevel) * amplitudeMultiplier * 0.67)

        // Add variation for visual interest
        let variation = CGFloat.random(in: -0.08...0.12)
        let newLevel = max(0.02, min(1.0, amplified + variation))

        // Shift left and append new level
        var newLevels = Array(levels.dropFirst())
        newLevels.append(newLevel)

        levels = newLevels
    }
}

// MARK: - Spectrum Visualization

/// Gradient spectrum analyzer-style visualization with fixed bars
struct SpectrumVisualizationView: View {
    let audioLevel: Float
    let isActive: Bool

    private let barCount = 36
    @State private var levels: [CGFloat]
    @State private var previousLevels: [CGFloat]

    init(audioLevel: Float, isActive: Bool) {
        self.audioLevel = audioLevel
        self.isActive = isActive
        let initial = Array(repeating: CGFloat(0.02), count: 36)
        _levels = State(initialValue: initial)
        _previousLevels = State(initialValue: initial)
    }

    private var amplitudeMultiplier: Double {
        let stored = UserDefaults.standard.double(forKey: "inputAmplitude")
        return stored > 0 ? stored : 10.0
    }

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(barCount - 1) * 2.5
            let barWidth = (geometry.size.width - totalSpacing) / CGFloat(barCount)

            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    spectrumBar(index: index, barWidth: barWidth, maxHeight: geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onChange(of: audioLevel) { _, newLevel in
            if isActive {
                updateSpectrum(with: newLevel)
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                withAnimation(.easeOut(duration: 0.1)) {
                    levels = Array(repeating: 0.02, count: barCount)
                    previousLevels = Array(repeating: 0.02, count: barCount)
                }
            }
        }
    }

    private func spectrumBar(index: Int, barWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let level = levels[index]
        let minHeight: CGFloat = 3
        let height = minHeight + (maxHeight - minHeight) * level

        let gradient = spectrumGradient(for: index)

        return RoundedRectangle(cornerRadius: 2)
            .fill(gradient)
            .frame(width: max(4, barWidth), height: height)
            .shadow(color: spectrumColor(for: index).opacity(level * 0.8), radius: level * 8, x: 0, y: 0)
    }

    private func spectrumGradient(for index: Int) -> LinearGradient {
        let color = spectrumColor(for: index)
        return LinearGradient(
            colors: [color, color.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func spectrumColor(for index: Int) -> Color {
        let position = CGFloat(index) / CGFloat(barCount - 1)

        // Gradient: Pink (0) → Purple (0.33) → Blue (0.66) → Cyan (1.0)
        if position < 0.33 {
            let t = position / 0.33
            return interpolateColor(
                from: Color(red: 1.0, green: 0.4, blue: 0.7),   // Pink
                to: Color(red: 0.7, green: 0.3, blue: 0.9),     // Purple
                t: t
            )
        } else if position < 0.66 {
            let t = (position - 0.33) / 0.33
            return interpolateColor(
                from: Color(red: 0.7, green: 0.3, blue: 0.9),   // Purple
                to: Color(red: 0.3, green: 0.5, blue: 1.0),     // Blue
                t: t
            )
        } else {
            let t = (position - 0.66) / 0.34
            return interpolateColor(
                from: Color(red: 0.3, green: 0.5, blue: 1.0),   // Blue
                to: Color(red: 0.2, green: 0.9, blue: 0.9),     // Cyan
                t: t
            )
        }
    }

    private func interpolateColor(from: Color, to: Color, t: CGFloat) -> Color {
        let fromComponents = NSColor(from).cgColor.components ?? [0, 0, 0, 1]
        let toComponents = NSColor(to).cgColor.components ?? [0, 0, 0, 1]

        let r = fromComponents[0] + (toComponents[0] - fromComponents[0]) * t
        let g = fromComponents[1] + (toComponents[1] - fromComponents[1]) * t
        let b = fromComponents[2] + (toComponents[2] - fromComponents[2]) * t

        return Color(red: r, green: g, blue: b)
    }

    private func updateSpectrum(with rawLevel: Float) {
        // Use amplitude setting (default 10 gives 2/3 of max)
        let amplified = min(1.0, CGFloat(rawLevel) * amplitudeMultiplier * 0.67)

        var newLevels = [CGFloat]()
        for i in 0..<barCount {
            let position = CGFloat(i) / CGFloat(barCount - 1)

            // Human voice frequency distribution - tuned for full range
            var bandMultiplier: CGFloat
            if position < 0.2 {
                // Low frequencies (fundamentals)
                bandMultiplier = 0.75 + CGFloat.random(in: 0...0.5)
            } else if position < 0.45 {
                // Mid-low (formants) - highest energy for voice
                bandMultiplier = 0.95 + CGFloat.random(in: 0...0.5)
            } else if position < 0.7 {
                // Mid-high
                bandMultiplier = 0.7 + CGFloat.random(in: 0...0.55)
            } else {
                // High frequencies
                bandMultiplier = 0.4 + CGFloat.random(in: 0...0.5)
            }

            let targetLevel = amplified * bandMultiplier

            // Very fast attack, quick decay
            let prevLevel = previousLevels[i]
            let newLevel: CGFloat
            if targetLevel > prevLevel {
                newLevel = prevLevel + (targetLevel - prevLevel) * 0.92
            } else {
                newLevel = prevLevel + (targetLevel - prevLevel) * 0.7
            }

            newLevels.append(max(0.02, min(1.0, newLevel)))
        }

        previousLevels = newLevels
        levels = newLevels
    }
}

// MARK: - Pulsing Visualization

/// Centered pulsing bars with glow effect
struct PulsingVisualizationView: View {
    let audioLevel: Float
    let isActive: Bool

    private let barCount = 32
    @State private var levels: [CGFloat]
    @State private var previousLevel: CGFloat = 0.02

    init(audioLevel: Float, isActive: Bool) {
        self.audioLevel = audioLevel
        self.isActive = isActive
        _levels = State(initialValue: Array(repeating: CGFloat(0.02), count: 32))
    }

    private var amplitudeMultiplier: Double {
        let stored = UserDefaults.standard.double(forKey: "inputAmplitude")
        return stored > 0 ? stored : 10.0
    }

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(barCount - 1) * 2.5
            let barWidth = (geometry.size.width - totalSpacing) / CGFloat(barCount)

            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    pulsingBar(index: index, barWidth: barWidth, maxHeight: geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onChange(of: audioLevel) { _, newLevel in
            if isActive {
                updatePulse(with: newLevel)
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                withAnimation(.easeOut(duration: 0.1)) {
                    levels = Array(repeating: 0.02, count: barCount)
                    previousLevel = 0.02
                }
            }
        }
    }

    private func pulsingBar(index: Int, barWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let level = levels[index]
        let minHeight: CGFloat = 3
        let height = minHeight + (maxHeight - minHeight) * level

        let color = pulsingColor(for: index)

        return RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: max(4, barWidth), height: height)
            .shadow(color: color.opacity(level * 0.9), radius: level * 10, x: 0, y: 0)
    }

    private func pulsingColor(for index: Int) -> Color {
        let centerIndex = CGFloat(barCount - 1) / 2.0
        let distance = abs(CGFloat(index) - centerIndex)
        let normalizedDistance = distance / centerIndex

        // Color based on position: Green (center) → Yellow → Orange → Red (edges)
        if normalizedDistance < 0.3 {
            let t = normalizedDistance / 0.3
            return interpolatePulseColor(
                from: Color(red: 0.2, green: 0.95, blue: 0.3),   // Bright green
                to: Color(red: 0.7, green: 0.95, blue: 0.2),     // Yellow-green
                t: t
            )
        } else if normalizedDistance < 0.6 {
            let t = (normalizedDistance - 0.3) / 0.3
            return interpolatePulseColor(
                from: Color(red: 0.7, green: 0.95, blue: 0.2),   // Yellow-green
                to: Color(red: 1.0, green: 0.85, blue: 0.1),     // Yellow
                t: t
            )
        } else {
            let t = (normalizedDistance - 0.6) / 0.4
            return interpolatePulseColor(
                from: Color(red: 1.0, green: 0.85, blue: 0.1),   // Yellow
                to: Color(red: 1.0, green: 0.4, blue: 0.2),      // Orange-red
                t: t
            )
        }
    }

    private func interpolatePulseColor(from: Color, to: Color, t: CGFloat) -> Color {
        let fromComponents = NSColor(from).cgColor.components ?? [0, 0, 0, 1]
        let toComponents = NSColor(to).cgColor.components ?? [0, 0, 0, 1]

        let r = fromComponents[0] + (toComponents[0] - fromComponents[0]) * t
        let g = fromComponents[1] + (toComponents[1] - fromComponents[1]) * t
        let b = fromComponents[2] + (toComponents[2] - fromComponents[2]) * t

        return Color(red: r, green: g, blue: b)
    }

    private func updatePulse(with rawLevel: Float) {
        // Use amplitude setting (default 10 gives 2/3 of max)
        let amplified = min(1.0, CGFloat(rawLevel) * amplitudeMultiplier * 0.67)

        // Very fast attack, quick decay
        let baseLevel: CGFloat
        if amplified > previousLevel {
            baseLevel = previousLevel + (amplified - previousLevel) * 0.95
        } else {
            baseLevel = previousLevel + (amplified - previousLevel) * 0.65
        }
        previousLevel = baseLevel

        // Calculate levels for each bar with bell curve shape and variation
        var newLevels = [CGFloat]()
        let centerIndex = CGFloat(barCount - 1) / 2.0

        for i in 0..<barCount {
            let distance = abs(CGFloat(i) - centerIndex)
            let normalizedDistance = distance / centerIndex

            // Bell curve - center bars are taller
            let bellFactor = exp(-normalizedDistance * normalizedDistance * 1.8) * 0.8 + 0.2

            // Add per-bar variation for organic feel
            let variation = CGFloat.random(in: 0.88...1.12)
            let level = baseLevel * bellFactor * variation

            newLevels.append(max(0.02, min(1.0, level)))
        }

        levels = newLevels
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
