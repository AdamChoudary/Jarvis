import Foundation

/// Every on-disk location the dashboard reads. Single source of truth so a
/// path never gets typo-duplicated across services.
enum JarvisPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let jarvisVoiceDir = "\(home)/.hermes/jarvis-voice"
    static let earLog = "\(jarvisVoiceDir)/ear.log"
    static let ramLog = "\(jarvisVoiceDir)/ram-log.jsonl"
    static let memoryDB = "\(jarvisVoiceDir)/jarvis-memory-v7.db"
    static let knowledgeGraphDB = "\(jarvisVoiceDir)/knowledge-graph.db"
    static let envFile = "\(home)/.hermes/.env"
    static let cronJobs = "\(home)/.hermes/cron/jobs.json"
    static let cronOutputDir = "\(home)/.hermes/cron/output"
    static let opencodeDB = "\(home)/.local/share/opencode/opencode.db"
    static let vaultJarvis = "\(home)/Documents/Obsidian Vault/Jarvis"
    static let vaultProjects = "\(vaultJarvis)/Projects"
    static let vaultIdeas = "\(vaultJarvis)/Ideas"
    static let contextDir = "\(home)/Developer/Context"

    /// Docs rendered in the "Way of working" tab, in reading order.
    static let architectureDocs: [(title: String, path: String)] = [
        ("Master context", "\(jarvisVoiceDir)/JARVIS-MASTER-CONTEXT.md"),
        ("Architecture", "\(jarvisVoiceDir)/ARCHITECTURE.md"),
        ("Features", "\(jarvisVoiceDir)/JARVIS-FEATURES.md"),
        ("README", "\(jarvisVoiceDir)/README.md"),
        ("Audit", "\(jarvisVoiceDir)/AUDIT-TODO.md"),
        ("Polish / open items", "\(jarvisVoiceDir)/POLISH-TODO.md"),
        ("Dashboard design", "\(jarvisVoiceDir)/DESIGN.md"),
    ]

    /// Env keys whose values must never be shown, only their presence.
    static let secretEnvKeyMarkers = ["KEY", "TOKEN", "SECRET", "PASSWORD"]
}
