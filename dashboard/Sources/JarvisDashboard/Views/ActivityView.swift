import SwiftUI

/// The vitals and activity panel — OpenJarvis's framing ported to our data:
/// latency, memory and reliability treated as first-class metrics alongside
/// what actually happened. Every number here is measured from the daemon's
/// own logs, never estimated.
struct ActivityView: View {
    @EnvironmentObject var store: DataStore
    @State private var slateContent: (title: String, source: String, path: String, content: String)?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    laneTiles
                    HStack(alignment: .top, spacing: 20) {
                        // A real 2x2 grid, not a hand-stacked column — the
                        // four panels here are independent measurements, not
                        // a sequence, so a grid says that structurally instead
                        // of implying memory→routines→work is a reading order.
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)],
                                  spacing: 20) {
                            memoryPanel
                            knowledgePanel
                            routinesPanel
                            workPanel
                        }
                        .frame(maxWidth: .infinity)
                        conversationPanel
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
                // Content otherwise starts under the hidden title bar and the top
                // row of tiles gets clipped by the window chrome.
                .padding(.top, 18)
            }
            .background(Theme.void)

            // Routines/Projects/Ideas rows now open the same real detail
            // panel Space uses — this tab used to show inert copies of that
            // data with no way to actually look at any of it.
            if let content = slateContent {
                SlateView(
                    title: content.title, path: content.path,
                    color: Theme.clusterColor(content.source), content: content.content,
                    onClose: { slateContent = nil }
                )
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.38), value: slateContent != nil)
            }
        }
    }

    /// A routine row's Slate loads its real last-run output — the same data
    /// and the same component the orrery's cron ring uses, not a placeholder.
    private func selectCron(_ job: CronJob) {
        let detail = job.lastStatus.map { "last run: \($0)" } ?? "no runs yet"
        slateContent = (job.name, "cron", job.schedule,
            "\(detail)\n\n" + (CronReader.lastOutput(jobId: job.id) ?? "No run output recorded yet for this job."))
    }

    /// Resolves straight against `store.docs` — this tab has no orbiting
    /// bodies to cross-highlight (that's Space's job), so it can look the
    /// doc id up directly instead of routing through `OrbitalSystem`.
    private func selectVaultNote(_ note: VaultNote) {
        guard let doc = store.docs.first(where: { $0.source == "vault" && $0.title == note.name }) else {
            slateContent = (note.name, "vault", "", "Not yet indexed.")
            return
        }
        slateContent = (doc.title, doc.source, "Loading\u{2026}", "")
        Task.detached(priority: .userInitiated) {
            let result = GraphReader.docContent(id: doc.id)
            await MainActor.run {
                switch result {
                case .found(let title, let source, let path, let content):
                    slateContent = (title, source, path.isEmpty ? source : path, content)
                case .readFailed:
                    slateContent = (doc.title, doc.source, "", "Read failed \u{2014} try again in a moment.")
                case .notFound:
                    slateContent = (doc.title, doc.source, "", "No longer indexed \u{2014} this memory has aged out.")
                }
            }
        }
    }

    // MARK: - Lane latency tiles

    /// One tile per dispatch lane. The reflex tile reading ~0s next to the
    /// fast lane's seconds is the entire Wave 1 story in one glance.
    private var laneTiles: some View {
        HStack(spacing: 14) {
            if store.laneStats.isEmpty {
                statTile(title: "TURNS MEASURED", value: "none yet",
                         detail: "speak to Jarvis and lanes appear here")
            }
            ForEach(store.laneStats) { lane in
                statTile(
                    title: lane.lane.uppercased(),
                    value: lane.avgSecs < 0.1 ? "<0.1s" : String(format: "%.1fs", lane.avgSecs),
                    detail: "\(lane.count) turns \u{00B7} max \(String(format: "%.1fs", lane.maxSecs))"
                        + (lane.totalTokens > 0 ? " \u{00B7} \(formatTokens(lane.totalTokens)) tok" : "")
                )
            }
            statTile(
                title: "SELF-RESTARTS",
                value: "\(store.restarts.count)",
                detail: store.restarts.isEmpty
                    ? "none on record"
                    : (store.restarts.last?.reason.map { String($0.prefix(34)) } ?? "")
            )
            Spacer(minLength: 0)
        }
    }

    private func statTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(Theme.inkDim)
            Text(value)
                .font(Theme.mono(24))
                .foregroundColor(Theme.ink)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: value)
            Text(detail)
                .font(Theme.mono(10))
                .foregroundColor(Theme.inkDim)
                .lineLimit(1)
        }
        .padding(16)
        .frame(minWidth: 150, alignment: .leading)
        .glassPanel()
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    // MARK: - Memory panel

    /// Both memory measures, because they disagree by design: psutil RSS is
    /// blind to Metal allocations; `footprint` is the honest unified number
    /// (measured 3.5x apart on this machine). Showing only one would lie.
    private var memoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader(icon: "memorychip", title: "Memory", subtitle: "process vs unified")
            let rss = store.ramTrend.compactMap(\.rssMb)
            let fp = store.ramTrend.compactMap(\.footprintMb)
            DualSparkline(primary: fp, secondary: rss)
                .frame(height: 56)
            HStack {
                legendDot(color: Theme.ink.opacity(0.85),
                          label: "unified \(fp.last.map { "\(Int($0))MB" } ?? "-")")
                legendDot(color: Theme.inkFaint,
                          label: "process \(rss.last.map { "\(Int($0))MB" } ?? "-")")
                Spacer()
            }
        }
        .padding(18)
        .glassPanel()
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(Theme.mono(10.5)).foregroundColor(Theme.inkDim)
        }
    }

    // MARK: - Routines

    private var routinesPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            panelHeader(icon: "clock", title: "Routines")
            ForEach(store.crons) { job in
                ActivityRow(left: job.name, right: job.lastStatus ?? "-",
                            rightColor: (job.lastStatus == "ok") ? Theme.inkDim : Theme.fail,
                            sub: job.schedule, sub2: job.completed.map { "\($0) runs" } ?? "",
                            action: { selectCron(job) })
            }
        }
        .padding(18)
        .glassPanel()
    }

    // MARK: - Projects and ideas, condensed

    private var workPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Vault-tinted, matching the same color the vault band and
            // LogRailView's own Projects/Ideas icons already use — the same
            // data now reads as visibly the same thing everywhere it appears.
            panelHeader(icon: "folder", title: "Projects & Ideas", color: Theme.clusterColor("vault"))
            ForEach(store.projects) { p in
                ActivityRow(left: p.name, right: p.status, rightColor: Theme.inkDim,
                            dotColor: Theme.clusterColor("vault"), action: { selectVaultNote(p) })
            }
            if !store.projects.isEmpty, !store.ideas.isEmpty {
                Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 4)
            }
            ForEach(store.ideas) { i in
                ActivityRow(left: i.name, right: i.status,
                            rightColor: i.status == "parked" ? Theme.inkFaint : Theme.ink,
                            dotColor: Theme.clusterColor("vault").opacity(0.55), action: { selectVaultNote(i) })
            }
        }
        .padding(18)
        .glassPanel()
    }

    // MARK: - Knowledge graph

    /// The same entity data now orbiting as hex bodies in Space, here as a
    /// real ranked list — a second, complementary home for data that used to
    /// have zero UI anywhere despite being fetched every 8s.
    private var knowledgePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            panelHeader(icon: "hexagon", title: "Knowledge", color: Theme.cKnowledge)
            if store.kgEntities.isEmpty {
                Text(store.kgReadOk
                     ? "No entities distilled yet \u{2014} dormant until Jarvis's ear daemon runs a while."
                     : "Knowledge-graph read failed.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.inkFaint)
                    .padding(.vertical, 6)
            } else {
                ForEach(store.kgEntities.prefix(8)) { entity in
                    HStack {
                        Text(entity.name).font(.system(size: 12.5)).foregroundColor(Theme.ink).lineLimit(1)
                        Spacer()
                        Text("\(entity.mentions)\u{00D7}").font(Theme.mono(11)).foregroundColor(Theme.inkDim)
                    }
                    .padding(.vertical, 2.5)
                }
            }
        }
        .padding(18)
        .glassPanel()
    }

    // MARK: - Conversation feed

    /// Real conversation only. The ambient chatter the daemon transcribes and
    /// discards is deliberately absent: that firehose belongs to the waterfall
    /// gate, not to a feed labelled "conversation".
    private var conversationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader(icon: "bubble.left.and.bubble.right", title: "Conversation", subtitle: "recent")
            if store.logStats.conversationLines.isEmpty {
                Text("No exchanges in the recent log. Say \u{201C}Hey Jarvis\u{201D} near the Mac.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.inkFaint)
                    .padding(.vertical, 6)
            }
            ForEach(Array(store.logStats.conversationLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.mono(11))
                    .foregroundColor(lineColor(line))
                    .lineLimit(2)
                    .padding(.vertical, 1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassPanel()
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("Reply:") || line.contains("Guest reply:") { return Theme.ink }
        if line.contains("Wake (") || line.contains("Mention trigger") { return Theme.amber.opacity(0.85) }
        return Theme.inkDim
    }

    /// Icon + serif title replaces the old small tracked-uppercase label —
    /// panel headers are real content moments (Claude's own typography is
    /// serif for content, sans reserved for dense small UI chrome), not
    /// dense instrument-panel readouts.
    private func panelHeader(icon: String, title: String, subtitle: String? = nil, color: Color = Theme.inkDim) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11.5, weight: .medium)).foregroundColor(color)
            Text(title).font(Theme.serif(14, weight: .medium)).foregroundColor(Theme.ink)
            if let subtitle {
                Text(subtitle).font(.system(size: 10)).foregroundColor(Theme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }
}

