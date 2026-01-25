import Foundation
import os.log

private let modeLog = OSLog(subsystem: "com.voicefox", category: "MODE")

/// Voice coding modes for different languages/syntaxes
public enum VoiceMode: String, CaseIterable {
    case none
    case markdown
    case javascript
    case php
    case python
    case bash
    // Add more as needed

    /// Keywords that trigger this mode
    var triggers: [String] {
        switch self {
        case .none: return ["plain", "plain text", "clear mode", "normal"]
        case .markdown: return ["markdown", "mark down", "md", "markdown on", "mark down on", "md on", "markdown mode", "mark down mode", "md mode"]
        case .javascript: return ["javascript", "js", "typescript", "ts", "javascript on", "js on", "typescript on", "ts on"]
        case .php: return ["php", "php on", "php mode"]
        case .python: return ["python", "py", "python on", "py on", "python mode", "py mode"]
        case .bash: return ["bash", "shell", "terminal", "command", "bash on", "shell on", "terminal on", "command on"]
        }
    }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .none: return "Plain Text"
        case .markdown: return "Markdown"
        case .javascript: return "JavaScript"
        case .php: return "PHP"
        case .python: return "Python"
        case .bash: return "Bash"
        }
    }

    /// Whether this mode requires symbol conversion (spoken words → symbols)
    /// Programming modes need "slash" → "/", "dot" → ".", etc.
    /// Text modes (none, markdown) should preserve natural language
    var requiresSymbolConversion: Bool {
        switch self {
        case .none, .markdown:
            return false
        case .javascript, .php, .python, .bash:
            return true
        }
    }
}

/// Manages the current voice coding mode
@MainActor
public class VoiceModeManager: ObservableObject {
    public static let shared = VoiceModeManager()

    @Published public private(set) var currentMode: VoiceMode = .none

    private init() {}

