import Foundation
import os.log

private let pipelineLog = OSLog(subsystem: "com.foxsay", category: "PIPELINE")

/// Orchestrates the text processing pipeline for transcribed text
/// New flow: Transcription → Markdown PreProcess → Prompt Detection → Vocal Corrections → AI Transform → PostProcess
@MainActor
public class CorrectionPipeline: ObservableObject {
    public static let shared = CorrectionPipeline()

    private let modeManager = VoiceModeManager.shared
    private let promptManager = PromptManager.shared
    private let providerManager = LLMProviderManager.shared
    private let dictionaryManager = DictionaryManager.shared

    // MARK: - Vocal Corrections

    private static let vocalCorrectionsEnabledKey = "vocalCorrectionsEnabled"

    /// Whether vocal corrections via AI are enabled (off by default)
    @Published public var vocalCorrectionsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(vocalCorrectionsEnabled, forKey: Self.vocalCorrectionsEnabledKey)
        }
    }

    /// The prompt used to correct spoken self-corrections in transcribed text.
    ///
    /// Leads with the instruction and three worked examples rather than a list of
    /// prohibitions. The previous wording stacked five "do not" clauses, which
    /// suppressed the edit this feature exists to make: benchmarked across the
    /// sub-2GB models, several applied no corrections at all, while others rewrote
    /// text that contained no correction ("about four in the afternoon" became
    /// "about 4:00 PM", and a git command picked up backticks). Showing the
    /// no-correction case as an example fixes both failure modes.
    ///
    /// Note the examples are load-bearing. Changing them changes behaviour, so
    /// re-benchmark rather than editing them by eye.
    static let vocalCorrectionsPrompt = """
        You edit speech-to-text transcripts. The speaker sometimes corrects themselves \
        mid-sentence. Rewrite the text keeping ONLY what the speaker finally intended, \
        and deleting the abandoned words and the correction phrase itself.

        If the speaker did not correct themselves, repeat the text back completely unchanged.

        Example 1
        Input: Let's meet on Monday, scratch that, let's meet on Friday.
        Output: Let's meet on Friday.

        Example 2
        Input: The build takes about ten minutes on this machine.
        Output: The build takes about ten minutes on this machine.

        Example 3
        Input: Email Tom, no wait, email Priya, before lunch.
        Output: Email Priya before lunch.

        Now do the same for this input. Output only the result.
        Input: {input}
        Output:
        """

    private init() {
        self.vocalCorrectionsEnabled = UserDefaults.standard.bool(forKey: Self.vocalCorrectionsEnabledKey)
    }

    /// Process transcription result through the pipeline
    /// - Parameter result: Original transcription result
    /// - Returns: Processed transcription result
    public func process(_ result: TranscriptionResult) async -> TranscriptionResult {
        var text = result.text

        // Early exit if no text detected
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            os_log(.info, log: pipelineLog, "No text detected, skipping pipeline")
            return result
        }

        os_log(.info, log: pipelineLog, ">>> INPUT: %{public}@", text)

        // Step 0: Apply dictionary replacements (filler words, custom terms)
        let beforeDictionary = text
        text = dictionaryManager.applyReplacements(text)
        if text != beforeDictionary {
            os_log(.info, log: pipelineLog, "After dictionary: %{public}@", text)
        }

        // Early exit if dictionary removed all content
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            os_log(.info, log: pipelineLog, "No text after dictionary processing, skipping pipeline")
            return result.withCorrection("")
        }

        // Step 1: Check for markdown mode trigger
        let (markdownTriggered, enableMarkdown, remainingAfterMarkdown) = modeManager.detectMarkdownTrigger(in: text)
        if markdownTriggered {
            modeManager.setMarkdownMode(enableMarkdown)
            text = remainingAfterMarkdown

            // If only trigger with no content, return empty
            if text.isEmpty {
                os_log(.info, log: pipelineLog, "Markdown trigger only, returning empty")
                return result.withCorrection("")
            }
        }

        // Step 2: Check for prompt activation/deactivation commands
        let (promptDetected, promptName, remainingAfterPrompt) = promptManager.detectPromptCommand(in: text)
        if promptDetected {
            if let name = promptName {
                promptManager.activatePrompt(byName: name)
                os_log(.info, log: pipelineLog, "Activated prompt: %{public}@", name)
            } else {
                promptManager.deactivatePrompt()
                os_log(.info, log: pipelineLog, "Deactivated prompt")
            }
            text = remainingAfterPrompt

            // If only trigger with no content, return empty
            if text.isEmpty {
                os_log(.info, log: pipelineLog, "Prompt trigger only, returning empty")
                return result.withCorrection("")
            }
        }

        // Step 3: Apply markdown preprocessing if enabled
        if modeManager.markdownModeEnabled {
            text = preProcessMarkdown(text)
            os_log(.info, log: pipelineLog, "After markdown preprocess: %{public}@", text)
        } else {
            // Minimal cleanup for non-markdown mode
            text = minimalCleanup(text)
        }

        // Step 4: Apply vocal corrections via AI (if enabled and AI model available)
        if vocalCorrectionsEnabled {
            text = await applyVocalCorrections(text)
        }

        // Step 5: Apply prompt transformation using AI
        // Priority: App-specific prompt > Manually activated prompt > None
        print("FoxSay: [PIPELINE] Checking for prompt...")

        let appDetector = AppDetector.shared
        let appPromptManager = AppPromptManager.shared
        let targetBundleId = appDetector.targetAppBundleId

        print("FoxSay: [PIPELINE] Target app: \(targetBundleId ?? "unknown")")

        // Determine which prompt to use
        var effectivePrompt: Prompt?

        // First check for app-specific prompt
        if let bundleId = targetBundleId,
           let appPrompt = appPromptManager.getDefaultPrompt(forBundleId: bundleId) {
            effectivePrompt = appPrompt
            print("FoxSay: [PIPELINE] Using app-specific prompt: \(appPrompt.name) (for \(bundleId))")
        }
        // Fall back to manually activated prompt
        else if let activePrompt = promptManager.activePrompt {
            effectivePrompt = activePrompt
            print("FoxSay: [PIPELINE] Using active prompt: \(activePrompt.name)")
        }

        if let prompt = effectivePrompt {
            os_log(.info, log: pipelineLog, "Using prompt: %{public}@", prompt.name)
            print("FoxSay: [PIPELINE] Input text to LLM: \"\(text)\"")
            print("FoxSay: [PIPELINE] Prompt template: \"\(prompt.promptText)\"")

            // Determine which transformer to use
            // Check for app-specific remote provider override first
            var transformer: (any TextTransformer)?

            if let bundleId = targetBundleId,
               let modelRef = appPromptManager.getModelReference(forBundleId: bundleId) {
                switch modelRef {
                case .remote(let providerId):
                    if let provider = LLMProviderManager.shared.remoteProviders.first(where: { $0.id == providerId && $0.isEnabled }) {
                        transformer = RemoteLLMService(provider: provider)
                        print("FoxSay: [PIPELINE] Using app-specific remote provider: \(provider.name)")
                        os_log(.info, log: pipelineLog, "Using app-specific remote provider: %{public}@", provider.name)
                    }
                }
            }

            // Fall back to default transformer if no app-specific model
            if transformer == nil {
                transformer = await providerManager.getTransformer()
                print("FoxSay: [PIPELINE] Using default provider")
            }

            // Check if LLM provider is ready
            let isReady = transformer != nil || providerManager.isReady
            print("FoxSay: [PIPELINE] Provider ready = \(isReady)")

            if let transformer = transformer {
                do {
                    let isAvailable = await transformer.isAvailable

                    if isAvailable {
                        // Pass the prompt template - transformer will substitute {input}
                        let transformed = try await transformer.transform(text, prompt: prompt.promptText)
                        print("FoxSay: [PIPELINE] LLM output: \"\(transformed)\"")
                        text = transformed
                        os_log(.info, log: pipelineLog, "After AI transform: %{public}@", text)
                    } else {
                        os_log(.info, log: pipelineLog, "Transformer not available, skipping transform")
                    }
                } catch {
                    os_log(.error, log: pipelineLog, "AI transform error: %{public}@", String(describing: error))
                    print("FoxSay: [PIPELINE] LLM error: \(error)")
                }
            } else {
                os_log(.info, log: pipelineLog, "No transformer available, skipping transform")
                print("FoxSay: [PIPELINE] No transformer available, skipping transform")
            }
        } else {
            print("FoxSay: [PIPELINE] No prompt active, skipping AI transform")
        }

        // Step 6: Post-processing cleanup
        text = postProcess(text)

        os_log(.info, log: pipelineLog, "<<< OUTPUT: %{public}@", text)

        // Return corrected result if text changed
        if text != result.text {
            return result.withCorrection(text)
        }

        return result
    }

    /// Apply vocal corrections using the AI model
    /// Sends text through the LLM with a correction-specific prompt to clean up
    /// spoken self-corrections, false starts, and revision phrases.
    private func applyVocalCorrections(_ text: String) async -> String {
        // Get the transformer (same logic as prompt step, respects app-specific overrides)
        let appDetector = AppDetector.shared
        let appPromptManager = AppPromptManager.shared
        let targetBundleId = appDetector.targetAppBundleId

        var transformer: (any TextTransformer)?

        // Check for app-specific remote provider override
        if let bundleId = targetBundleId,
           let modelRef = appPromptManager.getModelReference(forBundleId: bundleId) {
            switch modelRef {
            case .remote(let providerId):
                if let provider = LLMProviderManager.shared.remoteProviders.first(where: { $0.id == providerId && $0.isEnabled }) {
                    transformer = RemoteLLMService(provider: provider)
                }
            }
        }

        // Fall back to default transformer
        if transformer == nil {
            transformer = await providerManager.getTransformer()
        }

        guard let transformer = transformer else {
            os_log(.info, log: pipelineLog, "Vocal corrections: no transformer available, skipping")
            return text
        }

        do {
            let isAvailable = await transformer.isAvailable
            guard isAvailable else {
                os_log(.info, log: pipelineLog, "Vocal corrections: transformer not available, skipping")
                return text
            }

            print("FoxSay: [PIPELINE] Applying vocal corrections...")
            let corrected = try await transformer.transform(text, prompt: Self.vocalCorrectionsPrompt)
            os_log(.info, log: pipelineLog, "After vocal corrections: %{public}@", corrected)
            print("FoxSay: [PIPELINE] Vocal corrections result: \"\(corrected)\"")
            return corrected
        } catch {
            os_log(.error, log: pipelineLog, "Vocal corrections error: %{public}@", String(describing: error))
            print("FoxSay: [PIPELINE] Vocal corrections error: \(error)")
            return text
        }
    }

    /// Minimal cleanup for non-markdown text
    private func minimalCleanup(_ text: String) -> String {
        var result = text

        // Remove commas that Whisper adds between repeated words
        result = result.replacingOccurrences(of: ",", with: "")

        // Remove double spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pre-processing for markdown mode - converts spoken markdown commands to syntax
    private func preProcessMarkdown(_ text: String) -> String {
        var result = text

        // Remove commas that Whisper adds
        result = result.replacingOccurrences(of: ",", with: "")

        // Normalize spoken words to lowercase
        let spokenWords = [
            "Hash", "Dash", "Dot", "Equals", "Colon", "Semicolon", "Plus", "Minus",
            "Open", "Close", "Paren", "Bracket", "Brace", "Curly",
            "Quote", "Quotes", "Tick", "Backtick",
            "H1", "H2", "H3", "H4", "H5", "H6", "Heading",
            "Bold", "Italic", "Bullet", "Number", "Numbered", "List",
            "Link", "Image", "Code", "Codeblock", "Quote", "Checkbox", "Checked",
            "Horizontal", "Rule", "Divider", "Endcode",
        ]
        for word in spokenWords {
            result = result.replacingOccurrences(of: word, with: word.lowercased())
        }

        // Handle consecutive hashes (longest first)
        result = result.replacingOccurrences(of: "hash hash hash hash hash hash ", with: "###### ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash hash hash hash hash ", with: "##### ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash hash hash hash ", with: "#### ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash hash hash ", with: "### ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash hash ", with: "## ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "hash ", with: "# ", options: .caseInsensitive)

        // Handle dashes
        result = result.replacingOccurrences(of: "dash dash ", with: "-- ", options: .caseInsensitive)

        // Formatting toggles
        let startTriggersSuffixes = [" ", ". ", ".", ", ", ","]
        let endTriggersSuffixes = [" ", ". ", ".", ", ", ",", ""]

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
        for base in ["strike on", "strike start", "start strike", "strikethrough on"] {
            for suffix in startTriggersSuffixes {
                result = result.replacingOccurrences(of: base + suffix, with: "~~", options: .caseInsensitive)
            }
        }
        for base in ["strike off", "strike end", "end strike", "strikethrough off"] {
            for suffix in endTriggersSuffixes {
                result = result.replacingOccurrences(of: " " + base + suffix, with: "~~" + (suffix == "" ? "" : " "), options: .caseInsensitive)
            }
        }

        // Block elements at start of line
        let blockElements: [(trigger: String, replacement: String)] = [
            ("h6 ", "###### "), ("h5 ", "##### "), ("h4 ", "#### "),
            ("h3 ", "### "), ("h2 ", "## "), ("h1 ", "# "),
            ("heading 6 ", "###### "), ("heading 5 ", "##### "), ("heading 4 ", "#### "),
            ("heading 3 ", "### "), ("heading 2 ", "## "), ("heading 1 ", "# "),
            ("bullet ", "- "), ("list item ", "- "),
            ("numbered ", "1. "), ("number ", "1. "),
            ("block quote ", "> "), ("quote ", "> "),
            ("checkbox ", "- [ ] "), ("todo ", "- [ ] "), ("checked ", "- [x] "),
            ("code block ", "```"), ("codeblock ", "```"),
        ]

        for element in blockElements {
            if result.lowercased().hasPrefix(element.trigger) {
                result = element.replacement + String(result.dropFirst(element.trigger.count))
            }
            result = result.replacingOccurrences(of: "\n" + element.trigger, with: "\n" + element.replacement, options: .caseInsensitive)
        }

        // End code block
        result = result.replacingOccurrences(of: "end code block", with: "\n```", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "end codeblock", with: "\n```", options: .caseInsensitive)

        // Horizontal rule
        if result.lowercased() == "horizontal rule" || result.lowercased() == "divider" {
            result = "---"
        }

        // Line breaks
        result = result.replacingOccurrences(of: "new line", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "line break", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "next line", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "new paragraph", with: "\n\n", options: .caseInsensitive)

        // Remove double spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Post-processing cleanup
    private func postProcess(_ text: String) -> String {
        var result = text

        // Collapse consecutive hashes
        while result.contains("# #") {
            result = result.replacingOccurrences(of: "# #", with: "##")
        }

        // Collapse consecutive dashes
        while result.contains("- -") {
            result = result.replacingOccurrences(of: "- -", with: "--")
        }

        // Remove double spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
