import Foundation

/// Fast regex-based corrections for developer terminology
public struct RuleBasedCorrector: Sendable {

    /// How a replacement treats the whitespace around the spoken word.
    ///
    /// Speech engines put a space on both sides of every dictated word, so a
    /// naive replacement of "comma" leaves "hello , there". Each punctuation
    /// mark declares which side it attaches to instead.
    public enum Spacing: Sendable {
        /// Leave surrounding whitespace untouched.
        case asSpoken
        /// Absorb whitespace before the word: `, . ? ! : ; ) ]` and closing quotes.
        case attachLeft
        /// Absorb whitespace after the word: `( [` and opening quotes.
        case attachRight
        /// Absorb whitespace on both sides: hyphens and line breaks.
        case attachBoth
        /// Alternate: the first occurrence opens (attaches right), the next
        /// closes (attaches left), and so on. For a bare "quote", which people
        /// use for both ends of a quotation.
        case alternating
        /// Keep a space on both sides: dashes used as prose punctuation.
        case detached
    }

    /// Sentence marks a spoken mark can stand in for.
    private static let sentenceMarks: Set<String> = [",", ".", "?", "!", ":", ";", "..."]

    /// Correction rule definition
    public struct Rule: Sendable {
        let pattern: String
        let replacement: String
        let isRegex: Bool
        let caseSensitive: Bool
        let spacing: Spacing
        /// The closing form for an `.alternating` rule whose two ends differ.
        /// A quote opens and closes with the same character; a paren does not.
        let closing: String?
        /// Which pair this form belongs to, e.g. "paren".
        ///
        /// Every form of a pair shares one depth counter, so an `.alternating`
        /// bare word knows whether the pair is currently open — including when
        /// it was opened by an explicit "open parentheses" instead.
        let family: String?

        public init(
            pattern: String,
            replacement: String,
            isRegex: Bool = false,
            caseSensitive: Bool = false,
            spacing: Spacing = .asSpoken,
            closing: String? = nil,
            family: String? = nil
        ) {
            self.pattern = pattern
            self.replacement = replacement
            self.isRegex = isRegex
            self.caseSensitive = caseSensitive
            self.spacing = spacing
            self.closing = closing
            self.family = family
        }

        /// Whether this mark may swallow any engine punctuation beside it.
        ///
        /// True for sentence marks, which occupy the same slot as whatever the
        /// engine guessed — dictating "exclamation point" after a question the
        /// engine already ended with "?" should give one "!", not "?!". False
        /// for brackets, quotes and dashes, which sit alongside sentence marks
        /// rather than replacing them: "is that right question mark close paren"
        /// keeps its "?". Those still swallow commas, which are pause artifacts.
        var absorbsSentenceMarks: Bool {
            RuleBasedCorrector.sentenceMarks.contains(replacement)
        }
    }

    /// Builds a match for one spoken form and its variants.
    ///
    /// The space between words of a multi-word form is deliberately loose: the
    /// engine renders a pause mid-phrase as its own comma, so "dash dash" can
    /// arrive as "dash, dash" and "open parentheses" as "open, parentheses".
    private static func spoken(_ forms: String...) -> String {
        let alternatives = forms
            .map { $0.replacingOccurrences(of: " ", with: "[\\s,]+") }
            .joined(separator: "|")
        return "\\b(?:\(alternatives))\\b"
    }

    /// Words for a parenthesis, including what the speech models actually hear.
    ///
    /// "paren" and "parenthesis" are rare enough that both engines push them
    /// onto common names: "open paren" comes back as "Perrin", "open
    /// parenthesis" as "Princess", "close parenthesis" as "Clothes Princess".
    /// Matching the homophones is safe because they only count directly after
    /// an opener or closer, which is not a phrase that occurs in real prose.
    private static let parenWords = ["paren", "parens", "parenthesis", "parentheses",
                                     "perrin", "princess", "princes"]
    private static let parenOpeners = ["open", "opening", "left"]
    /// "open parentheses" is frequently heard as "a parentheses". Safe to match
    /// only in that exact pairing: a singular article in front of a plural noun
    /// is not something that occurs in real prose, whereas "a parenthesis" is,
    /// and treating a bare "a" as an opener eats the article.
    private static let misheardParenOpener = "a parentheses"
    /// "clothes" is what "close" becomes in front of these words.
    private static let parenClosers = ["close", "closed", "closing", "clothes", "right"]

