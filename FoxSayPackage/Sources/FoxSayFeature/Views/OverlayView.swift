import SwiftUI
import AppKit
import QuartzCore

// MARK: - Metrics

/// Card and window geometry for the recording HUD. The panel is the card plus a
/// transparent margin so the drop shadow has room to render without clipping.
enum OverlayMetrics {
    static let cardWidth: CGFloat = 440
    static let cardHeight: CGFloat = 80
    @MainActor
    static var cornerRadius: CGFloat { SystemChrome.windowCornerRadius }
    // Must comfortably exceed the shadow's full falloff (2 × radius + offset),
    // or the clipped shadow reads as a hard square-cornered ring on bright
    // desktops.
    static let shadowMargin: CGFloat = 28

    static var windowSize: CGSize {
        CGSize(width: cardWidth + shadowMargin * 2, height: cardHeight + shadowMargin * 2)
    }
}

// MARK: - Presentation state

/// Drives the HUD's appear/disappear transform. The window controller flips this
/// so the window-level fade and the SwiftUI drift/scale run as one motion.
@MainActor
final class OverlayPresentation: ObservableObject {
    static let shared = OverlayPresentation()

    @Published var isVisible = false

    private init() {}
}

// MARK: - Overlay

/// Compact floating overlay for recording feedback
public struct OverlayView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modeManager = VoiceModeManager.shared
    @ObservedObject private var promptManager = PromptManager.shared
    @ObservedObject private var appDetector = AppDetector.shared
    @ObservedObject private var presentation = OverlayPresentation.shared

    @State private var pulseOpacity: Double = 1.0

    public init() {}

    public var body: some View {
        // The fade itself belongs to the window's alpha; SwiftUI owns the drift
        // and the scale so the two run as one motion.
        card
            .scaleEffect(presentation.isVisible ? 1.0 : 0.97, anchor: .center)
            .offset(y: presentation.isVisible ? 0 : 8)
            .padding(OverlayMetrics.shadowMargin)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OverlayMetrics.cornerRadius, style: .continuous)
    }

    private var card: some View {
        ZStack(alignment: .topLeading) {
            cardBackground

            if let error = appState.overlayError {
                errorContent(error)
            } else {
                liveContent
            }
        }
        .frame(width: OverlayMetrics.cardWidth, height: OverlayMetrics.cardHeight)
        .clipShape(cardShape)
        .overlay(cardShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.40), radius: 10, x: 0, y: 4)
    }

    /// Neutral dark ground matching the main window. Flat on purpose: a top
    /// lift washes out the hairline border along the top edge.
    private var cardBackground: some View {
        Color(white: 0.11)
    }

    /// One status line, then the meter gets the whole band beneath it. Nothing
    /// is drawn behind the text, so both stay legible.
    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            statusRow

            MeterView(isActive: appState.isRecording)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.brandCoralLight)
                .frame(width: 8, height: 8)
                .opacity(pulseOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulseOpacity = 0.35
                    }
                }

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))

            // The animated dots read as the ellipsis while work is in flight.
            if appState.isTranscribing {
                TranscribingDots()
            }

            if modeManager.markdownModeEnabled {
                OverlayChip(text: "Markdown")
            }

            if let activePrompt = promptManager.activePrompt {
                OverlayChip(text: activePrompt.displayName)
            }

            Spacer(minLength: 8)

            if let appName = appDetector.targetAppName {
                HStack(spacing: 4) {
                    if let icon = appDetector.targetAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Text(appName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
                .fixedSize()
            }
        }
        .frame(height: 16)
    }

    private func errorContent(_ error: OverlayError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: error.icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.statusError)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(error.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var statusText: String {
        if appState.isRecording {
            return "Recording"
        } else if appState.isTranscribing {
            return "Transcribing"
        } else {
            return "Ready"
        }
    }
}

// MARK: - Small pieces

/// Quiet metadata chip for the HUD: no color coding, just a soft white fill.
struct OverlayChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.8))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.10)))
    }
}

/// Three-dot working indicator for the transcription pass. Driven off the frame
/// clock with a phase offset per dot — no chained repeating animations.
private struct TranscribingDots: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(TranscribingDots.opacity(at: time, index: index)))
                        .frame(width: 3.5, height: 3.5)
                }
            }
        }
        .frame(height: 13)
    }

    private static func opacity(at time: TimeInterval, index: Int) -> Double {
        let wave = sin(time * 3.4 - Double(index) * 0.8)
        return 0.28 + 0.55 * max(0, wave)
    }
}

