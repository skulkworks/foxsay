import Foundation
import os.log

private let llmLog = OSLog(subsystem: "com.voicefox", category: "LLM-DEBUG")

/// Orchestrates the correction pipeline for transcribed text
@MainActor
public class CorrectionPipeline: ObservableObject {
    public static let shared = CorrectionPipeline()

    private let ruleCorrector = RuleBasedCorrector()
    private let modeManager = VoiceModeManager.shared

    // UserDefaults keys
    private static let devCorrectionEnabledKey = "devCorrectionEnabled"
    private static let llmCorrectionEnabledKey = "llmCorrectionEnabled"
    private static let llmAlwaysApplyKey = "llmAlwaysApply"

    /// Whether to apply dev corrections
    @Published public var devCorrectionEnabled: Bool {
        didSet { UserDefaults.standard.set(devCorrectionEnabled, forKey: Self.devCorrectionEnabledKey) }
    }

    /// Whether to use LLM for ambiguous cases
    @Published public var llmCorrectionEnabled: Bool {
        didSet { UserDefaults.standard.set(llmCorrectionEnabled, forKey: Self.llmCorrectionEnabledKey) }
    }

    /// When true, always use LLM (skip heuristics). When false, only use for detected patterns.
    @Published public var llmAlwaysApply: Bool {
        didSet { UserDefaults.standard.set(llmAlwaysApply, forKey: Self.llmAlwaysApplyKey) }
    }

    private init() {
        // Load settings from UserDefaults
        let defaults = UserDefaults.standard

        // Default to true if not set
        if defaults.object(forKey: Self.devCorrectionEnabledKey) == nil {
            self.devCorrectionEnabled = true
        } else {
            self.devCorrectionEnabled = defaults.bool(forKey: Self.devCorrectionEnabledKey)
        }

        self.llmCorrectionEnabled = defaults.bool(forKey: Self.llmCorrectionEnabledKey)

        // Default to true if not set
        if defaults.object(forKey: Self.llmAlwaysApplyKey) == nil {
            self.llmAlwaysApply = true
        } else {
            self.llmAlwaysApply = defaults.bool(forKey: Self.llmAlwaysApplyKey)
        }
    }

    /// Process transcription result through the correction pipeline
    /// - Parameters:
    ///   - result: Original transcription result
    ///   - isDevApp: Whether the frontmost app is a developer app
    /// - Returns: Corrected transcription result
    public func process(
        _ result: TranscriptionResult,
        isDevApp: Bool
    ) async -> TranscriptionResult {
        // If not a dev app or dev correction disabled, return original
        guard isDevApp && devCorrectionEnabled else {
            return result
        }

        // Log raw speech input
        os_log(.info, log: llmLog, ">>> SPEECH: %{public}@", result.text)

        // Step 1: Check for mode trigger FIRST (before preprocessing)
        // This allows us to know if symbol conversion should be applied
        let (detectedMode, remainingText) = modeManager.detectMode(in: result.text)
        var correctedText = result.text

        if let mode = detectedMode {
            modeManager.setMode(mode)
            correctedText = remainingText
            os_log(.info, log: llmLog, "Mode detected and set: %{public}@, remaining: %{public}@", mode.rawValue, remainingText)

            // If only mode trigger with no content, return empty (mode shown in overlay)
            if correctedText.isEmpty {
                os_log(.info, log: llmLog, "Mode-only input, returning empty")
                return result.withCorrection("")
            }
        }

        // Get current mode (either just set or persisted from before)
        let currentMode = modeManager.currentMode
        os_log(.info, log: llmLog, "Current mode: %{public}@", currentMode.rawValue)

        // Step 2: Pre-process to clean up transcription artifacts
        // Apply different preprocessing based on mode:
        // - none: minimal cleanup only (commas, spaces)
        // - markdown: markdown-specific conversions (hash headers, bold/italic, etc.)
        // - programming: all conversions
        correctedText = preProcess(correctedText, mode: currentMode)

        // Step 3: Apply LLM/rule-based correction (skip entirely in 'none' mode)
        // In 'none' mode, we want raw transcription with minimal cleanup only
        if currentMode != .none {
            if llmCorrectionEnabled {
                let llmCorrector = LLMCorrector.shared
                let isAvailable = await llmCorrector.available

                // Apply LLM when in a specific mode, or when llmAlwaysApply is on, or heuristics detect patterns
                let heuristicsApply = await llmCorrector.shouldApplyCorrection(correctedText)
                let shouldApply = llmAlwaysApply || heuristicsApply

                os_log(.info, log: llmLog, "LLM check - mode: %{public}@, enabled: %d, available: %d, shouldApply: %d",
                       currentMode.rawValue, llmCorrectionEnabled, isAvailable, shouldApply)

                if isAvailable && shouldApply {
                    do {
                        // Use mode-specific prompt
                        let prompt = modeManager.getPromptForMode(currentMode)
                        let llmCorrected = try await llmCorrector.correct(correctedText, prompt: prompt)
                        os_log(.info, log: llmLog, "<<< FINAL OUTPUT: %{public}@", llmCorrected)
                        correctedText = llmCorrected
                    } catch {
                        os_log(.error, log: llmLog, "ERROR: %{public}@", String(describing: error))
                    }
                } else if !isAvailable {
                    os_log(.info, log: llmLog, "LLM not available (model not downloaded/loaded)")
                    // Fallback to rule-based when LLM not available (only in programming modes)
                    if currentMode.requiresSymbolConversion {
                        correctedText = ruleCorrector.correct(correctedText)
                    }
                }
            } else {
                // Apply rule-based corrections when LLM disabled (only in programming modes)
                if currentMode.requiresSymbolConversion {
                    correctedText = ruleCorrector.correct(correctedText)
                }
            }
        } else {
            os_log(.info, log: llmLog, "Mode is 'none' - skipping all corrections, returning cleaned text")
        }

        // Step 4: Post-processing cleanup
        correctedText = postProcess(correctedText)

        // Return corrected result if text changed
        if correctedText != result.text {
            return result.withCorrection(correctedText)
        }

        return result
    }

