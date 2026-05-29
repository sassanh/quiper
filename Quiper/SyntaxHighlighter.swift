import Foundation
import AppKit

struct SyntaxHighlighter {
    // Monokai-inspired dark theme palette using native NSColor
    private static let pink = NSColor(red: 249/255, green: 38/255, blue: 114/255, alpha: 1)
    private static let green = NSColor(red: 166/255, green: 226/255, blue: 46/255, alpha: 1)
    private static let yellow = NSColor(red: 230/255, green: 219/255, blue: 116/255, alpha: 1)
    private static let purple = NSColor(red: 174/255, green: 129/255, blue: 255/255, alpha: 1)
    private static let cyan = NSColor(red: 102/255, green: 217/255, blue: 239/255, alpha: 1)
    private static let orange = NSColor(red: 253/255, green: 151/255, blue: 31/255, alpha: 1)
    private static let gray = NSColor(red: 117/255, green: 113/255, blue: 94/255, alpha: 1)
    private static let white = NSColor(red: 248/255, green: 248/255, blue: 242/255, alpha: 1)

    static func highlight(code: String, language: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: code)
        guard !code.isEmpty else { return attributed }

        // Default text color
        let fullRange = NSRange(location: 0, length: code.utf16.count)
        attributed.addAttribute(.foregroundColor, value: white, range: fullRange)

        switch language {
        case "javascript":
            highlightJavaScript(attributed, code: code, range: fullRange)
        case "css":
            highlightCSS(attributed, code: code, range: fullRange)
        default:
            break
        }

        return attributed
    }

    // MARK: - JavaScript

    private static func highlightJavaScript(_ attributed: NSMutableAttributedString, code: String, range: NSRange) {
        // Order matters: later rules override earlier ones.
        // Apply broadest first, then narrow tokens on top.

        // 1. Function calls: identifier immediately before `(`  → cyan
        applyPattern("\\b([a-zA-Z_$][a-zA-Z0-9_$]*)\\s*(?=\\()", to: attributed, in: code, range: range, color: cyan)

        // 3. Numbers (integer, float, hex, binary, octal, exponential) → purple
        applyPattern("\\b0[xX][0-9a-fA-F_]+\\b|\\b0[bB][01_]+\\b|\\b0[oO][0-7_]+\\b|\\b\\d[\\d_]*\\.?[\\d_]*(?:[eE][+-]?\\d+)?\\b", to: attributed, in: code, range: range, color: purple)

        // 4. Control-flow keywords → pink
        let controlKeywords = ["if", "else", "for", "while", "do", "switch", "case", "break", "continue", "return", "throw", "try", "catch", "finally", "default", "yield"]
        applyWordList(controlKeywords, to: attributed, in: code, range: range, color: pink)

        // 5. Declaration keywords → pink
        let declKeywords = ["const", "let", "var", "function", "class", "extends", "import", "export", "from", "async", "await", "new", "delete", "typeof", "instanceof", "in", "of", "void"]
        applyWordList(declKeywords, to: attributed, in: code, range: range, color: pink)

        // 6. Built-in constants → purple
        let builtinConstants = ["true", "false", "null", "undefined", "NaN", "Infinity"]
        applyWordList(builtinConstants, to: attributed, in: code, range: range, color: purple)

        // 7. this / super / self → orange
        applyWordList(["this", "super", "self"], to: attributed, in: code, range: range, color: orange)

        // 8. Built-in types / globals → cyan
        let builtinTypes = ["Promise", "Error", "TypeError", "RangeError", "Date", "Math", "Array", "Object", "Map", "Set", "RegExp", "JSON", "console", "document", "window", "setTimeout", "setInterval", "clearTimeout", "clearInterval", "requestAnimationFrame", "fetch", "Response", "Request", "URL", "URLSearchParams", "Number", "String", "Boolean", "Symbol", "BigInt", "WeakMap", "WeakSet", "Proxy", "Reflect"]
        applyWordList(builtinTypes, to: attributed, in: code, range: range, color: cyan)

        // 9. Operators → pink
        applyPattern("=>|===|!==|==|!=|>=|<=|&&|\\|\\||\\?\\.|\\.\\.\\.|\\.\\?|\\?\\?|[+\\-*/%]=?", to: attributed, in: code, range: range, color: pink)

        // 10. Strings (double, single, template) → yellow
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", to: attributed, in: code, range: range, color: yellow)
        applyPattern("`(?:[^`\\\\]|\\\\.)*`", to: attributed, in: code, range: range, color: yellow, options: [.dotMatchesLineSeparators])

        // 11. Comments override everything → gray
        applyPattern("//[^\\n]*|/\\*[\\s\\S]*?\\*/", to: attributed, in: code, range: range, color: gray, options: [.dotMatchesLineSeparators])
    }

    // MARK: - CSS

    private static func highlightCSS(_ attributed: NSMutableAttributedString, code: String, range: NSRange) {
        // 1. Selectors: everything outside braces that isn't a property block.
        applyPattern("[^{}]+(?=\\s*\\{)", to: attributed, in: code, range: range, color: cyan)

        // 2. Property names: word-chars (including hyphens) followed by `:` inside a declaration block.
        applyPattern("(?<=\\{|;|\\n)\\s*([a-zA-Z-]+)\\s*(?=:)", to: attributed, in: code, range: range, color: orange)

        // 3. Numeric values with optional units → purple
        applyPattern("\\b\\d+\\.?\\d*(%|px|em|rem|vh|vw|vmin|vmax|ch|ex|cm|mm|in|pt|pc|s|ms|deg|rad|turn|fr)?\\b", to: attributed, in: code, range: range, color: purple)

        // 4. Hex colors → green
        applyPattern("#[0-9a-fA-F]{3,8}\\b", to: attributed, in: code, range: range, color: green)

        // 5. CSS value keywords → purple
        let valueKeywords = ["transparent", "inherit", "initial", "unset", "none", "auto", "normal", "bold", "italic", "underline", "solid", "dashed", "dotted", "hidden", "visible", "absolute", "relative", "fixed", "sticky", "flex", "grid", "block", "inline", "inline-block", "inline-flex", "inline-grid", "center", "baseline", "stretch"]
        applyWordList(valueKeywords, to: attributed, in: code, range: range, color: purple)

        // 6. !important → pink
        applyPattern("!important\\b", to: attributed, in: code, range: range, color: pink)

        // 7. @-rules → pink
        applyPattern("@[a-zA-Z-]+", to: attributed, in: code, range: range, color: pink)

        // 8. Strings → yellow
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", to: attributed, in: code, range: range, color: yellow)

        // 9. Comments → gray
        applyPattern("/\\*[\\s\\S]*?\\*/", to: attributed, in: code, range: range, color: gray, options: [.dotMatchesLineSeparators])

        // 10. Braces and punctuation → white
        applyPattern("[{}:;]", to: attributed, in: code, range: range, color: white)
    }

    // MARK: - Helpers

    private static func applyPattern(
        _ pattern: String,
        to attributed: NSMutableAttributedString,
        in code: String,
        range: NSRange,
        color: NSColor,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        regex.enumerateMatches(in: code, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: matchRange)
        }
    }

    private static func applyWordList(
        _ words: [String],
        to attributed: NSMutableAttributedString,
        in code: String,
        range: NSRange,
        color: NSColor
    ) {
        let pattern = "\\b(\(words.joined(separator: "|")))\\b"
        applyPattern(pattern, to: attributed, in: code, range: range, color: color)
    }
}
