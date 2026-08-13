import Foundation

/// Live turn state, mirrored from the daemon's `write_state()` calls in
/// jarvis_ear.py (isair/jarvis-inspired: every view's "what is Jarvis doing"
/// signal should reflect what the assistant is actually doing, not just
/// whether the process is up). Polled from a tiny JSON file rather than a
/// socket — same file-based pattern as every other reader in this dashboard,
/// and cheap enough to read many times a second. Shared by OverlayWindow and
/// DataStore so the two don't each hand-roll their own copy of this file read.
enum LiveStateReader {
    struct Snapshot { let state: JarvisState; let ts: Date }

    static func read() -> Snapshot? {
        let path = "\(JarvisPaths.jarvisVoiceDir)/state.json"
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stateRaw = obj["state"] as? String,
              let ts = obj["ts"] as? Double else { return nil }
        return Snapshot(state: JarvisState(rawValue: stateRaw) ?? .idle, ts: Date(timeIntervalSince1970: ts))
    }

    /// A stale file (daemon restarted mid-write, or crashed before ever
    /// writing one) must read as idle, not freeze on whatever state happened
    /// to be last written.
    static func currentState(freshWithin seconds: TimeInterval = 30) -> JarvisState {
        guard let snap = read(), Date().timeIntervalSince(snap.ts) < seconds else { return .idle }
        return snap.state
    }
}
