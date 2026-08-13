import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    @Published var daemonAlive = false
    /// True when the ear daemon is down AND launchd still has it registered
    /// (KeepAlive) — i.e. it should be running but silently isn't, as
    /// opposed to being intentionally stopped/unloaded.
    @Published var daemonExpectedButDown = false
    @Published var uptimeHours: Double?
    @Published var ramTrend: [RamSample] = []
    @Published var footprintMb: Double?
    @Published var logStats = LogStats()

    @Published var crons: [CronJob] = []
    @Published var projects: [VaultNote] = []
    @Published var ideas: [VaultNote] = []
    @Published var laneStats: [LaneStat] = []
    @Published var restarts: [RamSample] = []

    @Published var docs: [DocNode] = []
    @Published var kgEntities: [KGEntity] = []
    @Published var kgRelations: [KGRelation] = []
    @Published var kgReadOk = true
    /// When the memory FTS index last actually rebuilt — nil until the first
    /// successful read of `meta.last_rebuild`'s `ts` field.
    @Published var memoryLastRebuilt: Date?

    /// Jarvis's real conversational state — a separate, much faster timer
    /// than the 8s doc/log refresh below, since state responsiveness and
    /// disk-heavy data refresh have very different latency budgets.
    @Published var liveState: JarvisState = .idle

    /// Any tool call an opencode/Claude Code session has in flight right now
    /// — the orrery's comets. A dedicated mid-speed timer: fast enough that a
    /// comet feels live, far cheaper than the 0.2s state poll since each tick
    /// here means a real SQLite read plus parsing up to 200 JSON blobs.
    @Published var pendingToolCalls: [PendingToolCall] = []
    /// False when the last opencode activity DB read failed outright (locked
    /// file, missing db) — distinct from a real "nothing pending" result.
    @Published var pendingToolCallsReadOk = true

    private var timer: AnyCancellable?
    private var stateTimer: AnyCancellable?
    private var activityTimer: AnyCancellable?

    init() {
        refresh()
        timer = Timer.publish(every: 8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        stateTimer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // `@Published` fires objectWillChange on every assignment, even
                // when the new value equals the old one — at 5 ticks/sec that's
                // real, unnecessary view-graph invalidation on every observer
                // (now including the sidebar's vitals dock, since today's
                // redesign). Only publish on an actual change.
                guard let self else { return }
                let next = LiveStateReader.currentState()
                if self.liveState != next { self.liveState = next }
            }
        activityTimer = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task.detached(priority: .utility) {
                    let (calls, ok) = OpencodeActivityReader.pendingToolCalls()
                    await MainActor.run {
                        self?.pendingToolCalls = calls
                        self?.pendingToolCallsReadOk = ok
                    }
                }
            }
    }

    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            let status = ProcessMonitor.jarvisEarStatus()
            let footprint = status.pid.flatMap { ProcessMonitor.footprintMb(pid: $0) }
            let trend = TextLogReaders.ramTrend()
            let stats = TextLogReaders.earLogStats()
            let lanes = TextLogReaders.laneStats()
            let restartEvents = TextLogReaders.restartEvents()
            let crons = CronReader.read()
            let projects = VaultReader.notes(in: JarvisPaths.vaultProjects)
            let ideas = VaultReader.notes(in: JarvisPaths.vaultIdeas)
            let docs = GraphReader.docs()
            let rebuiltAt = GraphReader.lastRebuilt()
            let (entities, entitiesOk) = GraphReader.entities()
            let (relations, relationsOk) = GraphReader.relations()

            await MainActor.run {
                guard let self else { return }
                self.daemonAlive = status.alive
                self.daemonExpectedButDown = status.expectedButDown
                self.uptimeHours = status.uptimeHours
                self.footprintMb = footprint
                self.ramTrend = trend
                self.logStats = stats
                self.crons = crons
                self.projects = projects
                self.ideas = ideas
                self.laneStats = lanes
                self.restarts = restartEvents
                if self.docs.map(\.id) != docs.map(\.id) { self.docs = docs }
                self.memoryLastRebuilt = rebuiltAt
                self.kgEntities = entities
                self.kgRelations = relations
                self.kgReadOk = entitiesOk && relationsOk
            }
        }
    }
}
