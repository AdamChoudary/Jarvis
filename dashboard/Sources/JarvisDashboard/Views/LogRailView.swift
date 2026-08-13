import SwiftUI

/// Right-edge rail overlaid on the Space graph — condensed Today/Projects/
/// Ideas, mirroring the HTML dashboard's Log rail. The full-detail versions
/// live in ActivityView (its own sidebar tab). Rows are real cross-links,
/// not a disconnected duplicate: a cron row is the exact same job as a
/// routine-ring tick, a Projects/Ideas row is the exact same vault doc
/// already orbiting in the vault band — clicking either highlights the
/// matching body instead of opening a second, separate preview.
struct LogRailView: View {
    @EnvironmentObject var store: DataStore
    var onSelectCron: (CronJob) -> Void = { _ in }
    var onSelectVaultNote: (VaultNote) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("Today", icon: "clock", first: true) {
                    ForEach(store.crons) { job in
                        LogRow(left: job.name, right: job.lastStatus ?? "-",
                               rightColor: (job.lastStatus == "ok") ? Theme.inkDim : Theme.fail,
                               sub: job.schedule, sub2: job.completed.map { "\($0)x" } ?? "",
                               action: { onSelectCron(job) })
                    }
                }
                section("Projects", icon: "folder", iconColor: Theme.clusterColor("vault")) {
                    ForEach(store.projects) { p in
                        LogRow(left: p.name, right: p.status, rightColor: Theme.inkDim,
                               action: { onSelectVaultNote(p) })
                    }
                }
                section("Ideas", icon: "lightbulb", iconColor: Theme.clusterColor("vault")) {
                    ForEach(store.ideas) { i in
                        LogRow(left: i.name, right: i.status,
                               rightColor: i.status == "parked" ? Theme.inkFaint : Theme.ink,
                               action: { onSelectVaultNote(i) })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel()
    }

    /// `iconColor` defaults to the neutral tone "Today" already used —
    /// matching the cron ring's own "Jarvis's own action, not a memory band"
    /// convention (plain ink, never a cluster hue). Projects/Ideas pass the
    /// real vault cluster color, so the same data reads as visibly-the-same
    /// thing here as it does orbiting in the vault band.
    private func section<Content: View>(_ title: String, icon: String, iconColor: Color = Theme.inkDim,
                                          first: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(1)
                    .foregroundColor(Theme.inkDim)
            }
            content()
        }
        .padding(15)
        .overlay(first ? nil : Divider().overlay(Color.white.opacity(0.1)), alignment: .top)
    }
}

/// Same hover language as `PaletteRow` — the rail's rows are as clickable as
/// any other navigation row in the app, not flat text that happens to sit
/// near a clickable graph.
private struct LogRow: View {
    let left: String
    let right: String
    let rightColor: Color
    var sub: String = ""
    var sub2: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(left).font(.system(size: 12)).foregroundColor(Theme.ink).lineLimit(1)
                    Spacer()
                    Text(right).font(Theme.mono(12)).foregroundColor(rightColor)
                }
                if !sub.isEmpty || !sub2.isEmpty {
                    HStack {
                        Text(sub).font(Theme.mono(10.5)).foregroundColor(Theme.inkDim)
                        Spacer()
                        Text(sub2).font(Theme.mono(10.5)).foregroundColor(Theme.inkDim)
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.white.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
