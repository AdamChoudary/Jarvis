import SwiftUI

/// Top-left vitals instrument — identity, uptime, latency, RAM/footprint.
struct HelmView: View {
    @EnvironmentObject var store: DataStore

    private var lastRss: Double? { store.ramTrend.last?.rssMb }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Circle()
                    .fill(store.daemonAlive ? Theme.look(for: store.liveState).hue
                          : store.daemonExpectedButDown ? Theme.fail : Theme.inkFaint)
                    .frame(width: 8, height: 8)
                    .shadow(color: store.daemonAlive ? Theme.look(for: store.liveState).hue.opacity(0.4) : .clear, radius: 4)
                Text("Jarvis").font(Theme.serif(14, weight: .medium)).foregroundColor(Theme.ink)
                Spacer()
                Text(store.daemonAlive ? store.liveState.rawValue.capitalized
                     : store.daemonExpectedButDown ? "Offline — should be running" : "Offline")
                    .font(Theme.mono(11))
                    .foregroundColor(store.daemonExpectedButDown ? Theme.fail : Theme.inkDim)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: store.liveState)
            }
            .padding(.bottom, 14)

            kv("Uptime", store.uptimeHours.map { String(format: "%.1fh", $0) } ?? "-")
            kv("Brain latency", latencyText)
            kv("Exchanges", "\(store.logStats.exchangesSinceBoot) since boot")
            kv("Process / unified",
               "\(lastRss.map { "\(Int($0))MB" } ?? "-") / \(store.footprintMb.map { "\(Int($0))MB" } ?? "-")")

            HStack(spacing: 6) {
                ConfidenceGlyph(healthy: memoryHealthy, color: memoryHealthy ? Theme.cKnowledge : Theme.fail)
                Text("Memory").font(.system(size: 11.5)).foregroundColor(Theme.inkDim)
                Spacer()
            }
            .padding(.vertical, 3.5)
            .overlay(Divider().overlay(Color.white.opacity(0.1)), alignment: .top)
            .help(memoryHealthDetail)

            Sparkline(samples: store.ramTrend)
                .frame(height: 30)
                .padding(.top, 10)

            Text("\(store.docs.count) bodies \u{00B7} 4 orbits + \(store.crons.count) routines \u{00B7} \(store.kgEntities.isEmpty ? "no entities yet" : "\(store.kgEntities.count) entities")")
                .font(Theme.mono(10)).foregroundColor(Theme.inkDim)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassPanel(active: store.daemonAlive ? store.liveState : nil)
    }

    private var latencyText: String {
        guard let s = store.logStats.latencyLastSecs else { return "-" }
        return s < 60 ? String(format: "%.1fs", s) : String(format: "%.1fm", s / 60)
    }

    /// Categorical, not a percentage (CVP pattern) — surfaces data that was
    /// already being fetched every 8s but never shown anywhere: the memory
    /// index's own last-rebuild timestamp (added after a real 6-day-stale
    /// incident) and the two read-failure flags that exist specifically to
    /// tell "read failed" apart from "genuinely empty."
    private var memoryHealthy: Bool {
        guard let rebuilt = store.memoryLastRebuilt else { return false }
        return store.kgReadOk && store.pendingToolCallsReadOk
            && Date().timeIntervalSince(rebuilt) < 24 * 3600
    }

    private var memoryHealthDetail: String {
        guard let rebuilt = store.memoryLastRebuilt else { return "Memory index has never rebuilt." }
        let hoursAgo = Int(Date().timeIntervalSince(rebuilt) / 3600)
        var parts = ["Index rebuilt \(hoursAgo)h ago"]
        if !store.kgReadOk { parts.append("knowledge-graph read failed") }
        if !store.pendingToolCallsReadOk { parts.append("activity read failed") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 11.5)).foregroundColor(Theme.inkDim)
            Spacer()
            Text(v).font(Theme.mono(11.5)).foregroundColor(Theme.ink).lineLimit(1)
        }
        .padding(.vertical, 3.5)
        .overlay(Divider().overlay(Color.white.opacity(0.1)), alignment: .top)
    }
}

/// RAM trend, hoverable — a plain dot plus a value+time label at the hovered
/// point, not a crosshair (DESIGN.md bans those as targeting decor).
struct Sparkline: View {
    let samples: [RamSample]
    @State private var hoverIndex: Int?

    private var points: [(value: Double, ts: String?)] {
        samples.compactMap { s in s.rssMb.map { (value: $0, ts: s.ts) } }
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points
            if pts.count > 1, let lo = pts.map(\.value).min(), let hi = pts.map(\.value).max() {
                let span = Swift.max(hi - lo, 1)
                let point: (Int) -> CGPoint = { i in
                    CGPoint(x: CGFloat(i) / CGFloat(pts.count - 1) * geo.size.width,
                            y: geo.size.height - CGFloat((pts[i].value - lo) / span) * (geo.size.height - 4) - 2)
                }
                ZStack(alignment: .topLeading) {
                    Path { path in
                        for i in pts.indices {
                            i == 0 ? path.move(to: point(i)) : path.addLine(to: point(i))
                        }
                    }
                    .stroke(Theme.inkDim.opacity(0.75), lineWidth: 1.2)

                    if let i = hoverIndex {
                        let p = point(i)
                        Circle().fill(Theme.ink).frame(width: 4, height: 4).position(p)
                        Text("\(Int(pts[i].value))MB \u{00B7} \(shortTime(pts[i].ts))")
                            .font(Theme.mono(9.5))
                            .foregroundColor(Theme.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.void.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                            .fixedSize()
                            .position(x: min(max(p.x, 34), geo.size.width - 34), y: max(p.y - 13, 8))
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        let idx = Int(((loc.x / geo.size.width) * CGFloat(pts.count - 1)).rounded())
                        hoverIndex = min(max(idx, 0), pts.count - 1)
                    case .ended:
                        hoverIndex = nil
                    }
                }
            }
        }
    }

    private func shortTime(_ ts: String?) -> String {
        guard let ts, let tIndex = ts.firstIndex(of: "T") else { return "-" }
        return String(ts[ts.index(after: tIndex)...].prefix(5))
    }
}

/// A categorical health dot (CVP pattern: solid vs. hatched, never a numeric
/// percentage — binary signals let you decide faster). SwiftUI has no native
/// hatch fill, so this draws real diagonal lines and clips them to a circle.
private struct ConfidenceGlyph: View {
    let healthy: Bool
    let color: Color

    var body: some View {
        ZStack {
            if healthy {
                Circle().fill(color)
            } else {
                Circle().fill(color.opacity(0.15))
                HatchLines().stroke(color, lineWidth: 1).clipShape(Circle())
            }
        }
        .frame(width: 8, height: 8)
    }
}

private struct HatchLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 2.5
        var x: CGFloat = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.minY))
            x += step
        }
        return path
    }
}