    /// Joins whole patterns into one alternation.
    private static func anyOf(_ patterns: String...) -> String {
        "(?:" + patterns.joined(separator: "|") + ")"
    }

    /// Builds `opener word` / `closer word` alternatives for a bracket pair.
    private static func bracketForms(_ prefixes: [String], _ words: [String]) -> String {
        var forms: [String] = []
        for prefix in prefixes {
            for word in words {
                forms.append("\(prefix)[\\s,]+\(word)")
            }
        }
        return "\\b(?:" + forms.joined(separator: "|") + ")\\b"
    }

    /// Spoken punctuation rules, used when "Spoken Punctuation" is enabled.
    ///
    /// Deliberately narrower than `defaultRules`: only marks a person would
    /// actually dictate in prose, no developer symbols or language names. Order
    /// matters — a form must come before any shorter form it contains, so
    /// "end quote" is consumed before `quote` and "em dash" before `dash`.
    public static let punctuationRules: [Rule] = [
        // Quotes — multi-word forms first
        Rule(pattern: Self.spoken("open quote", "open quotes", "begin quote", "start quote"),
             replacement: "\u{22}", isRegex: true, spacing: .attachRight, family: "quote"),
        Rule(pattern: Self.spoken("close quote", "close quotes", "end quote", "end quotes"),
             replacement: "\u{22}", isRegex: true, spacing: .attachLeft, family: "quote"),
        Rule(pattern: Self.spoken("unquote"), replacement: "\u{22}", isRegex: true, spacing: .attachLeft, family: "quote"),
        Rule(pattern: Self.spoken("quote"), replacement: "\u{22}", isRegex: true, spacing: .alternating, family: "quote"),
        Rule(pattern: Self.spoken("apostrophe"), replacement: "'", isRegex: true, spacing: .attachLeft),

        // Sentence punctuation
        Rule(pattern: Self.spoken("comma"), replacement: ",", isRegex: true, spacing: .attachLeft),
        Rule(pattern: Self.spoken("question mark"), replacement: "?", isRegex: true, spacing: .attachLeft),
        Rule(pattern: Self.spoken("exclamation mark", "exclamation point"),
             replacement: "!", isRegex: true, spacing: .attachLeft),
        Rule(pattern: Self.spoken("full stop", "period"), replacement: ".", isRegex: true, spacing: .attachLeft),
        Rule(pattern: Self.spoken("semicolon", "semi colon"), replacement: ";", isRegex: true, spacing: .attachLeft),
        Rule(pattern: Self.spoken("colon"), replacement: ":", isRegex: true, spacing: .attachLeft),
        Rule(pattern: Self.spoken("ellipsis", "dot dot dot"), replacement: "...", isRegex: true, spacing: .attachLeft),

        // Brackets — singular and plural, since people say both
        Rule(pattern: Self.anyOf(Self.bracketForms(Self.parenOpeners, Self.parenWords),
                                 Self.spoken(Self.misheardParenOpener)),
             replacement: "(", isRegex: true, spacing: .attachRight, family: "paren"),
        Rule(pattern: Self.bracketForms(Self.parenClosers, Self.parenWords),
             replacement: ")", isRegex: true, spacing: .attachLeft, family: "paren"),
        Rule(pattern: Self.spoken("open bracket", "open brackets", "open square bracket",
                                  "left bracket", "left brackets", "left square bracket"),
             replacement: "[", isRegex: true, spacing: .attachRight, family: "bracket"),
        Rule(pattern: Self.spoken("close bracket", "close brackets", "close square bracket",
                                  "right bracket", "right brackets", "right square bracket"),
             replacement: "]", isRegex: true, spacing: .attachLeft, family: "bracket"),
        Rule(pattern: Self.spoken("open brace", "open braces", "open curly brace", "open curly",
                                  "left brace", "left braces", "left curly brace"),
             replacement: "{", isRegex: true, spacing: .attachRight, family: "brace"),
        Rule(pattern: Self.spoken("close brace", "close braces", "close curly brace", "close curly",
                                  "right brace", "right braces", "right curly brace"),
             replacement: "}", isRegex: true, spacing: .attachLeft, family: "brace"),

        // Bare bracket words, for when the engine drops the opener entirely.
        // These come last so a surviving "close parentheses" is claimed as a
        // closer above, and alternate for the same reason a bare "quote" does.
        Rule(pattern: Self.spoken("parentheses", "parenthesis", "parens", "paren"),
             replacement: "(", isRegex: true, spacing: .alternating, closing: ")", family: "paren"),
        Rule(pattern: Self.spoken("curly braces", "curly brace", "braces", "brace"),
             replacement: "{", isRegex: true, spacing: .alternating, closing: "}", family: "brace"),
        Rule(pattern: Self.spoken("square brackets", "square bracket", "brackets", "bracket"),
             replacement: "[", isRegex: true, spacing: .alternating, closing: "]", family: "bracket"),

        // Dashes — longest forms first, so "em dash" is not eaten by "dash"
        Rule(pattern: Self.spoken("em dash", "long dash"), replacement: "\u{2014}", isRegex: true, spacing: .detached),
        // An en dash joins a range ("3–7"), so it stays tight like a hyphen
        Rule(pattern: Self.spoken("en dash"), replacement: "\u{2013}", isRegex: true, spacing: .attachBoth),
        Rule(pattern: Self.spoken("dash dash", "double dash"), replacement: "\u{2014}", isRegex: true, spacing: .detached),
        Rule(pattern: Self.spoken("hyphen"), replacement: "-", isRegex: true, spacing: .attachBoth),
        Rule(pattern: Self.spoken("dash"), replacement: "-", isRegex: true, spacing: .detached),

        // Breaks
        Rule(pattern: Self.spoken("new paragraph"), replacement: "\n\n", isRegex: true, spacing: .attachBoth),
        Rule(pattern: Self.spoken("new line", "line break"), replacement: "\n", isRegex: true, spacing: .attachBoth),
    ]

