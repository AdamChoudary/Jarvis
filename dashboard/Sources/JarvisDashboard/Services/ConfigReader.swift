import Foundation

struct ConfigEntry: Identifiable {
    var id: String { key }
    let key: String
    let value: String
    let note: String
    var meta: FieldMeta? = nil
}

/// isair/jarvis's metadata-driven-settings principle, adapted to our actual
/// config surface: there is no single config.json here, just top-level
/// tunable constants in jarvis_ear.py. A FieldMeta entry is what makes a
/// constant editable instead of read-only-display — bounds double as both
/// the widget's range and the write-back validation.
struct FieldMeta {
    let min: Double
    let max: Double
    let step: Double
    let isInt: Bool
}

enum ConfigReader {
    /// Constants left out on purpose, same spirit as isair's "Fields NOT
    /// Exposed in UI": RATE/CHUNK are audio-format constants load-bearing
    /// elsewhere in the resampling math; VOICE_EDGE/VOICE_KOKORO are engine
    /// names, not tunables; MIN_UPTIME_FOR_NIGHTLY is a computed expression
    /// ("20 * 3600") rather than a plain literal, so a numeric write-back
    /// would silently destroy its readable form.
    static let editableFields: [String: FieldMeta] = [
        "WAKE_THRESHOLD": FieldMeta(min: 0.0, max: 1.0, step: 0.05, isInt: false),
        "WAKE_SOFT": FieldMeta(min: 0.0, max: 1.0, step: 0.05, isInt: false),
        "RING_SECS": FieldMeta(min: 1, max: 10, step: 1, isInt: true),
        "FOLLOWUP_WINDOW_SECS": FieldMeta(min: 5, max: 120, step: 5, isInt: false),
        "BARGE_IN_RMS": FieldMeta(min: 500, max: 5000, step: 100, isInt: true),
        "BARGE_IN_FRAMES": FieldMeta(min: 1, max: 20, step: 1, isInt: true),
        "BARGE_IN_ARM_TIMEOUT": FieldMeta(min: 10, max: 300, step: 10, isInt: false),
        "RAM_CEILING_MB": FieldMeta(min: 1000, max: 5000, step: 100, isInt: true),
        "RAM_STREAK_NEEDED": FieldMeta(min: 1, max: 30, step: 1, isInt: true),
        "NIGHTLY_RESTART_HOUR": FieldMeta(min: 0, max: 23, step: 1, isInt: true),
        "IDLE_DISTILL_SECS": FieldMeta(min: 60, max: 3600, step: 60, isInt: true),
    ]

    static func envEntries() -> [ConfigEntry] {
        guard let data = FileManager.default.contents(atPath: JarvisPaths.envFile),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [ConfigEntry] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eq])
            let rawValue = String(trimmed[trimmed.index(after: eq)...])
            let isSecret = JarvisPaths.secretEnvKeyMarkers.contains { key.uppercased().contains($0) }
            out.append(ConfigEntry(key: key, value: isSecret ? "•••• (set)" : rawValue, note: isSecret ? "redacted" : ""))
        }
        return out.sorted { $0.key < $1.key }
    }

    /// Tunable constants pulled straight from jarvis_ear.py's own source, so
    /// this view can never drift from what the daemon is actually running —
    /// no separate config schema to keep in sync by hand.
    static let trackedConstants: Set<String> = [
        "WAKE_THRESHOLD", "WAKE_SOFT", "RING_SECS", "SILENCE_SECS", "MIN_SPEECH_SECS",
        "MAX_RECORD_SECS", "FOLLOWUP_WINDOW_SECS", "BARGE_IN_RMS", "BARGE_IN_FRAMES",
        "BARGE_IN_ARM_TIMEOUT", "RAM_CEILING_MB", "RAM_STREAK_NEEDED",
        "NIGHTLY_RESTART_HOUR", "MIN_UPTIME_FOR_NIGHTLY", "IDLE_DISTILL_SECS",
        "VOICE_EDGE", "VOICE_KOKORO", "RATE", "CHUNK",
    ]

    static func daemonConstants() -> [ConfigEntry] {
        guard let data = FileManager.default.contents(atPath: "\(JarvisPaths.jarvisVoiceDir)/jarvis_ear.py"),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: "\n")
        var out: [ConfigEntry] = []
        let pattern = try! NSRegularExpression(pattern: #"^([A-Z_][A-Z0-9_]*)\s*=\s*(.+?)(\s*#.*)?$"#)
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let m = pattern.firstMatch(in: line, range: range) else { continue }
            func group(_ i: Int) -> String? {
                guard let r = Range(m.range(at: i), in: line) else { return nil }
                return String(line[r])
            }
            guard let key = group(1), trackedConstants.contains(key) else { continue }
            let value = group(2)?.trimmingCharacters(in: .whitespaces) ?? ""
            let comment = group(3)?.trimmingCharacters(in: CharacterSet(charactersIn: " #")) ?? ""
            out.append(ConfigEntry(key: key, value: value, note: comment, meta: editableFields[key]))
        }
        return out
    }
}
