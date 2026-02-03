import SwiftUI
import AppKit

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

        // Restore saved position or use default center position
        if let savedPosition = UserDefaults.standard.dictionary(forKey: positionKey),
           let x = savedPosition["x"] as? CGFloat,
           let y = savedPosition["y"] as? CGFloat {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            // Default: center of screen, above center
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 300
            let windowHeight: CGFloat = 400
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.midY - windowHeight / 2 + 100
            window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }

        isShowing = true
        startKeyMonitor()
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

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
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

        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        self.hostingController = hostingController

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
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

/// SwiftUI content view for the prompt selector
struct PromptSelectorContentView: View {
    @ObservedObject private var promptManager = PromptManager.shared
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @ObservedObject private var modeManager = VoiceModeManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @State private var selectedIndex: Int = 0
    @State private var filterText: String = ""
    @FocusState private var isFocused: Bool
    @FocusState private var isFilterFocused: Bool

    let onDismiss: () -> Void

    // Darker colors for better badge contrast
    private let markdownBadgeColor = Color(red: 0.0, green: 0.55, blue: 0.55) // Darker teal
    private let promptBadgeColor = Color(red: 0.45, green: 0.25, blue: 0.65) // Darker purple
    private let hotkeyBadgeColor = Color(red: 0.659, green: 0.333, blue: 0.969) // Dashboard purple

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
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            filterField
            Divider().background(Color.white.opacity(0.2))
            textProcessingSection
            Divider().background(Color.white.opacity(0.2))
            aiModelWarning
            promptSectionHeader
            promptList
        }
        .padding(12)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        )
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
                            .foregroundColor(hotkeyBadgeColor)

                        Text("Prompts")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))

                        Text(hotkeyManager.promptSelectorModifier.shortName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(hotkeyBadgeColor.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                        Image(systemName: "gear")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to change hotkey")

                Spacer()

                Text("⎋ Close")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }

            // Title and keyboard hints
            HStack {
                Text("Select Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text("↑↓ Navigate  ␣ Toggle  ⏎ Select")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 11))

            TextField("Filter prompts...", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
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
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.1))
        )
    }

    @ViewBuilder
    private var aiModelWarning: some View {
        if !aiModelManager.isModelReady {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 10))
                Text("No AI model selected")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
            .padding(.vertical, 4)
        }
    }

    private var promptSectionHeader: some View {
        Text("AI Prompts")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
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
            .frame(maxHeight: 250)
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 1 {
                    withAnimation(.easeOut(duration: 0.1)) {
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
                .foregroundColor(.white.opacity(isSelected ? 1.0 : 0.7))

            Spacer()

            if isActive {
                Text("Active")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(promptBadgeColor))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? promptBadgeColor.opacity(0.4) : Color.clear)
        )
        .contentShape(Rectangle())
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
                .foregroundColor(.white.opacity(0.5))

            // Markdown mode row - index 0 in unified navigation
            HStack {
                Text("Markdown Mode")
                    .font(.system(size: 12, weight: modeManager.markdownModeEnabled ? .semibold : .regular))
                    .foregroundColor(.white.opacity(selectedIndex == 0 ? 1.0 : 0.8))

                Spacer()

                if modeManager.markdownModeEnabled {
                    Text("Active")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(markdownBadgeColor))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedIndex == 0 ? markdownBadgeColor.opacity(0.4) : (modeManager.markdownModeEnabled ? markdownBadgeColor.opacity(0.15) : Color.clear))
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
        .frame(width: 300, height: 400)
        .background(Color.gray.opacity(0.3))
}