/// Same hover/click language as `LogRailView`'s `LogRow` — routines and
/// vault rows here are as clickable as everywhere else this data appears,
/// not flat text that happens to look like the real thing.
private struct ActivityRow: View {
    let left: String
    let right: String
    let rightColor: Color
    var sub: String = ""
    var sub2: String = ""
    var dotColor: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let dotColor {
                        Circle().fill(dotColor).frame(width: 5, height: 5)
                    }
                    Text(left).font(.system(size: 12.5)).foregroundColor(Theme.ink).lineLimit(1)
                    Spacer()
                    Text(right).font(Theme.mono(11.5)).foregroundColor(rightColor)
                }
                if !sub.isEmpty || !sub2.isEmpty {
                    HStack {
                        Text(sub).font(Theme.mono(10)).foregroundColor(Theme.inkFaint)
                        Spacer()
                        Text(sub2).font(Theme.mono(10)).foregroundColor(Theme.inkFaint)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.white.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Two series on a shared scale. Primary reads as the headline line;
/// secondary sits dimmer beneath it.
struct DualSparkline: View {
    let primary: [Double]
    let secondary: [Double]

    var body: some View {
        GeometryReader { geo in
            let all = primary + secondary
            if let lo = all.min(), let hi = all.max(), all.count > 1 {
                let span = max(hi - lo, 1)
                path(for: secondary, in: geo.size, lo: lo, span: span)
                    .stroke(Theme.inkFaint, lineWidth: 1)
                path(for: primary, in: geo.size, lo: lo, span: span)
                    .stroke(Theme.ink.opacity(0.85), lineWidth: 1.2)
            }
        }
    }

    private func path(for series: [Double], in size: CGSize, lo: Double, span: Double) -> Path {
        Path { p in
            guard series.count > 1 else { return }
            for (i, v) in series.enumerated() {
                let x = CGFloat(i) / CGFloat(series.count - 1) * size.width
                let y = size.height - CGFloat((v - lo) / span) * (size.height - 4) - 2
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}