// MARK: - Visualization Style

/// Available audio meter styles
public enum VisualizationStyle: String, CaseIterable, Identifiable {
    case scrolling = "scrolling"
    case spectrum = "spectrum"
    case pulsing = "pulsing"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scrolling: return "Waveform"
        case .spectrum: return "Analyzer"
        case .pulsing: return "LED Meter"
        }
    }

    public var description: String {
        switch self {
        case .scrolling: return "Scrolling recording track"
        case .spectrum: return "Spectrum analyzer with peak holds"
        case .pulsing: return "Segmented console level meter"
        }
    }
}

/// Container view that switches between meter styles
struct MeterView: View {
    let isActive: Bool

    private var visualizationStyle: VisualizationStyle {
        let stored = UserDefaults.standard.string(forKey: "visualizationStyle") ?? "scrolling"
        return VisualizationStyle(rawValue: stored) ?? .scrolling
    }

    var body: some View {
        switch visualizationStyle {
        case .scrolling:
            WaveformTrackView(isActive: isActive)
        case .spectrum:
            SpectrumAnalyzerView(isActive: isActive)
        case .pulsing:
            LevelMeterView(isActive: isActive)
        }
    }
}

// MARK: - Meter engine

/// Resting level: a meter at rest still shows life, but only just.
private let meterIdleLevel: CGFloat = 0.038

private let ledSegmentCount = 30
private let analyzerBandCount = 40
private let trackColumnCount = 108

/// The top of the scale is the hot zone, drawn in coral.
private let hotZoneStart: CGFloat = 0.85

/// Band weighting for the analyzer: energy peaks in the low formants of a voice
/// and rolls off toward the top of the range.
private func voiceBandWeights(count: Int) -> [CGFloat] {
    (0..<count).map { index in
        let position = Double(index) / Double(max(count - 1, 1))
        let formant = exp(-pow((position - 0.24) / 0.26, 2))
        let air = 0.40 * exp(-pow((position - 0.60) / 0.30, 2))
        return CGFloat(min(1.0, 0.24 + 0.76 * formant + air))
    }
}

/// Studio meter ballistics for all three styles.
///
/// The audio engine publishes a per-IO-cycle peak (`audioLevel`) and RMS
/// (`audioRMS`) roughly every 10 ms, so this reads like real metering hardware:
/// RMS drives the bar body with a near-instant attack and a slow PPM-style
/// release, while true peak drives a hold-then-fall indicator. Everything is
/// sampled once per displayed frame from `TimelineView(.animation)` and drawn
/// with `Canvas` — no `withAnimation`, no randomness.
///
/// Only ever touched from a view body, so it needs no isolation of its own.
final class MeterEngine {
    /// Bar body: attack is as fast as the 10 ms feed allows, release is the
    /// slow part that gives the meter its weight.
    private let bodyAttackTau: TimeInterval = 0.012
    private let bodyReleaseTau: TimeInterval = 0.26
    private let bandAttackTau: TimeInterval = 0.012
    private let bandReleaseTau: TimeInterval = 0.22

    /// Peak indicator: instant attack, hold, then a steady fall in level per
    /// second — the classic peak-programme-meter return.
    private let peakHoldTime: TimeInterval = 0.8
    private let peakFallRate: CGFloat = 0.55
    private let bandHoldTime: TimeInterval = 0.6
    private let bandFallRate: CGFloat = 0.9

    /// One waveform column every 1/26 s: slow enough to be calm, and fixed so
    /// the drift speed is the same on a 60 Hz and a 120 Hz display.
    private let columnInterval: TimeInterval = 1.0 / 26.0

    /// Speech RMS sits well under its peak, so the body is brought back to the
    /// calibration the amplitude setting was tuned against.
    private let rmsGain: CGFloat = 2.2

    let style: VisualizationStyle

    /// RMS-driven bar body, 0...1.
    private(set) var level: CGFloat = 0
    /// Peak-hold indicator, 0...1.
    private(set) var peakLevel: CGFloat = 0
    /// Per-band or per-column levels.
    private(set) var bars: [CGFloat]
    /// Per-band peak-hold ticks.
    private(set) var barPeaks: [CGFloat]
    /// Progress (0...1) toward the next waveform column, for sub-pixel drift.
    private(set) var scrollFraction: CGFloat = 0

    private let weights: [CGFloat]
    private var bandHoldRemaining: [TimeInterval]
    private var peakHoldRemaining: TimeInterval = 0
    private var columnCollector: CGFloat = 0
    private var columnAccumulator: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var lastTimestamp: TimeInterval?

