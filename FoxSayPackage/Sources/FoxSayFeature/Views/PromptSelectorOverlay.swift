import SwiftUI
import AppKit
import QuartzCore

// MARK: - Metrics

/// Card and window geometry for the prompt selector. As with the recording HUD,
/// the panel is the card plus a transparent margin for the drop shadow.
enum PromptSelectorMetrics {
    static let cardWidth: CGFloat = 300
    @MainActor
    static var cornerRadius: CGFloat { SystemChrome.windowCornerRadius }
    // Must comfortably exceed the shadow's full falloff (2 × radius + offset),
    // or the clipped shadow reads as a hard square-cornered ring on bright
    // desktops.
    static let shadowMargin: CGFloat = 28
    static let listMaxHeight: CGFloat = 220

    static var windowSize: CGSize {
        CGSize(width: cardWidth + shadowMargin * 2, height: 496)
    }
}

// MARK: - Presentation state

/// Drives the selector's appear/disappear transform so the window-level fade and
/// the SwiftUI drift/scale run as one motion.
@MainActor
final class PromptSelectorPresentation: ObservableObject {
    static let shared = PromptSelectorPresentation()

    @Published var isVisible = false

    private init() {}
}

// MARK: - Window

/// Window controller for the prompt selector overlay
@MainActor
public class PromptSelectorWindowController: NSObject {
    public static let shared = PromptSelectorWindowController()

    private var window: NSPanel?
    private var isShowing = false
    private var hostingController: NSHostingController<PromptSelectorContentView>?
    private var localMonitor: Any?

    private let positionKey = "promptSelectorWindowPosition"

    private override init() {
        super.init()
    }

    public func showSelector() {
        if window == nil {
            createWindow()
        }

        guard let window = window else { return }

        let size = PromptSelectorMetrics.windowSize

        // Restore saved position or use default center position
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
            // Default: center of screen, above center
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size.width / 2
            let y = screenFrame.midY - size.height / 2 + 100
            window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }

        PromptSelectorPresentation.shared.isVisible = false
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        isShowing = true
        startKeyMonitor()

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
            PromptSelectorPresentation.shared.isVisible = true
        }
    }

    public func hideSelector() {
        guard let window = window, isShowing else { return }

        // Save window position before hiding
        let position: [String: CGFloat] = [
            "x": window.frame.origin.x,
            "y": window.frame.origin.y
        ]
        UserDefaults.standard.set(position, forKey: positionKey)

        stopKeyMonitor()

        withAnimation(.easeOut(duration: 0.18)) {
            PromptSelectorPresentation.shared.isVisible = false
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

    private func startKeyMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isShowing else { return event }

            if event.keyCode == 53 { // Escape
                self.hideSelector()
                return nil // Consume the event
            }
            return event
        }
    }

    private func stopKeyMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    public func toggleSelector() {
        if isShowing {
            hideSelector()
        } else {
            showSelector()
        }
    }

    private func createWindow() {
        let contentView = PromptSelectorContentView { [weak self] in
            self?.hideSelector()
        }

        let size = PromptSelectorMetrics.windowSize
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        self.hostingController = hostingController

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        // Set the dismiss callback
        panel.onEscape = { [weak self] in
            self?.hideSelector()
        }

        window = panel
    }
}

/// NSPanel subclass that can become key and handles keyboard events
class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Keycap