    /// Default correction rules for developer context
    public static let defaultRules: [Rule] = [
        // Symbol corrections - spoken to symbol
        Rule(pattern: "\\bdash\\b", replacement: "-", isRegex: true),
        Rule(pattern: "\\bdot\\b", replacement: ".", isRegex: true),
        Rule(pattern: "\\bunderscore\\b", replacement: "_", isRegex: true),
        Rule(pattern: "\\bslash\\b", replacement: "/", isRegex: true),
        Rule(pattern: "\\bback ?slash\\b", replacement: "\\", isRegex: true),
        Rule(pattern: "\\bequals\\b", replacement: "=", isRegex: true),
        Rule(pattern: "\\bplus\\b", replacement: "+", isRegex: true),
        Rule(pattern: "\\basterisk\\b", replacement: "*", isRegex: true),
        Rule(pattern: "\\bstar\\b", replacement: "*", isRegex: true),
        Rule(pattern: "\\bat sign\\b", replacement: "@", isRegex: true),
        Rule(pattern: "\\bhash\\b", replacement: "#", isRegex: true),
        Rule(pattern: "\\bpound\\b", replacement: "#", isRegex: true),
        Rule(pattern: "\\bdollar( sign)?\\b", replacement: "$", isRegex: true),
        Rule(pattern: "\\bpercent\\b", replacement: "%", isRegex: true),
        Rule(pattern: "\\bcaret\\b", replacement: "^", isRegex: true),
        Rule(pattern: "\\bampersand\\b", replacement: "&", isRegex: true),
        Rule(pattern: "\\bpipe\\b", replacement: "|", isRegex: true),
        Rule(pattern: "\\btilde\\b", replacement: "~", isRegex: true),
        Rule(pattern: "\\bbacktick\\b", replacement: "`", isRegex: true),
        Rule(pattern: "\\bcolon\\b", replacement: ":", isRegex: true),
        Rule(pattern: "\\bsemicolon\\b", replacement: ";", isRegex: true),
        Rule(pattern: "\\bcomma\\b", replacement: ",", isRegex: true),

        // Bracket corrections
        Rule(pattern: "\\bopen paren\\b", replacement: "(", isRegex: true),
        Rule(pattern: "\\bclose paren\\b", replacement: ")", isRegex: true),
        Rule(pattern: "\\bopen bracket\\b", replacement: "[", isRegex: true),
        Rule(pattern: "\\bclose bracket\\b", replacement: "]", isRegex: true),
        Rule(pattern: "\\bopen brace\\b", replacement: "{", isRegex: true),
        Rule(pattern: "\\bclose brace\\b", replacement: "}", isRegex: true),
        Rule(pattern: "\\bopen curly\\b", replacement: "{", isRegex: true),
        Rule(pattern: "\\bclose curly\\b", replacement: "}", isRegex: true),
        Rule(pattern: "\\bless than\\b", replacement: "<", isRegex: true),
        Rule(pattern: "\\bgreater than\\b", replacement: ">", isRegex: true),

        // Common command patterns
        Rule(pattern: "\\bdash dash\\b", replacement: "--", isRegex: true),
        Rule(pattern: "\\bdouble dash\\b", replacement: "--", isRegex: true),

        // Markdown headers (must come before single hash replacement)
        Rule(pattern: "\\bhash hash hash hash hash hash\\b", replacement: "######", isRegex: true),
        Rule(pattern: "\\bhash hash hash hash hash\\b", replacement: "#####", isRegex: true),
        Rule(pattern: "\\bhash hash hash hash\\b", replacement: "####", isRegex: true),
        Rule(pattern: "\\bhash hash hash\\b", replacement: "###", isRegex: true),
        Rule(pattern: "\\bhash hash\\b", replacement: "##", isRegex: true),

        // Common Git commands
        Rule(pattern: "\\bgit status\\b", replacement: "git status", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit add\\b", replacement: "git add", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit commit\\b", replacement: "git commit", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit push\\b", replacement: "git push", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit pull\\b", replacement: "git pull", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit checkout\\b", replacement: "git checkout", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit branch\\b", replacement: "git branch", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit merge\\b", replacement: "git merge", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit rebase\\b", replacement: "git rebase", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit diff\\b", replacement: "git diff", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit log\\b", replacement: "git log", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bgit stash\\b", replacement: "git stash", isRegex: true, caseSensitive: true),

        // Common developer terms
        Rule(pattern: "\\bN P M\\b", replacement: "npm", isRegex: true),
        Rule(pattern: "\\bAPI\\b", replacement: "API", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bJSON\\b", replacement: "JSON", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bHTML\\b", replacement: "HTML", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bCSS\\b", replacement: "CSS", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bURL\\b", replacement: "URL", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bHTTP\\b", replacement: "HTTP", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bHTTPS\\b", replacement: "HTTPS", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bSQL\\b", replacement: "SQL", isRegex: true, caseSensitive: true),
        Rule(pattern: "\\bRESTful\\b", replacement: "RESTful", isRegex: true, caseSensitive: true),

        // Programming language names
        Rule(pattern: "\\bjavascript\\b", replacement: "JavaScript", isRegex: true),
        Rule(pattern: "\\btypescript\\b", replacement: "TypeScript", isRegex: true),
        Rule(pattern: "\\bpython\\b", replacement: "Python", isRegex: true),
        Rule(pattern: "\\bswift\\b", replacement: "Swift", isRegex: true),
        Rule(pattern: "\\brust\\b", replacement: "Rust", isRegex: true),
        Rule(pattern: "\\bkotlin\\b", replacement: "Kotlin", isRegex: true),

        // Common file extensions
        Rule(pattern: "\\bdot js\\b", replacement: ".js", isRegex: true),
        Rule(pattern: "\\bdot ts\\b", replacement: ".ts", isRegex: true),
        Rule(pattern: "\\bdot py\\b", replacement: ".py", isRegex: true),
        Rule(pattern: "\\bdot swift\\b", replacement: ".swift", isRegex: true),
        Rule(pattern: "\\bdot rs\\b", replacement: ".rs", isRegex: true),
        Rule(pattern: "\\bdot json\\b", replacement: ".json", isRegex: true),
        Rule(pattern: "\\bdot yaml\\b", replacement: ".yaml", isRegex: true),
        Rule(pattern: "\\bdot yml\\b", replacement: ".yml", isRegex: true),
        Rule(pattern: "\\bdot md\\b", replacement: ".md", isRegex: true),

        // Operators
        Rule(pattern: "\\bequals equals\\b", replacement: "==", isRegex: true),
        Rule(pattern: "\\btriple equals\\b", replacement: "===", isRegex: true),
        Rule(pattern: "\\bnot equals\\b", replacement: "!=", isRegex: true),
        Rule(pattern: "\\bplus equals\\b", replacement: "+=", isRegex: true),
        Rule(pattern: "\\bminus equals\\b", replacement: "-=", isRegex: true),
        Rule(pattern: "\\barrow\\b", replacement: "->", isRegex: true),
        Rule(pattern: "\\bfat arrow\\b", replacement: "=>", isRegex: true),
        Rule(pattern: "\\bdouble arrow\\b", replacement: "=>", isRegex: true),

        // Special keywords
        Rule(pattern: "\\bnew line\\b", replacement: "\n", isRegex: true),
        Rule(pattern: "\\btab\\b", replacement: "\t", isRegex: true),
        Rule(pattern: "\\bspace\\b", replacement: " ", isRegex: true),
    ]

    private let rules: [Rule]

    public init(rules: [Rule] = RuleBasedCorrector.defaultRules) {
        self.rules = rules
    }

    /// Apply all correction rules to the text
    public func correct(_ text: String) -> String {
        var result = text

        for rule in rules {
            if rule.isRegex {
                do {
                    let options: NSRegularExpression.Options = rule.caseSensitive ? [] : .caseInsensitive
                    let regex = try NSRegularExpression(pattern: rule.pattern, options: options)
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(
                        in: result,
                        options: [],
                        range: range,
                        withTemplate: rule.replacement
                    )
                } catch {
                    // Skip invalid regex patterns
                    continue
                }
            } else {
                // Simple string replacement
                if rule.caseSensitive {
                    result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
                } else {
                    result = result.replacingOccurrences(
                        of: rule.pattern,
                        with: rule.replacement,
                        options: .caseInsensitive
                    )
                }
            }
        }

        return result
    }

    // MARK: - Spoken Punctuation

    /// Punctuation the speech engine inserts on its own.
    ///
    /// Parakeet and Whisper both punctuate from prosody, so dictating "comma"
    /// gets you the engine's comma for the pause *and* the literal word:
    /// "Testing comma period" comes back as "Testing, comma, period." A spoken
    /// mark is an explicit instruction, so it overrides whatever the engine put
    /// next to it rather than stacking on top of it.
    private static let enginePunctuation = "[,.;:!?]"

    /// Private-use delimiters for the placeholder a matched rule leaves behind.
    /// Deliberately free of letters and punctuation, so no later rule can match
    /// inside a placeholder and no absorb pass can eat a mark already inserted.
    private static let tokenOpen = "\u{E000}"
    private static let tokenClose = "\u{E001}"

    /// Convert spoken punctuation words into punctuation marks.
    ///
    /// Two passes. The first swaps each spoken word for a placeholder, swallowing
    /// the whitespace and engine punctuation on either side of it. The second
    /// expands the placeholders, which is where spacing gets decided — by then
    /// nothing else is competing for the space around the mark.
    public func correctSpokenPunctuation(_ text: String) -> String {
        var result = text

        let absorbAll = "(?:[ \\t]*\(Self.enginePunctuation))*[ \\t]*"
        let absorbCommas = "(?:[ \\t]*,)*[ \\t]*"

        for (index, rule) in rules.enumerated() {
            guard rule.isRegex else { continue }
            let absorb = rule.absorbsSentenceMarks ? absorbAll : absorbCommas
            let pattern = absorb + rule.pattern + absorb
            let options: NSRegularExpression.Options = rule.caseSensitive ? [] : .caseInsensitive
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }

            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "\(Self.tokenOpen)\(index)\(Self.tokenClose)"
            )
        }

        return expandTokens(result)
    }