    init(style: VisualizationStyle) {
        self.style = style
        switch style {
        case .scrolling:
            // Two extra columns live off the edges so the track drifts in and
            // out rather than popping into place.
            bars = Array(repeating: meterIdleLevel, count: trackColumnCount + 2)
            barPeaks = []
            bandHoldRemaining = []
            weights = []
        case .spectrum:
            bars = Array(repeating: meterIdleLevel, count: analyzerBandCount)
            barPeaks = Array(repeating: meterIdleLevel, count: analyzerBandCount)
            bandHoldRemaining = Array(repeating: 0, count: analyzerBandCount)
            weights = voiceBandWeights(count: analyzerBandCount)
        case .pulsing:
            // The LED meter reads `level` and `peakLevel` directly.
            bars = []
            barPeaks = []
            bandHoldRemaining = []
            weights = []
        }
    }

    func advance(to time: TimeInterval, peak: Float, rms: Float, isActive: Bool) {
        guard let delta = step(to: time, peak: peak, rms: rms, isActive: isActive) else { return }
        switch style {
        case .scrolling:
            advanceTrack(by: delta)
        case .spectrum:
            advanceBands(by: delta)
        case .pulsing:
            break
        }
    }

    // MARK: Shared step

    /// Advances the clock and the master ballistics. Returns nil when this is a
    /// repeat evaluation of a frame already processed — SwiftUI can run a body
    /// twice for one timeline date and the meter must not step twice.
    private func step(to time: TimeInterval, peak: Float, rms: Float, isActive: Bool) -> TimeInterval? {
        guard let last = lastTimestamp else {
            lastTimestamp = time
            return nil
        }
        let delta = min(time - last, 1.0 / 15.0)
        guard delta > 0 else { return nil }
        lastTimestamp = time
        elapsed += delta

        let gain = amplitude
        var rawPeak: CGFloat = 0
        var rawBody: CGFloat = 0
        if isActive {
            rawPeak = min(1, CGFloat(max(0, peak)) * gain)
            let energy = CGFloat(max(0, rms))
            rawBody = min(1, energy > 0 ? energy * gain * rmsGain : rawPeak * 0.7)
        }

        if rawPeak >= peakLevel {
            peakLevel = rawPeak
            peakHoldRemaining = peakHoldTime
        } else if peakHoldRemaining > 0 {
            peakHoldRemaining -= delta
        } else {
            peakLevel = max(rawPeak, peakLevel - peakFallRate * CGFloat(delta))
        }

        let tau = rawBody > level ? bodyAttackTau : bodyReleaseTau
        level += (rawBody - level) * coefficient(delta, tau)
        level = max(level, idleFloor(phase: elapsed * 1.7))
        // A meter's bar never overshoots its own peak indicator.
        peakLevel = max(peakLevel, level)

        // The waveform track keeps the loudest reading inside each column.
        columnCollector = max(columnCollector, rawBody)
        return delta
    }

    /// Exponential smoothing factor for a time constant over an elapsed delta.
    private func coefficient(_ delta: TimeInterval, _ tau: TimeInterval) -> CGFloat {
        1 - CGFloat(exp(-delta / tau))
    }

    private var amplitude: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "inputAmplitude")
        return CGFloat(stored > 0 ? stored : 10.0) * 0.67
    }

    /// Gentle breathing floor so a silent meter still reads as live.
    private func idleFloor(phase: Double) -> CGFloat {
        meterIdleLevel * CGFloat(0.8 + 0.4 * sin(phase))
    }

    // MARK: Waveform track

    private func advanceTrack(by delta: TimeInterval) {
        columnAccumulator += delta
        var pushes = 0
        while columnAccumulator >= columnInterval && pushes < bars.count {
            columnAccumulator -= columnInterval
            pushes += 1
            bars.removeFirst()
            bars.append(min(1, max(idleFloor(phase: elapsed * 2.0), columnCollector)))
            columnCollector = 0
        }
        if columnAccumulator >= columnInterval {
            columnAccumulator = 0  // recover from a long stall without a burst
        }
        scrollFraction = CGFloat(columnAccumulator / columnInterval)
    }

    // MARK: Analyzer bands

    private func advanceBands(by delta: TimeInterval) {
        let attack = coefficient(delta, bandAttackTau)
        let release = coefficient(delta, bandReleaseTau)

        for index in 0..<bars.count {
            // Deterministic per-band motion: no random jitter anywhere.
            let rate = 2.1 + 0.29 * Double(index)
            let wobble = 1 + 0.09 * sin(elapsed * rate + Double(index) * 1.7)
            var target = level * weights[index] * CGFloat(wobble)
            target = max(target, idleFloor(phase: elapsed * 1.9 + Double(index) * 0.45))

            let current = bars[index]
            let next = min(1, current + (target - current) * (target > current ? attack : release))
            bars[index] = next

            if next >= barPeaks[index] {
                barPeaks[index] = next
                bandHoldRemaining[index] = bandHoldTime
            } else if bandHoldRemaining[index] > 0 {
                bandHoldRemaining[index] -= delta
            } else {
                barPeaks[index] = max(next, barPeaks[index] - bandFallRate * CGFloat(delta))
            }
        }
    }
}

