import SwiftUI

/// Light, line-based syntax highlighting for `.py`/`.sh` — comments, string
/// literals, and a small keyword set, coloured with the same desaturated
/// Theme hues everything else already uses at reduced opacity, not a
/// dedicated rainbow scheme. No parser, no dependency: same "good enough"
/// spirit as `MarkdownBody`'s own hand-rolled renderer.
enum CodeHighlighter {
    private static let pyKeywords: Set<String> = [
        "def", "class", "import", "from", "return", "if", "elif", "else", "for", "while",
        "try", "except", "finally", "with", "as", "pass", "break", "continue", "raise",
        "yield", "async", "await", "lambda", "in", "is", "not", "and", "or",
        "None", "True", "False", "self",
    ]
    private static let shKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "do", "done", "while", "until",
        "case", "esac", "function", "local", "export", "return", "echo", "set", "in",
    ]

    static func line(_ text: String, ext: String) -> Text {
        let keywords = ext == "py" ? pyKeywords : shKeywords

        // Split into (code, comment) at the first '#' outside a string —
        // good enough for real source; doesn't need to handle every edge case.
        var inString: Character?
        var commentStart: String.Index?
        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            if let quote = inString {
                if ch == quote { inString = nil }
            } else if ch == "\"" || ch == "'" {
                inString = ch
            } else if ch == "#" {
                commentStart = idx
                break
            }
            idx = text.index(after: idx)
        }
        let codePart = commentStart.map { String(text[text.startIndex..<$0]) } ?? text
        let commentPart = commentStart.map { String(text[$0...]) } ?? ""

        var result = highlightCode(codePart, keywords: keywords)
        if !commentPart.isEmpty {
            result = result + Text(commentPart).foregroundColor(Theme.cContext.opacity(0.7))
        }
        return result
    }

    private static func highlightCode(_ code: String, keywords: Set<String>) -> Text {
        var result = Text("")
        var word = ""
        var inString: Character?
        var stringBuf = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            result = result + (keywords.contains(word)
                ? Text(word).foregroundColor(Theme.cVault.opacity(0.9))
                : Text(word).foregroundColor(Theme.inkDim))
            word = ""
        }

        for ch in code {
            if let quote = inString {
                stringBuf.append(ch)
                if ch == quote {
                    result = result + Text(stringBuf).foregroundColor(Theme.cOpencode.opacity(0.9))
                    stringBuf = ""
                    inString = nil
                }
                continue
            }
            if ch == "\"" || ch == "'" {
                flushWord()
                inString = ch
                stringBuf = String(ch)
            } else if ch.isLetter || ch == "_" || (ch.isNumber && !word.isEmpty) {
                word.append(ch)
            } else {
                flushWord()
                result = result + Text(String(ch)).foregroundColor(Theme.inkDim)
            }
        }
        flushWord()
        if !stringBuf.isEmpty { result = result + Text(stringBuf).foregroundColor(Theme.cOpencode.opacity(0.9)) }
        return result
    }
}