    /// Characters that must not be followed by an inserted space.
    private static let openers: Set<Character> = ["(", "[", "{", "\u{22}"]
    /// Characters that must not be preceded by an inserted space.
    private static let closers: Set<Character> = [",", ".", ";", ":", "!", "?", ")", "]", "}"]

    private func expandTokens(_ text: String) -> String {
        let pattern = "\(Self.tokenOpen)(\\d+)\(Self.tokenClose)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = 0
        // Set after a mark that hugs the word on its left, so the next word gets
        // its space back — but only if a word actually follows.
        var pendingSpace = false
        // Parity for `.alternating` rules, keyed by rule index. One utterance
        // is one call, so a quotation left open does not leak into the next.
        // How many of each pair are currently open. Every form of a pair feeds
        // the same counter, so "open parentheses … parentheses" closes correctly
        // and so does a bare "parentheses … close parentheses".
        var openDepth: [String: Int] = [:]
        // Set after an opening bracket or quote. Nothing legitimately follows one
        // with a comma or a full stop, so whatever the engine put there is the
        // artifact of the pause before the word it swallowed.
        var stripLeadingPunctuation = false

        func appendLiteral(_ rawLiteral: String) {
            var literal = Substring(rawLiteral)
            if stripLeadingPunctuation {
                literal = literal.drop { $0 == " " || $0 == "\t" || Self.closers.contains($0) }
                stripLeadingPunctuation = false
            }
            guard !literal.isEmpty else { return }
            if pendingSpace, let first = literal.first,
               !first.isWhitespace, !Self.closers.contains(first) {
                output += " "
            }
            output += literal
            pendingSpace = false
        }

        for match in matches {
            let literalRange = NSRange(location: cursor, length: match.range.location - cursor)
            appendLiteral(ns.substring(with: literalRange))

            guard let index = Int(ns.substring(with: match.range(at: 1))), rules.indices.contains(index) else {
                cursor = match.range.location + match.range.length
                continue
            }
            let rule = rules[index]

            switch rule.spacing {
            case .attachLeft:
                output += rule.replacement
                pendingSpace = true
                if let family = rule.family {
                    openDepth[family] = max(0, (openDepth[family] ?? 0) - 1)
                }
            case .attachRight:
                if let last = output.last, !last.isWhitespace, !Self.openers.contains(last) {
                    output += " "
                }
                output += rule.replacement
                pendingSpace = false
                stripLeadingPunctuation = true
                if let family = rule.family {
                    openDepth[family] = (openDepth[family] ?? 0) + 1
                }
            case .attachBoth, .asSpoken:
                output += rule.replacement
                pendingSpace = false
            case .alternating:
                let family = rule.family ?? "\(index)"
                let isOpening = (openDepth[family] ?? 0) == 0
                openDepth[family] = (openDepth[family] ?? 0) + (isOpening ? 1 : -1)
                if isOpening {
                    if let last = output.last, !last.isWhitespace, !Self.openers.contains(last) {
                        output += " "
                    }
                    output += rule.replacement
                    pendingSpace = false
                    stripLeadingPunctuation = true
                } else {
                    output += rule.closing ?? rule.replacement
                    pendingSpace = true
                }
            case .detached:
                if let last = output.last, !last.isWhitespace {
                    output += " "
                }
                output += rule.replacement
                pendingSpace = true
            }

            cursor = match.range.location + match.range.length
        }

        appendLiteral(ns.substring(from: cursor))
        return output
    }

    /// Create a corrector with additional custom rules
    public func adding(rules additionalRules: [Rule]) -> RuleBasedCorrector {
        RuleBasedCorrector(rules: self.rules + additionalRules)
    }
}
