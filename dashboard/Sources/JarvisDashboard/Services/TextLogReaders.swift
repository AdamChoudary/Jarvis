import Foundation

enum TextLogReaders {
    static func tailLines(_ path: String, count: Int) -> [String] {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(count).map(String.init)
    }

    private static let tsRegex = try! NSRegularExpression(pattern: #"^\[(\d{2}):(\d{2}):(\d{2})\] (.*)$"#)

    private static func hmsToSecs(_ line: String) -> (Int, String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = tsRegex.firstMatch(in: line, range: range) else { return nil }
        func group(_ i: Int) -> String {
            Range(m.range(at: i), in: line).map { String(line[$0]) } ?? ""
        }
        guard let h = Int(group(1)), let mi = Int(group(2)), let s = Int(group(3)) else { return nil }
        return (h * 3600 + mi * 60 + s, group(4))
    }

    /// Mirrors dashboard_server.py's _log_stats(): exchange count + brain
    /// latency, both derived from adjacent timestamped lines already in
    /// ear.log rather than new daemon instrumentation.
    static func earLogStats() -> LogStats {
        // The boot marker used to get searched for within only the last 6000
        // lines — if it fell outside that window (ear.log is small, well
        // under 1MB, so reading it whole costs nothing), `bootIdx` silently
        // defaulted to 0 and stats spanned however many prior boots happened
        // to also be in that window.
        let lines = tailLines(JarvisPaths.earLog, count: .max)
        var bootIdx = 0
        for (i, line) in lines.enumerated() where line.contains("Jarvis ear v7 online") {
            bootIdx = i
        }
        let sinceBoot = lines[bootIdx...]

        var stats = LogStats()
        var pendingStart: Int?
        for line in sinceBoot {
            guard let (secs, rest) = hmsToSecs(line) else { continue }
            if rest.hasPrefix("Heard") || rest.hasPrefix("Follow-up") {
                stats.exchangesSinceBoot += 1
                pendingStart = secs
            } else if (rest.hasPrefix("Reply") || rest.hasPrefix("Guest reply")), let start = pendingStart {
                let delta = secs - start
                if delta >= 0 && delta <= 120 { stats.latencySamplesSecs.append(Double(delta)) }
                pendingStart = nil
            }
        }
        stats.recentLines = Array(lines.suffix(60).reversed())

        let conversational = ["Heard (", "Reply:", "Guest reply:", "Mention trigger:",
                              "Wake (", "reflex:", "Barge-in captured", "BARGE-IN",
                              "Follow-up ("]
        stats.conversationLines = lines.filter { line in
            conversational.contains { line.contains($0) }
        }.suffix(40).reversed()

        return stats
    }

    static func ramTrend() -> [RamSample] {
        tailLines(JarvisPaths.ramLog, count: 300).compactMap {
            guard let data = $0.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(RamSample.self, from: data)
        }
    }

    /// Every dispatched turn the daemon has logged (Wave 1 instrumentation),
    /// aggregated per lane so the vitals panel can show measured speed
    /// rather than claims. Reflex should sit near zero; that gap IS the value.
    static func laneStats() -> [LaneStat] {
        var byLane: [String: [Double]] = [:]
        var tokensByLane: [String: Int] = [:]
        for line in tailLines(JarvisPaths.ramLog, count: 2000) {
            guard let data = line.data(using: .utf8),
                  let turn = try? JSONDecoder().decode(TurnEvent.self, from: data),
                  line.contains("\"event\": \"turn\""),
                  turn.source != "test" else { continue }
            byLane[turn.lane, default: []].append(turn.secs)
            if let total = turn.tokens?.total {
                tokensByLane[turn.lane, default: 0] += total
            }
        }
        let order = ["reflex", "fast", "agent"]
        return byLane.map { lane, secs in
            LaneStat(lane: lane, count: secs.count,
                     avgSecs: secs.reduce(0, +) / Double(max(secs.count, 1)),
                     maxSecs: secs.max() ?? 0,
                     totalTokens: tokensByLane[lane] ?? 0)
        }.sorted { (order.firstIndex(of: $0.lane) ?? 99) < (order.firstIndex(of: $1.lane) ?? 99) }
    }

    /// Deliberate self-restarts (RAM ceiling, nightly housekeeping, dead audio
    /// stream). Zero across days is the daemon's health headline.
    static func restartEvents() -> [RamSample] {
        tailLines(JarvisPaths.ramLog, count: 2000).compactMap { line in
            guard line.contains("\"event\": \"self_restart\""),
                  let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(RamSample.self, from: data)
        }
    }
}
