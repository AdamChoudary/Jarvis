import Foundation

enum ProcessMonitor {
    struct Status {
        let alive: Bool
        let pid: Int32?
        let uptimeHours: Double?
        /// True when launchd has the ear daemon's LaunchAgent registered at
        /// all. A bare `pgrep` alone can't tell "intentionally turned off"
        /// (not loaded) apart from "should be running per its own KeepAlive
        /// LaunchAgent but silently isn't" (loaded, no PID) — live-caught
        /// (2026-07-26): the daemon was down for hours with nothing in the
        /// UI to distinguish either case.
        let expectedButDown: Bool
    }

    private static func run(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func jarvisEarStatus() -> Status {
        let pids = run("/usr/bin/pgrep", ["-f", "jarvis_ear.py$"])
            .split(separator: "\n").compactMap { Int32($0) }
        guard let pid = pids.first else {
            let loaded = run("/bin/launchctl", ["list", "com.jarvis.ear"])
                .contains("\"Label\"")
            return Status(alive: false, pid: nil, uptimeHours: nil, expectedButDown: loaded)
        }
        let etime = run("/bin/ps", ["-o", "etime=", "-p", "\(pid)"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Status(alive: true, pid: pid, uptimeHours: parseEtimeHours(etime), expectedButDown: false)
    }

    /// ps etime is "[[DD-]HH:]MM:SS" — parse the pieces present.
    private static func parseEtimeHours(_ etime: String) -> Double? {
        guard !etime.isEmpty else { return nil }
        var days = 0.0
        var rest = etime
        if let dash = etime.firstIndex(of: "-") {
            days = Double(etime[etime.startIndex..<dash]) ?? 0
            rest = String(etime[etime.index(after: dash)...])
        }
        let parts = rest.split(separator: ":").compactMap { Double($0) }
        var seconds = days * 86400
        switch parts.count {
        case 3: seconds += parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: seconds += parts[0] * 60 + parts[1]
        case 1: seconds += parts[0]
        default: break
        }
        return seconds / 3600
    }

    static func footprintMb(pid: Int32) -> Double? {
        let out = run("/usr/bin/footprint", ["\(pid)"])
        for line in out.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("phys_footprint:") {
                let digits = t.dropFirst("phys_footprint:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: " ").first ?? ""
                return Double(digits)
            }
        }
        return nil
    }
}
