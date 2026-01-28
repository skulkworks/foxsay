import Foundation
import os.log

private let pipelineLog = OSLog(subsystem: "com.foxsay", category: "PIPELINE")

/// Orchestrates the text processing pipeline for transcribed text
/// New flow: Transcription → Markdown PreProcess → Prompt Detection → AI Transform → PostProcess
@MainActor
public class CorrectionPipeline: ObservableObject {
    public static let shared = CorrectionPipeline()

    private let modeManager = VoiceModeManager.shared
    private let promptManager = PromptManager.shared
    private let aiModelManager = AIModelManager.shared

    private init() {}

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

        // Step 4: Apply active prompt transformation using AI
        print("FoxSay: [PIPELINE] Checking for active prompt...")
        print("FoxSay: [PIPELINE] activePromptId = \(String(describing: promptManager.activePromptId))")

        if let activePrompt = promptManager.activePrompt {
            os_log(.info, log: pipelineLog, "Active prompt: %{public}@", activePrompt.name)
            print("FoxSay: [PIPELINE] Active prompt: \(activePrompt.name)")
            print("FoxSay: [PIPELINE] Input text to LLM: \"\(text)\"")
            print("FoxSay: [PIPELINE] Prompt template: \"\(activePrompt.promptText)\"")

            // Check if AI model is ready
            print("FoxSay: [PIPELINE] AI model ready = \(aiModelManager.isModelReady)")
            if aiModelManager.isModelReady {
                do {
                    let llmCorrector = LLMCorrector.shared
                    let isAvailable = await llmCorrector.available

                    if isAvailable {
                        // Pass the prompt template - LLMCorrector will substitute {input}
                        let transformed = try await llmCorrector.correct(text, prompt: activePrompt.promptText)
                        print("FoxSay: [PIPELINE] LLM output: \"\(transformed)\"")
                        text = transformed
                        os_log(.info, log: pipelineLog, "After AI transform: %{public}@", text)
                    } else {
                        os_log(.info, log: pipelineLog, "AI model not loaded, skipping transform")
                    }
                } catch {
                    os_log(.error, log: pipelineLog, "AI transform error: %{public}@", String(describing: error))
                    print("FoxSay: [PIPELINE] LLM error: \(error)")
                }
            } else {
                os_log(.info, log: pipelineLog, "AI model not ready, skipping transform")
                print("FoxSay: [PIPELINE] AI model not ready, skipping transform")
            }
        } else {
            print("FoxSay: [PIPELINE] No active prompt, skipping AI transform")
        }

        // Step 5: Post-processing cleanup
        text = postProcess(text)

        os_log(.info, log: pipelineLog, "<<< OUTPUT: %{public}@", text)

        // Return corrected result if text changed
        if text != result.text {
            return result.withCorrection(text)
        }

        return result
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
