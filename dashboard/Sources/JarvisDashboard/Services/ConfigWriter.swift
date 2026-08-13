import Foundation

/// Writes a single tunable constant back into jarvis_ear.py — the other half
/// of isair/jarvis's "metadata-driven, writable Settings" principle, adapted
/// to a source file instead of a config.json. Only the value token changes;
/// everything else on the line (the trailing `# comment`, if any) is left
/// untouched, and every other line in the file is never touched at all.
enum ConfigWriter {
    enum WriteError: Error { case keyNotFound, ioError }

    private static var earPath: String { "\(JarvisPaths.jarvisVoiceDir)/jarvis_ear.py" }

    /// Matches from start-of-line through the value, stopping before any
    /// trailing "# comment" or the newline — so replacing the matched range
    /// with "KEY = newValue" preserves the comment for free.
    static func write(key: String, value: String) throws {
        guard let text = try? String(contentsOfFile: earPath, encoding: .utf8) else {
            throw WriteError.ioError
        }
        let pattern = "^\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*[^#\\r\\n]*"
        let regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let full = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: full),
              let range = Range(match.range, in: text) else {
            throw WriteError.keyNotFound
        }
        // The match's greedy [^#\r\n]* swallows the whitespace column that
        // precedes an inline comment, so a naive replace glues "# comment"
        // straight onto the new value. Put back a single separating space
        // whenever a comment follows.
        let followedByComment = range.upperBound < text.endIndex && text[range.upperBound] == "#"
        var updated = text
        updated.replaceSubrange(range, with: "\(key) = \(value)\(followedByComment ? " " : "")")
        do {
            try updated.write(toFile: earPath, atomically: true, encoding: .utf8)
        } catch {
            throw WriteError.ioError
        }
    }

    /// Restarts the launchd-managed ear daemon so edited constants take
    /// effect. Never called automatically after write(save) — Settings only
    /// offers this as a separate, explicit button, matching isair's own
    /// confirm-before-restart flow.
    @discardableResult
    static func restartDaemon() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["kickstart", "-k", "gui/\(getuid())/com.jarvis.ear"]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