// MARK: - Painting

/// Shared drawing for the meters: paths are grouped so a frame costs a handful
/// of fills, never one draw call (or a shadow) per bar.
enum MeterPainter {
    // MARK: Fills

    /// Vertical fill for anything that grows upward: bright at the base, coral
    /// once a reading pushes into the hot zone at the top.
    static func columnShading(for size: CGSize) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(stops: [
                Gradient.Stop(color: Color.brandCoralLight.opacity(0.85), location: 0.00),
                Gradient.Stop(color: Color.brandCoralLight.opacity(0.45), location: 0.14),
                Gradient.Stop(color: Color.white.opacity(0.42), location: 0.34),
                Gradient.Stop(color: Color.white.opacity(0.66), location: 0.70),
                Gradient.Stop(color: Color.white.opacity(0.86), location: 1.00)
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        )
    }

    /// Slightly hotter version of the same ramp, for peak-hold ticks.
    static func tickShading(for size: CGSize) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(stops: [
                Gradient.Stop(color: Color.brandCoralLight.opacity(1.0), location: 0.00),
                Gradient.Stop(color: Color.brandCoralLight.opacity(0.70), location: 0.16),
                Gradient.Stop(color: Color.white.opacity(0.60), location: 0.40),
                Gradient.Stop(color: Color.white.opacity(0.70), location: 1.00)
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        )
    }

    /// Symmetric fill for the mirrored track: densest along the center axis,
    /// tipping coral only where a transient runs to the top or bottom.
    static func trackShading(for size: CGSize) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(stops: [
                Gradient.Stop(color: Color.brandCoralLight.opacity(0.55), location: 0.00),
                Gradient.Stop(color: Color.white.opacity(0.42), location: 0.16),
                Gradient.Stop(color: Color.white.opacity(0.88), location: 0.50),
                Gradient.Stop(color: Color.white.opacity(0.42), location: 0.84),
                Gradient.Stop(color: Color.brandCoralLight.opacity(0.55), location: 1.00)
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        )
    }