    /// Pre-processing cleanup before LLM
    /// - Parameters:
    ///   - text: Raw transcription text
    ///   - mode: Current voice mode - determines which conversions to apply:
    ///           - none: minimal cleanup only (commas, spaces)
    ///           - markdown: markdown-specific conversions (hash headers, bold/italic, etc.)
    ///           - programming: all conversions including spoken symbols
    private func preProcess(_ text: String, mode: VoiceMode) -> String {
        var result = text

        // === ALWAYS APPLY (all modes) ===

        // Remove commas that Parakeet/Whisper adds between repeated words
        result = result.replacingOccurrences(of: ",", with: "")

        // In 'none' mode, only do minimal cleanup
        guard mode != .none else {
            // Remove double spaces and trim
            while result.contains("  ") {
                result = result.replacingOccurrences(of: "  ", with: " ")
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // === MARKDOWN AND PROGRAMMING MODES ===

        // Normalize spoken punctuation words to lowercase (Parakeet often capitalizes first word)
        let spokenWords = [
            // Punctuation
            "Hash", "Dash", "Dot", "Equals", "Colon", "Semicolon", "Plus", "Minus",
            "Open", "Close", "Paren", "Bracket", "Brace", "Curly",
            "Greater", "Less", "Than", "Pipe", "Slash", "Backslash",
            "Quote", "Quotes", "Tick", "Backtick", "Tilde", "Bang", "At",
            "Ampersand", "Percent", "Caret", "Star", "Asterisk", "Underscore",
            // Programming keywords
            "Const", "Let", "Var", "Function", "Def", "Class", "Import", "Export",
            "Return", "If", "Else", "For", "While", "True", "False", "None", "Null",
            "Self", "This", "Async", "Await", "Try", "Catch", "Throw",
            // Commands
            "Git", "Npm", "Pip", "Curl", "Sudo", "Chmod", "Mkdir", "Echo", "Grep",
            // Markdown keywords
            "H1", "H2", "H3", "H4", "H5", "H6", "Heading",
            "Bold", "Italic", "Bullet", "Number", "Numbered", "List",
            "Link", "Image", "Code", "Codeblock", "Quote", "Checkbox", "Checked",
            "Horizontal", "Rule", "Divider", "Endcode",
        ]
        for word in spokenWords {
            result = result.replacingOccurrences(of: word, with: word.lowercased())
        }

        // Handle consecutive hashes deterministically (LLM struggles with counting)
        // Must do longer patterns first
        result = result.replacingOccurrences(of: "hash hash hash hash hash hash ", with: "###### ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash hash hash hash hash ", with: "##### ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash hash hash hash ", with: "#### ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash hash hash ", with: "### ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash hash ", with: "## ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash ", with: "# ", options: .caseInsensitive)

        // Handle consecutive dashes deterministically
        result = result.replacingOccurrences(of: "dash dash ", with: "-- ", options: .caseInsensitive)

        // Handle formatting toggles deterministically (bold, italic, code)
        // Supports: "bold on", "bold start", "start bold" and "bold off", "bold end", "end bold"
        // Also handles punctuation after triggers (period, comma)

        let startTriggersSuffixes = [" ", ". ", ".", ", ", ","]  // space, period+space, period, comma+space, comma
        let endTriggersSuffixes = [" ", ". ", ".", ", ", ",", ""]  // same plus end-of-string

        // Bold
        for base in ["bold on", "bold start", "start bold"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "**", options: .caseInsensitive)
            }
        }
        for base in ["bold off", "bold end", "end bold"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "**" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Italic
        for base in ["italic on", "italic start", "start italic"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "*", options: .caseInsensitive)
            }
        }
        for base in ["italic off", "italic end", "end italic"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "*" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Code (inline)
        for base in ["code on", "code start", "start code"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "`", options: .caseInsensitive)
            }
        }
        for base in ["code off", "code end", "end code"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "`" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Strikethrough
        for base in ["strike on", "strike start", "start strike", "strikethrough on", "strikethrough start"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "~~", options: .caseInsensitive)
            }
        }
        for base in ["strike off", "strike end", "end strike", "strikethrough off", "strikethrough end"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "~~" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Highlight/Mark (extended markdown)
        for base in ["highlight on", "highlight start", "start highlight", "mark on", "mark start"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "==", options: .caseInsensitive)
            }
        }
        for base in ["highlight off", "highlight end", "end highlight", "mark off", "mark end"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "==" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Bold Italic (combined)
        for base in ["bold italic on", "bold italic start", "start bold italic"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "***", options: .caseInsensitive)
            }
        }
        for base in ["bold italic off", "bold italic end", "end bold italic"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "***" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Subscript (extended markdown: ~text~)
        for base in ["subscript on", "subscript start", "start subscript", "sub on", "sub start"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "~", options: .caseInsensitive)
            }
        }
        for base in ["subscript off", "subscript end", "end subscript", "sub off", "sub end"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "~" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Superscript (extended markdown: ^text^)
        for base in ["superscript on", "superscript start", "start superscript", "super on", "super start"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "^", options: .caseInsensitive)
            }
        }
        for base in ["superscript off", "superscript end", "end superscript", "super off", "super end"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "^" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Markdown block elements - only at start of line (start of string or after newline)
        // This prevents "quote" mid-sentence from becoming ">"
        let blockElements: [(trigger: String, replacement: String)] = [
            // Headings
            ("h6 ", "###### "),
            ("h5 ", "##### "),
            ("h4 ", "#### "),
            ("h3 ", "### "),
            ("h2 ", "## "),
            ("h1 ", "# "),
            ("heading 6 ", "###### "),
            ("heading 5 ", "##### "),
            ("heading 4 ", "#### "),
            ("heading 3 ", "### "),
            ("heading 2 ", "## "),
            ("heading 1 ", "# "),
            // Lists
            ("bullet ", "- "),
            ("list item ", "- "),
            ("numbered ", "1. "),
            ("number ", "1. "),
            // Quotes
            ("block quote ", "> "),
            ("quote ", "> "),
            // Tasks
            ("checkbox ", "- [ ] "),
            ("todo ", "- [ ] "),
            ("checked ", "- [x] "),
            // Code blocks
            ("code block ", "```"),
            ("codeblock ", "```"),
        ]

        for element in blockElements {
            // Match at start of string
            if result.lowercased().hasPrefix(element.trigger) {
                result = element.replacement + String(result.dropFirst(element.trigger.count))
            }
            // Match after newline
            result = result.replacingOccurrences(of: "\n" + element.trigger, with: "\n" + element.replacement, options: .caseInsensitive)
        }

        // End code block (can appear anywhere)
        result = result.replacingOccurrences(of: "end code block", with: "\n```", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "end codeblock", with: "\n```", options: .caseInsensitive)

        // Horizontal rule (standalone - typically at start of line)
        if result.lowercased() == "horizontal rule" || result.lowercased() == "divider" {
            result = "---"
        }
        result = result.replacingOccurrences(of: "\nhorizontal rule", with: "\n---", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "\ndivider", with: "\n---", options: .caseInsensitive)

        // Links: [text](url)
        // "link text" or "open link" → [
        // "link to" or "link url" → ](
        // "end link" or "close link" → )
        result = result.replacingOccurrences(of: "open link ", with: "[", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "link text ", with: "[", options: .caseInsensitive)
        result = result.replacingOccurrences(of: " link to ", with: "](", options: .caseInsensitive)
        result = result.replacingOccurrences(of: " link url ", with: "](", options: .caseInsensitive)
        // End link - with and without leading space, with and without trailing punctuation
        for ending in ["end link", "close link"] {
            result = result.replacingOccurrences(of: " " + ending + ".", with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: " " + ending + ",", with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: " " + ending, with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: ending + ".", with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: ending + ",", with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: ending, with: ")", options: .caseInsensitive)
        }

        // Images: ![alt](url)
        // "image alt" or "open image" → ![
        // "image source" or "image url" → ](
        // "end image" or "close image" → )
        result = result.replacingOccurrences(of: "open image ", with: "![", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "image alt ", with: "![", options: .caseInsensitive)
        result = result.replacingOccurrences(of: " image source ", with: "](", options: .caseInsensitive)
        result = result.replacingOccurrences(of: " image url ", with: "](", options: .caseInsensitive)
        // End image - with and without leading space, with and without trailing punctuation
        for ending in ["end image", "close image"] {
            result = result.replacingOccurrences(of: " " + ending + ".", with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: " " + ending + ",", with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: " " + ending, with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: ending + ".", with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: ending + ",", with: ")", options: .caseInsensitive)
            result = result.replacingOccurrences(of: ending, with: ")", options: .caseInsensitive)
        }

        // Line breaks and paragraphs
        result = result.replacingOccurrences(of: "new line", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "line break", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "next line", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "enter", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "return", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "new paragraph", with: "\n\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "paragraph break", with: "\n\n", options: .caseInsensitive)

        // URL cleanup - speech-to-text often adds spaces around URL components
        // First, normalize various "colon slash slash" patterns to ://
        result = result.replacingOccurrences(of: "colon slash slash", with: "://", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "colon forward slash forward slash", with: "://", options: .caseInsensitive)

        // Clean up spaced out :// patterns (keep running until no more changes)
        var previousResult = ""
        while previousResult != result {
            previousResult = result
            result = result.replacingOccurrences(of: " : ", with: ":")
            result = result.replacingOccurrences(of: ": / /", with: "://")
            result = result.replacingOccurrences(of: " / / ", with: "//")
            result = result.replacingOccurrences(of: " / /", with: "//")
            result = result.replacingOccurrences(of: "/ / ", with: "//")
            result = result.replacingOccurrences(of: " // ", with: "//")
            result = result.replacingOccurrences(of: ":/ /", with: "://")
            result = result.replacingOccurrences(of: ": //", with: "://")
            result = result.replacingOccurrences(of: " ://", with: "://")
            result = result.replacingOccurrences(of: ":// ", with: "://")
        }

        // Clean up spaces around slashes and dots (only after URL protocol detected)
        if result.contains("://") {
            // Keep cleaning until stable
            previousResult = ""
            while previousResult != result {
                previousResult = result
                result = result.replacingOccurrences(of: " / ", with: "/")
                result = result.replacingOccurrences(of: " /", with: "/")
                result = result.replacingOccurrences(of: "/ ", with: "/")
                result = result.replacingOccurrences(of: " . ", with: ".")
                result = result.replacingOccurrences(of: " .", with: ".")
                result = result.replacingOccurrences(of: ". ", with: ".")
            }
        }

        // Footnote reference: [^1]
        result = result.replacingOccurrences(of: "footnote ", with: "[^", options: .caseInsensitive)
        result = result.replacingOccurrences(of: " end footnote", with: "]", options: .caseInsensitive)

        // Remove double spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Post-processing cleanup
    private func postProcess(_ text: String) -> String {
        var result = text

        // Collapse consecutive hashes for markdown headings (# # # -> ###)
        while result.contains("# #") {
            result = result.replacingOccurrences(of: "# #", with: "##")
        }

        // Collapse consecutive dashes (- - -> --)
        while result.contains("- -") {
            result = result.replacingOccurrences(of: "- -", with: "--")
        }

        // Remove double spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Trim whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Get correction statistics
    public struct CorrectionStats {
        public let originalLength: Int
        public let correctedLength: Int
        public let rulesApplied: Int
        public let llmUsed: Bool
    }
}
