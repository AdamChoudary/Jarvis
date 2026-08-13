import Foundation

struct RamSample: Codable {
    let ts: String?
    let rssMb: Double?
    let footprintMb: Double?
    let event: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case ts, event, reason
        case rssMb = "rss_mb"
        case footprintMb = "footprint_mb"
    }
}

struct CronJob: Identifiable {
    let id: String
    let name: String
    let schedule: String
    let enabled: Bool
    let lastRunAt: String?
    let lastStatus: String?
    let completed: Int?
    /// ISO8601, used to ramp the routine ring's brightness as a run approaches.
    let nextRunAt: String?
    /// Non-nil only while this job is actively executing right now.
    let fireClaim: String?
}

/// A tool call some opencode/Claude Code session has in flight right now —
/// the most concrete "work happening" signal available, since it names the
/// real tool and target rather than a generic busy indicator.
struct PendingToolCall: Identifiable {
    var id: String { "\(sessionID):\(tool):\(summary)" }
    let sessionID: String
    let tool: String
    let summary: String
}

struct VaultNote: Identifiable {
    var id: String { name }
    let name: String
    let type: String
    let status: String
    let extra: [String: String]
}

struct DocNode: Identifiable {
    let id: String
    let source: String
    let title: String
    let path: String
}

struct KGEntity: Identifiable {
    var id: String { "kg:\(name)" }
    let name: String
    let type: String
    let mentions: Int
}

struct KGRelation {
    let source: String
    let target: String
    let relation: String
}

struct CodeFile: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
}

/// Derived from ear.log's adjacent (Heard|Follow-up) -> (Reply|Guest reply)
/// timestamp pairs — the same trick the HTML dashboard's Python endpoint
/// uses, so latency is real without adding any new instrumentation to the
/// daemon itself.
struct LogStats {
    var exchangesSinceBoot: Int = 0
    var latencySamplesSecs: [Double] = []
    var recentLines: [String] = []
    /// Only genuinely conversational lines — wake/mention triggers, heard
    /// turns, replies, reflex hits. Ambient "overheard" chatter and
    /// repetition-loop discards are the daemon doing its job of IGNORING the
    /// room; showing them as "exchanges" made the feed read as garbage.
    var conversationLines: [String] = []
    var latencyLastSecs: Double? { latencySamplesSecs.last }
}

/// Real per-turn token counts (OpenJarvis's cost/energy-as-metric idea,
/// ported as real token data rather than a fabricated dollar cost — NIM and
/// Zen are free-tier with no verified per-token pricing to report).
struct TokenUsage: Codable {
    let prompt: Int
    let completion: Int
    let total: Int
}

/// One dispatched turn from ram-log.jsonl — written by the daemon's
/// _log_turn() since Wave 1, specifically so speed claims are measurable.
struct TurnEvent: Codable {
    let ts: String
    let lane: String
    let secs: Double
    let words: Int?
    let memSecs: Double?
    let tokens: TokenUsage?
    /// "test" for turns `test_wave1.py` logged directly through the real
    /// `dispatch()` — found live-mixed into production latency data; filter
    /// these out of anything measuring real-usage speed.
    let source: String?

    enum CodingKeys: String, CodingKey {
        case ts, lane, secs, words, tokens, source
        case memSecs = "mem_secs"
    }
}

struct LaneStat: Identifiable {
    var id: String { lane }
    let lane: String
    let count: Int
    let avgSecs: Double
    let maxSecs: Double
    let totalTokens: Int
}