    /// Left-to-right ramp for lit LED segments, so the meter brightens as it
    /// climbs the scale.
    static func ledShading(for size: CGSize) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(colors: [Color.white.opacity(0.52), Color.white.opacity(0.86)]),
            startPoint: .zero,
            endPoint: CGPoint(x: size.width, y: 0)
        )
    }

    private static func addRoundedBar(to path: inout Path, rect: CGRect, radius: CGFloat) {
        let clamped = min(radius, min(rect.width, rect.height) / 2)
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: clamped, height: clamped),
            style: .continuous
        )
    }

    // MARK: Level meter

    /// Console channel meter: a run of segments lit by the RMS body, with a
    /// bright peak-hold segment riding above it and a coral hot zone at the top.
    static func drawLevelMeter(
        level: CGFloat,
        peak: CGFloat,
        into context: inout GraphicsContext,
        size: CGSize
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let count = ledSegmentCount
        let step = size.width / CGFloat(count)
        let width = max(2, step * 0.68)
        let height = min(size.height, 26)
        let top = (size.height - height) / 2
        let radius: CGFloat = 2.5
        let litEdge = level * CGFloat(count)
        let hotStart = Int(CGFloat(count) * hotZoneStart)
        let peakIndex = min(count - 1, max(0, Int(peak * CGFloat(count) - 0.0001)))
        let showsPeak = peak > 0.09

        var dimCool = Path()
        var dimHot = Path()
        var litCool = Path()
        var litHot = Path()
        var edgeSegment = Path()
        var edgeIsHot = false
        var edgeAmount: CGFloat = 0
        var marker = Path()
        var markerIsHot = false

        for index in 0..<count {
            let rect = CGRect(
                x: step * CGFloat(index) + (step - width) / 2,
                y: top,
                width: width,
                height: height
            )
            let isHot = index >= hotStart

            if showsPeak && index == peakIndex {
                addRoundedBar(to: &marker, rect: rect, radius: radius)
                markerIsHot = isHot
                continue
            }

            let fill = litEdge - CGFloat(index)
            if fill >= 1 {
                if isHot {
                    addRoundedBar(to: &litHot, rect: rect, radius: radius)
                } else {
                    addRoundedBar(to: &litCool, rect: rect, radius: radius)
                }
            } else if fill > 0 {
                addRoundedBar(to: &edgeSegment, rect: rect, radius: radius)
                edgeIsHot = isHot
                edgeAmount = fill
            } else if isHot {
                addRoundedBar(to: &dimHot, rect: rect, radius: radius)
            } else {
                addRoundedBar(to: &dimCool, rect: rect, radius: radius)
            }
        }

        context.fill(dimCool, with: .color(Color.white.opacity(0.09)))
        context.fill(dimHot, with: .color(Color.brandCoralLight.opacity(0.11)))
        context.fill(litCool, with: ledShading(for: size))
        context.fill(litHot, with: .color(Color.brandCoralLight.opacity(0.92)))
        context.fill(
            edgeSegment,
            with: .color(
                (edgeIsHot ? Color.brandCoralLight : Color.white)
                    .opacity(0.09 + 0.78 * edgeAmount)
            )
        )
        context.fill(
            marker,
            with: .color(markerIsHot ? Color.brandCoralLight : Color.white.opacity(0.98))
        )
    }

    // MARK: Analyzer

    /// Bottom-anchored bands with a floating peak-hold tick over each one.
    static func drawAnalyzer(
        levels: [CGFloat],
        peaks: [CGFloat],
        into context: inout GraphicsContext,
        size: CGSize
    ) {
        guard size.width > 0, size.height > 0, !levels.isEmpty else { return }

        let step = size.width / CGFloat(levels.count)
        let width = max(2, step * 0.69)
        let tickHeight: CGFloat = 2
        let minHeight: CGFloat = 2.5
        // A small radius rather than a capsule: a quiet band still reads as a
        // bar, never as a row of dots.
        let barRadius: CGFloat = 1.75

        var bars = Path()
        var ticks = Path()

        for (index, level) in levels.enumerated() {
            let x = step * CGFloat(index) + (step - width) / 2
            let height = max(minHeight, level * size.height)
            addRoundedBar(
                to: &bars,
                rect: CGRect(x: x, y: size.height - height, width: width, height: height),
                radius: barRadius
            )

            // The tick only appears once it has cleared the bar it belongs to.
            guard index < peaks.count else { continue }
            let peakHeight = peaks[index] * size.height
            guard peakHeight > height + tickHeight else { continue }
            let y = max(0, size.height - peakHeight - tickHeight)
            addRoundedBar(
                to: &ticks,
                rect: CGRect(x: x, y: y, width: width, height: tickHeight),
                radius: tickHeight / 2
            )
        }

        context.fill(bars, with: columnShading(for: size))
        context.fill(ticks, with: tickShading(for: size))
    }

    // MARK: Waveform track

    /// Mirrored recording track drifting left. `fraction` slides the whole run
    /// by a sub-column amount so the motion is continuous between pushes.
    static func drawTrack(
        levels: [CGFloat],
        fraction: CGFloat,
        into context: inout GraphicsContext,
        size: CGSize
    ) {
        guard size.width > 0, size.height > 0, levels.count > 2 else { return }

        let visible = CGFloat(levels.count - 2)
        let step = size.width / visible
        let width = max(1.5, step * 0.62)
        let middle = size.height / 2
        let maxHalf = middle * 0.96
        let minHalf: CGFloat = 1.1

        // The axis line is what makes this read as a recording track.
        context.fill(
            Path(CGRect(x: 0, y: middle - 0.5, width: size.width, height: 1)),
            with: .color(Color.white.opacity(0.12))
        )

        var path = Path()
        for (index, level) in levels.enumerated() {
            let fromRight = CGFloat(levels.count - 1 - index) + fraction
            let x = size.width - fromRight * step - width / 2
            let half = max(minHalf, min(maxHalf, level * maxHalf))
            addRoundedBar(
                to: &path,
                rect: CGRect(x: x, y: middle - half, width: width, height: half * 2),
                radius: width / 2
            )
        }

        context.clip(to: Path(CGRect(origin: .zero, size: size)))
        context.fill(path, with: trackShading(for: size))
    }
}

