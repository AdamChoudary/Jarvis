import Foundation

enum CronReader {
    static func read() -> [CronJob] {
        guard let data = FileManager.default.contents(atPath: JarvisPaths.cronJobs),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = obj["jobs"] as? [[String: Any]] else { return [] }
        return jobs.map { j in
            let schedule = (j["schedule"] as? [String: Any])?["display"] as? String
                ?? j["schedule_display"] as? String ?? ""
            let repeatInfo = j["repeat"] as? [String: Any]
            return CronJob(
                id: j["id"] as? String ?? (j["name"] as? String ?? "?"),
                name: j["name"] as? String ?? "?",
                schedule: schedule,
                enabled: j["enabled"] as? Bool ?? false,
                lastRunAt: j["last_run_at"] as? String,
                lastStatus: j["last_status"] as? String,
                completed: repeatInfo?["completed"] as? Int,
                nextRunAt: j["next_run_at"] as? String,
                fireClaim: j["fire_claim"] as? String
            )
        }
    }

    /// The real markdown from a job's most recent run, read from
    /// `~/.hermes/cron/output/<job-id>/<timestamp>.md` — filenames sort
    /// chronologically, so the last one alphabetically is the latest.
    static func lastOutput(jobId: String) -> String? {
        let dir = "\(JarvisPaths.cronOutputDir)/\(jobId)"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir),
              let latest = names.filter({ $0.hasSuffix(".md") }).sorted().last else { return nil }
        return try? String(contentsOfFile: "\(dir)/\(latest)", encoding: .utf8)
    }
}