    /// Check if text starts with a mode trigger and extract the mode + remaining text
    /// Returns (mode, remainingText) where mode is the detected mode and remainingText is without the trigger
    public func detectMode(in text: String) -> (mode: VoiceMode?, remainingText: String) {
        let lowercased = text.lowercased()
        // Strip trailing punctuation for trigger-only detection (e.g., "Markdown." -> "markdown")
        let stripped = lowercased.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))

        // Check for "[mode] off" patterns to turn off current mode
        let offPatterns = [
            "markdown off", "mark down off", "md off",
            "javascript off", "js off", "typescript off", "ts off",
            "python off", "py off",
            "bash off", "shell off", "terminal off", "command off",
            "mode off", "turn off mode", "disable mode"
        ]
        for pattern in offPatterns {
            if stripped == pattern || lowercased.hasPrefix(pattern + " ") {
                os_log(.info, log: modeLog, "Mode off trigger detected: %{public}@", pattern)
                return (VoiceMode.none, "")
            }
        }

        // Check each mode's triggers
        for mode in VoiceMode.allCases {
            for trigger in mode.triggers {
                if lowercased.hasPrefix(trigger + " ") {
                    let remaining = String(text.dropFirst(trigger.count + 1))
                    os_log(.info, log: modeLog, "Mode trigger detected: %{public}@ -> %{public}@", trigger, mode.rawValue)
                    return (mode, remaining)
                }
                // Also check for just the trigger word alone (with or without trailing punctuation)
                if lowercased == trigger || stripped == trigger {
                    os_log(.info, log: modeLog, "Mode set to: %{public}@", mode.rawValue)
                    return (mode, "")
                }
            }
        }

        return (nil, text)
    }

    /// Set the current mode
    public func setMode(_ mode: VoiceMode) {
        if currentMode != mode {
            os_log(.info, log: modeLog, "Mode changed: %{public}@ -> %{public}@", currentMode.rawValue, mode.rawValue)
            currentMode = mode
        }
    }

    /// Clear mode back to none
    public func clearMode() {
        setMode(.none)
    }

    /// Get the LLM prompt for the current mode
    public func getPromptForMode(_ mode: VoiceMode) -> String {
        switch mode {
        case .none:
            return defaultPrompt

        case .markdown:
            return markdownPrompt

        case .javascript:
            return javascriptPrompt

        case .php:
            return phpPrompt

        case .python:
            return pythonPrompt

        case .bash:
            return bashPrompt
        }
    }

    // MARK: - Mode-specific prompts

    /// Default prompt for no-mode (general spoken-to-code)
    private let defaultPrompt = """
        Convert spoken punctuation to symbols. Be minimal - output only the converted text.

        Rules: hash=#, dash=-, dot=., equals=, colon=:, semicolon=;
        open paren=(, close paren=), open bracket=[, close bracket=]
        greater than=>, less than=<, plus=+
        "dash dash"=--, "equals equals"==, "not equals"=!=, "plus equals"=+=

        Examples:
        "hash hello" -> # hello
        "const x equals 5" -> const x = 5
        "if x equals equals y" -> if x == y
        "function hello open paren close paren" -> function hello()
        "hello world" -> hello world

        Input: {input}
        Output:
        """

    private let markdownPrompt = """
        Convert spoken markdown commands to markdown syntax. Output only the markdown.

        Commands:
        h1/heading 1 = #, h2/heading 2 = ##, h3/heading 3 = ###, h4 = ####, h5 = #####, h6 = ######
        "bold on" and "bold off" toggle **bold** (preprocessed to **)
        "italic on" and "italic off" toggle *italic* (preprocessed to *)
        "code on" and "code off" toggle `inline code` (preprocessed to `)
        bullet/dash/list [text] = - text
        number/numbered [text] = 1. text
        link [text] to [url] = [text](url)
        image [alt] from [url] = ![alt](url)
        code [text] = `text` (inline code wrapped in backticks)
        code block/codeblock [lang] = ```lang (start fenced code block)
        end code/endcode = ``` (end fenced code block)
        quote/block quote [text] = > text
        hr/horizontal rule/divider = ---
        checkbox/todo [text] = - [ ] text
        checked [text] = - [x] text

        Examples:
        "h1 welcome to my site" -> # welcome to my site
        "h2 introduction" -> ## introduction
        "this is **important** text" -> this is **important** text
        "here is *emphasized* word" -> here is *emphasized* word
        "use `const x` in code" -> use `const x` in code
        "bullet first item" -> - first item
        "number step one" -> 1. step one
        "code const x equals 5" -> `const x = 5`
        "code block python" -> ```python
        "codeblock javascript" -> ```javascript
        "end code" -> ```
        "quote this is quoted" -> > this is quoted
        "block quote important note" -> > important note
        "checkbox remember this" -> - [ ] remember this
        "this is plain text" -> this is plain text

        Input: {input}
        Output:
        """

    private let javascriptPrompt = """
        Convert spoken JavaScript to code. Output only the code.

        Patterns:
        const/let/var [name] equals [value] = const/let/var name = value
        function [name] [args...] = function name(args) { }
        arrow [name] [args...] = const name = (args) => { }
        if [condition] = if (condition) { }
        else if [condition] = else if (condition) { }
        else = else { }
        for [var] in [iterable] = for (const var of iterable) { }
        for [var] from [start] to [end] = for (let var = start; var < end; var++)
        log [message] = console.log(message)
        return [value] = return value
        async function [name] = async function name() { }
        await [expression] = await expression
        import [name] from [module] = import name from 'module'
        export [thing] = export thing

        Examples:
        "const count equals 0" -> const count = 0
        "function add a b" -> function add(a, b) { }
        "arrow double x" -> const double = (x) => { }
        "if x greater than 5" -> if (x > 5) { }
        "log hello world" -> console.log("hello world")
        "return result" -> return result

        Input: {input}
        Output:
        """

    private let phpPrompt = """
        Convert spoken PHP to code. Output only the code.

        Patterns:
        function [name] [args...] = function name($args) { }
        class [name] = class name { }
        if [condition] = if (condition) { }
        else if [condition] = elseif (condition) { }
        else = else { }
        foreach [item] in [array] = foreach ($array as $item) { }
        for [var] from [start] to [end] = for ($var = start; $var < end; $var++)
        echo [text] = echo "text"
        return [value] = return value
        public function [name] = public function name() { }
        private function [name] = private function name() { }
        protected function [name] = protected function name() { }
        new [class] = new class()
        arrow = ->
        double colon = ::
        dollar [var] = $var

        Examples:
        "function hello name" -> function hello($name) { }
        "echo hello world" -> echo "hello world"
        "if count greater than 0" -> if ($count > 0) { }
        "foreach item in items" -> foreach ($items as $item) { }
        "return result" -> return $result
        "dollar this arrow name" -> $this->name
        "class name colon colon method" -> ClassName::method()

        Input: {input}
        Output:
        """

    private let pythonPrompt = """
        Convert spoken Python to code. Output only the code.

        Patterns:
        def [name] [args...] = def name(args):
        class [name] = class name:
        if [condition] = if condition:
        elif [condition] = elif condition:
        else = else:
        for [var] in [iterable] = for var in iterable:
        while [condition] = while condition:
        print [message] = print(message)
        return [value] = return value
        import [module] = import module
        from [module] import [thing] = from module import thing
        with [context] as [var] = with context as var:
        try = try:
        except [error] = except error:
        finally = finally:

        Examples:
        "def hello name" -> def hello(name):
        "print hello world" -> print("hello world")
        "if x equals 5" -> if x == 5:
        "for item in items" -> for item in items:
        "return result" -> return result
        "import os" -> import os
        "from typing import list" -> from typing import List

        Input: {input}
        Output:
        """

    private let bashPrompt = """
        Convert spoken bash/shell commands to code. Output only the command.

        Common patterns:
        cd [path] = cd path
        ls [options] [path] = ls options path
        mkdir [name] = mkdir name
        rm [file] = rm file
        cp [source] to [dest] = cp source dest
        mv [source] to [dest] = mv source dest
        cat [file] = cat file
        grep [pattern] in [file] = grep "pattern" file
        echo [text] = echo "text"
        pipe = |
        redirect to [file] = > file
        append to [file] = >> file
        and = &&
        or = ||

        Git:
        git status = git status
        git add [file] = git add file
        git commit message [msg] = git commit -m "msg"
        git push = git push
        git pull = git pull
        git checkout [branch] = git checkout branch
        git branch [name] = git branch name

        Examples:
        "cd documents" -> cd documents
        "ls all" -> ls -la
        "mkdir new folder" -> mkdir "new folder"
        "git commit message fix bug" -> git commit -m "fix bug"
        "grep error in log file" -> grep "error" log file
        "echo hello world" -> echo "hello world"

        Input: {input}
        Output:
        """
}