// MARK: - Waveform track

/// Calm, vertically centered recording track, like a DAW take.
struct WaveformTrackView: View {
    let isActive: Bool

    @ObservedObject private var presentation = OverlayPresentation.shared
    @State private var engine = MeterEngine(style: .scrolling)

    var body: some View {
        // The frame clock stops with the HUD so a hidden panel costs nothing.
        TimelineView(.animation(minimumInterval: nil, paused: !presentation.isVisible)) { timeline in
            // Levels are sampled here rather than observed, so the audio
            // engine's updates never invalidate the rest of the HUD.
            let _ = engine.advance(
                to: timeline.date.timeIntervalSinceReferenceDate,
                peak: AudioEngine.shared.audioLevel,
                rms: AudioEngine.shared.audioRMS,
                isActive: isActive
            )
            let levels = engine.bars
            let fraction = engine.scrollFraction

            Canvas(opaque: false) { context, size in
                MeterPainter.drawTrack(levels: levels, fraction: fraction, into: &context, size: size)
            }
        }
    }
}

// MARK: - Analyzer

/// Spectrum analyzer with per-band peak-hold ticks.
struct SpectrumAnalyzerView: View {
    let isActive: Bool

    @ObservedObject private var presentation = OverlayPresentation.shared
    @State private var engine = MeterEngine(style: .spectrum)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !presentation.isVisible)) { timeline in
            let _ = engine.advance(
                to: timeline.date.timeIntervalSinceReferenceDate,
                peak: AudioEngine.shared.audioLevel,
                rms: AudioEngine.shared.audioRMS,
                isActive: isActive
            )
            let levels = engine.bars
            let peaks = engine.barPeaks

            Canvas(opaque: false) { context, size in
                MeterPainter.drawAnalyzer(levels: levels, peaks: peaks, into: &context, size: size)
            }
        }
    }
}

// MARK: - Level meter

/// Segmented console level meter with a peak-hold segment.
struct LevelMeterView: View {
    let isActive: Bool

    @ObservedObject private var presentation = OverlayPresentation.shared
    @State private var engine = MeterEngine(style: .pulsing)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !presentation.isVisible)) { timeline in
            let _ = engine.advance(
                to: timeline.date.timeIntervalSinceReferenceDate,
                peak: AudioEngine.shared.audioLevel,
                rms: AudioEngine.shared.audioRMS,
                isActive: isActive
            )
            let level = engine.level
            let peak = engine.peakLevel

            Canvas(opaque: false) { context, size in
                MeterPainter.drawLevelMeter(level: level, peak: peak, into: &context, size: size)
            }
        }
    }
}

// MARK: - Window

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
        var useDefault = true
        if let savedPosition = UserDefaults.standard.dictionary(forKey: positionKey),
           let x = savedPosition["x"] as? CGFloat,
           let y = savedPosition["y"] as? CGFloat {
            // Validate that the saved position is on a currently connected screen
            let savedFrame = NSRect(x: x, y: y, width: window.frame.width, height: window.frame.height)
            let isOnScreen = NSScreen.screens.contains { screen in
                screen.frame.intersects(savedFrame)
            }
            if isOnScreen {
                window.setFrameOrigin(NSPoint(x: x, y: y))
                useDefault = false
            }
        }
        if useDefault, let screen = NSScreen.main {
            // Default: top center of main screen, card sitting ~12pt below the edge
            let screenFrame = screen.visibleFrame
            let size = OverlayMetrics.windowSize
            let x = screenFrame.midX - size.width / 2
            let y = screenFrame.maxY - size.height + OverlayMetrics.shadowMargin - 12
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        OverlayPresentation.shared.isVisible = false
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        isShowing = true
        SoundEffectManager.shared.playOpen()

        // A short hop lets SwiftUI commit the collapsed state before the
        // transform animates; the window is still fully transparent here.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            self.animateIn()
        }
    }

    private func animateIn() {
        guard isShowing, let window = window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        withAnimation(.easeOut(duration: 0.22)) {
            OverlayPresentation.shared.isVisible = true
        }
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

        withAnimation(.easeOut(duration: 0.18)) {
            OverlayPresentation.shared.isVisible = false
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
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

        let size = OverlayMetrics.windowSize
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
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
        .frame(width: OverlayMetrics.windowSize.width, height: OverlayMetrics.windowSize.height)
        .background(Color.gray.opacity(0.3))
        .onAppear { OverlayPresentation.shared.isVisible = true }
}
