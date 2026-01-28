import Foundation

/// Fast regex-based corrections for developer terminology
public struct RuleBasedCorrector: Sendable {

    /// Correction rule definition
    public struct Rule: Sendable {
        let pattern: String
        let replacement: String
        let isRegex: Bool
        let caseSensitive: Bool

        public init(pattern: String, replacement: String, isRegex: Bool = false, caseSensitive: Bool = false) {
            self.pattern = pattern
            self.replacement = replacement
            self.isRegex = isRegex
            self.caseSensitive = caseSensitive
        }
    }

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

    /// Create a corrector with additional custom rules
    public func adding(rules additionalRules: [Rule]) -> RuleBasedCorrector {
        RuleBasedCorrector(rules: self.rules + additionalRules)
    }
}
