import SwiftUI

/// Environment stays read-only (secrets, not tunables). Daemon constants with
/// a FieldMeta entry (ConfigReader.editableFields) are now genuinely writable
/// — isair/jarvis's metadata-driven-settings principle, adapted to a source
/// file instead of a config.json: the same registry entry that renders the
/// widget also bounds what can be written back.
struct SettingsView: View {
    private enum RowSaveStatus { case saved, failed }

    @State private var env: [ConfigEntry] = ConfigReader.envEntries()
    @State private var constants: [ConfigEntry] = ConfigReader.daemonConstants()
    @State private var edits: [String: Double] = [:]
    /// Per-field, not one blanket line — a multi-field save can partly fail,
    /// and "Saved." for five fields when a sixth silently didn't write is
    /// exactly the kind of ambiguity a tuning screen can't afford.
    @State private var rowStatus: [String: RowSaveStatus] = [:]
    @State private var status: String = ""
    @State private var statusIsError = false
    @State private var needsRestart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Daemon tuning below is genuinely writable — Save edits the exact line in jarvis_ear.py, nothing else changes. Everything else here mirrors what's actually running.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)

                group(icon: "slider.horizontal.3", title: "Daemon tuning", subtitle: "jarvis_ear.py") {
                    ForEach(constants) { entry in
                        row(entry)
                    }
                }

                group(icon: "lock", title: "Environment", subtitle: "~/.hermes/.env") {
                    ForEach(env) { entry in
                        HStack {
                            Text(entry.key).font(Theme.mono(12)).foregroundColor(Theme.ink)
                            Spacer()
                            Text(entry.value).font(Theme.mono(12))
                                .foregroundColor(entry.note == "redacted" ? Theme.inkFaint : Theme.inkDim)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.bottom, edits.isEmpty && status.isEmpty && !needsRestart ? 0 : 60)
        }
        .background(Theme.void)
        .overlay(alignment: .bottom) { saveBar }
        .onAppear {
            env = ConfigReader.envEntries()
            constants = ConfigReader.daemonConstants()
        }
    }

    @ViewBuilder
    private func row(_ entry: ConfigEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.key).font(Theme.mono(12)).foregroundColor(Theme.ink)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.system(size: 10.5)).foregroundColor(Theme.inkFaint)
                }
                if let meta = entry.meta {
                    Text("range \(formatValue(meta.min, meta))\u{2013}\(formatValue(meta.max, meta))")
                        .font(.system(size: 10)).foregroundColor(Theme.inkFaint)
                }
            }
            Spacer()
            if let status = rowStatus[entry.key] {
                HStack(spacing: 3) {
                    Image(systemName: status == .saved ? "checkmark" : "xmark")
                    Text(status == .saved ? "saved" : "failed")
                }
                .font(.system(size: 10.5))
                .foregroundColor(status == .saved ? Theme.inkDim : Theme.fail)
                .padding(.top, 2)
            }
            if let meta = entry.meta {
                editableValue(entry, meta)
            } else {
                Text(entry.value).font(Theme.mono(12)).foregroundColor(Theme.inkDim)
            }
        }
        .padding(.vertical, 4)
    }

    /// A plain commit-on-Enter TextField rather than a Stepper: a Stepper's
    /// chevrons are a continuous-press control (and a target for VoiceOver
    /// increment/decrement actions), so a single ambiguous interaction can
    /// silently fire several `set` calls in a row against a live daemon's
    /// source file. Typing a number and pressing Return can't happen by
    /// accident, which is the property this control needs most.
    @ViewBuilder
    private func editableValue(_ entry: ConfigEntry, _ meta: FieldMeta) -> some View {
        let current = edits[entry.key] ?? Double(entry.value) ?? meta.min
        TextField("", text: Binding(
            get: { formatValue(current, meta) },
            set: { text in
                guard let parsed = Double(text) else { return }
                edits[entry.key] = min(max(parsed, meta.min), meta.max)
                rowStatus[entry.key] = nil // a fresh edit retires the last save's confirmation
            }
        ))
        .textFieldStyle(.plain)
        .font(Theme.mono(12))
        .foregroundColor(edits[entry.key] != nil ? Theme.amber : Theme.inkDim)
        .multilineTextAlignment(.trailing)
        .frame(width: 64)
    }

    private func formatValue(_ value: Double, _ meta: FieldMeta) -> String {
        if meta.isInt { return String(Int(value.rounded())) }
        var s = String(format: "%.2f", value)
        while s.hasSuffix("0") && !s.hasSuffix(".0") { s.removeLast() }
        return s
    }

    @ViewBuilder
    private var saveBar: some View {
        if !edits.isEmpty || !status.isEmpty || needsRestart {
            HStack(spacing: 12) {
                if !status.isEmpty {
                    Text(status).font(.system(size: 12))
                        .foregroundColor(statusIsError ? Theme.fail : Theme.inkDim)
                }
                Spacer()
                if needsRestart {
                    Button("Restart daemon to apply") {
                        let ok = ConfigWriter.restartDaemon()
                        status = ok ? "Daemon restarted." : "Restart failed — run launchctl kickstart manually."
                        statusIsError = !ok
                        needsRestart = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.amber)
                }
                if !edits.isEmpty {
                    Button("Save \(edits.count) change\(edits.count == 1 ? "" : "s")") { save() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.ink)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.void.opacity(0.92))
            .overlay(Rectangle().fill(Theme.inkFaint.opacity(0.2)).frame(height: 1), alignment: .top)
        }
    }

    private func save() {
        for (key, value) in edits {
            guard let meta = ConfigReader.editableFields[key] else { continue }
            do {
                try ConfigWriter.write(key: key, value: formatValue(value, meta))
                rowStatus[key] = .saved
            } catch {
                rowStatus[key] = .failed
            }
        }
        constants = ConfigReader.daemonConstants()
        edits.removeAll()
        needsRestart = rowStatus.values.contains(.saved)
    }

    /// Same icon+serif header language every other panel in the app now
    /// uses — Settings stays deliberately the calmest tab (no new structure,
    /// no invented decoration), but the typography system is shared, not
    /// tab-specific, so it finishes the rollout rather than sitting apart.
    private func group<Content: View>(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11.5, weight: .medium)).foregroundColor(Theme.inkDim)
                Text(title).font(Theme.serif(14, weight: .medium)).foregroundColor(Theme.ink)
                Text(subtitle).font(Theme.mono(10)).foregroundColor(Theme.inkFaint)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)
            content()
        }
        .padding(18)
        .glassPanel()
    }
}