/// Keyboard hint drawn as a keycap. The HUD is dark in both system appearances,
/// so this is white-on-slate rather than the semantic `KeycapLabel`.
private struct OverlayKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(minWidth: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

// MARK: - Content

/// SwiftUI content view for the prompt selector
struct PromptSelectorContentView: View {
    @ObservedObject private var promptManager = PromptManager.shared
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @ObservedObject private var modeManager = VoiceModeManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var presentation = PromptSelectorPresentation.shared
    @State private var selectedIndex: Int = 0
    @State private var filterText: String = ""
    @FocusState private var isFocused: Bool
    @FocusState private var isFilterFocused: Bool

    let onDismiss: () -> Void

    // Total count: 1 (markdown) + AI prompt options
    private var totalOptionCount: Int {
        1 + filteredPromptOptions.count
    }

    private var filteredPromptOptions: [(id: UUID?, name: String, displayName: String)] {
        var options: [(id: UUID?, name: String, displayName: String)] = [
            (nil, "none", "None (No Prompt)")
        ]
        // Only show enabled prompts
        let enabledPrompts = promptManager.enabledPrompts

        // Apply filter if not empty
        if filterText.isEmpty {
            options += enabledPrompts.map { ($0.id, $0.name, $0.displayName) }
        } else {
            let filtered = enabledPrompts.filter {
                $0.name.localizedCaseInsensitiveContains(filterText) ||
                $0.displayName.localizedCaseInsensitiveContains(filterText)
            }
            options += filtered.map { ($0.id, $0.name, $0.displayName) }
        }
        return options
    }

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        // The fade itself belongs to the window's alpha; keeping the view opaque
        // means focus and key handling are never attached to a hidden view.
        card
            .scaleEffect(presentation.isVisible ? 1.0 : 0.97, anchor: .center)
            .offset(y: presentation.isVisible ? 0 : 8)
            .padding(PromptSelectorMetrics.shadowMargin)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(.upArrow) {
                moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.return) {
                selectCurrentOption(dismiss: true)
                return .handled
            }
            .onKeyPress(.space) {
                selectCurrentOption(dismiss: false)
                return .handled
            }
            .onAppear {
                isFocused = true
                // Set initial selection based on what's active
                if modeManager.markdownModeEnabled {
                    selectedIndex = 0
                } else if let activeId = promptManager.activePromptId,
                          let index = filteredPromptOptions.firstIndex(where: { $0.id == activeId }) {
                    selectedIndex = 1 + index // +1 because markdown is at index 0
                } else {
                    selectedIndex = 1 // Default to "None" in prompts
                }
            }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PromptSelectorMetrics.cornerRadius, style: .continuous)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            filterField
            hairline
            textProcessingSection
            hairline
            aiModelWarning
            promptSectionHeader
            promptList
        }
        .padding(12)
        .frame(width: PromptSelectorMetrics.cardWidth)
        .background(cardBackground)
        .clipShape(cardShape)
        .overlay(cardShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.40), radius: 10, x: 0, y: 4)
    }

    /// Neutral dark ground matching the main window, lifted very slightly at
    /// the top edge.
    private var cardBackground: some View {
        ZStack {
            Color(white: 0.11)
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.white.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Hotkey indicator - clickable to go to settings
            HStack(spacing: 6) {
                Button {
                    // Navigate to General settings and close overlay
                    AppState.shared.selectedSidebarItem = .general
                    // Bring main window to front
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title == "FoxSay" || $0.identifier?.rawValue == "main" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    onDismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.brandCoralLight)

                        Text("Prompts")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))

                        OverlayKeycap(text:hotkeyManager.promptSelectorModifier.shortName)

                        Image(systemName: "gear")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to change hotkey")

                Spacer()

                HStack(spacing: 4) {
                    OverlayKeycap(text:"esc")
                    Text("Close")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }

            // Title and keyboard hints
            HStack {
                Text("Select Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Text("↑↓ Navigate  ␣ Toggle  ⏎ Select")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.white.opacity(0.4))
                .font(.system(size: 11))

            TextField("Filter prompts...", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .focused($isFilterFocused)
                .onSubmit {
                    // Move focus back to main view for keyboard navigation
                    isFilterFocused = false
                    isFocused = true
                }

            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(0.4))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var aiModelWarning: some View {
        if !aiModelManager.isModelReady {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.statusWarning)
                    .font(.system(size: 10))
                Text("No AI model selected")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.statusWarning)
            }
            .padding(.vertical, 4)
        }
    }

    private var promptSectionHeader: some View {
        Text("AI Prompts")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.top, 4)
    }

    private var promptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(filteredPromptOptions.enumerated()), id: \.offset) { index, option in
                        let globalIndex = 1 + index // +1 because markdown is at 0
                        promptOptionRow(
                            option: option,
                            isSelected: globalIndex == selectedIndex,
                            isActive: isPromptActive(option)
                        )
                        .id(globalIndex)
                        .onTapGesture {
                            selectPromptOption(option, dismiss: true)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: PromptSelectorMetrics.listMaxHeight)
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 1 {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private func isPromptActive(_ option: (id: UUID?, name: String, displayName: String)) -> Bool {
        if option.id == nil {
            // "None" is active when no prompt is selected
            return promptManager.activePromptId == nil
        }
        return option.id == promptManager.activePromptId
    }

    private func promptOptionRow(
        option: (id: UUID?, name: String, displayName: String),
        isSelected: Bool,
        isActive: Bool
    ) -> some View {
        HStack {
            Text(option.displayName)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.72))
                .lineLimit(1)

            Spacer()

            if isActive {
                OverlayChip(text: "Active")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(rowBackground(isSelected: isSelected, isActive: isActive))
        .contentShape(Rectangle())
    }

    /// Coral marks the keyboard cursor; an already-active row gets a quiet fill.
    private func rowBackground(isSelected: Bool, isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return shape
            .fill(isSelected
                  ? Color.brandCoralDeep.opacity(0.38)
                  : (isActive ? Color.white.opacity(0.06) : Color.clear))
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.brandCoralLight.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
            )
    }

    private func moveSelection(by offset: Int) {
        let newIndex = selectedIndex + offset
        if newIndex >= 0 && newIndex < totalOptionCount {
            selectedIndex = newIndex
        }
    }

    private func selectCurrentOption(dismiss: Bool) {
        if selectedIndex == 0 {
            // Markdown mode toggle
            modeManager.toggleMarkdownMode()
        } else {
            // AI prompt selection
            let promptIndex = selectedIndex - 1
            guard promptIndex >= 0 && promptIndex < filteredPromptOptions.count else { return }
            selectPromptOption(filteredPromptOptions[promptIndex], dismiss: dismiss)
            return
        }
        if dismiss {
            onDismiss()
        }
    }

    private func selectPromptOption(_ option: (id: UUID?, name: String, displayName: String), dismiss: Bool = true) {
        if let id = option.id {
            promptManager.activatePrompt(id: id)
        } else {
            promptManager.deactivatePrompt()
        }
        if dismiss {
            onDismiss()
        }
    }

    @ViewBuilder
    private var textProcessingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Text Processing")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))

            // Markdown mode row - index 0 in unified navigation
            HStack {
                Text("Markdown Mode")
                    .font(.system(size: 12, weight: modeManager.markdownModeEnabled ? .semibold : .regular))
                    .foregroundStyle(Color.white.opacity(selectedIndex == 0 ? 1.0 : 0.8))

                Spacer()

                if modeManager.markdownModeEnabled {
                    OverlayChip(text: "Active")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                rowBackground(
                    isSelected: selectedIndex == 0,
                    isActive: modeManager.markdownModeEnabled
                )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                modeManager.toggleMarkdownMode()
                onDismiss()
            }
        }
    }
}

#Preview {
    PromptSelectorContentView(onDismiss: {})
        .frame(
            width: PromptSelectorMetrics.windowSize.width,
            height: PromptSelectorMetrics.windowSize.height
        )
        .background(Color.gray.opacity(0.3))
        .onAppear { PromptSelectorPresentation.shared.isVisible = true }
}
