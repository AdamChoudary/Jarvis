import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case space = "Space"
    case activity = "Activity"
    case code = "Code"
    case architecture = "Way of Working"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .space: return "sparkles"
        case .activity: return "list.bullet.rectangle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .architecture: return "point.3.connected.trianglepath.dotted"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: DataStore
    // The tab you were on survives relaunch. (Also what lets headless tooling
    // screenshot a specific tab: `defaults write com.jarvis.dashboard lastTab
    // Activity` then relaunch.)
    @State private var selection: Destination? =
        Destination(rawValue: UserDefaults.standard.string(forKey: "lastTab") ?? "") ?? .space
    // Pinned open: this is a fixed five-place app, so the sidebar is permanent
    // furniture rather than something to collapse (it was auto-hiding when the
    // window went wide/fullscreen).
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var showPalette = false

    private var paletteItems: [CommandPalette.Item] {
        Destination.allCases.map { dest in
            CommandPalette.Item(title: dest.rawValue, subtitle: "Jump to \(dest.rawValue)") {
                selection = dest
            }
        }
    }

    /// `alwaysShow` is for counts that are meaningfully "how much is being
    /// tracked" (Space) rather than "is anything happening right now"
    /// (Activity) — the latter hides at zero, its resting state, so the
    /// badge itself reads as a real live signal rather than static noise.
    @ViewBuilder
    private func liveBadge(_ count: Int, alwaysShow: Bool = false) -> some View {
        if alwaysShow || count > 0 {
            Text("\(count)")
                .font(Theme.mono(9.5))
                .foregroundColor(Theme.inkFaint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Theme.voidSunken, in: Capsule())
        }
    }

    private let liveDestinations: [Destination] = [.space, .activity]
    private let referenceDestinations: [Destination] = [.code, .architecture, .settings]

    /// A real instrument, not a corner dot — a ring readout plus the actual
    /// state/uptime text, so the sidebar opens with genuine live weight
    /// instead of a decorative sliver.
    private var vitalsDock: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.voidSunken, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: store.daemonAlive ? 1 : 0.001)
                    .stroke(store.daemonAlive ? Theme.look(for: store.liveState).hue : Theme.inkFaint,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.settle, value: store.liveState)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.daemonAlive ? store.liveState.rawValue.capitalized : "Offline")
                    .font(Theme.serif(12, weight: .semibold))
                    .foregroundColor(store.daemonAlive ? Theme.ink : Theme.inkFaint)
                    .contentTransition(.opacity)
                Text(store.uptimeHours.map { String(format: "%.1fh uptime", $0) } ?? "not running")
                    .font(Theme.mono(9.5))
                    .foregroundColor(Theme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.voidRaised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(Theme.inkFaint)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func row(for dest: Destination) -> some View {
        // Only Space and Activity get a live-signal badge and a live-tinted
        // selection color — they're the only two destinations with a real,
        // already-published live source; Code/Way of Working/Settings get
        // the neutral amber selection meaning every other row in the app uses.
        switch dest {
        case .space:
            PaletteRow(title: dest.rawValue, icon: dest.icon, isSelected: selection == dest,
                       accentColor: store.daemonAlive ? Theme.look(for: store.liveState).hue : Theme.amber) {
                selection = dest
            } accessory: {
                liveBadge(store.docs.count + store.kgEntities.count, alwaysShow: true)
            }
        case .activity:
            PaletteRow(title: dest.rawValue, icon: dest.icon, isSelected: selection == dest,
                       accentColor: Theme.cOpencode) {
                selection = dest
            } accessory: {
                liveBadge(store.pendingToolCalls.count)
            }
        default:
            PaletteRow(title: dest.rawValue, icon: dest.icon, isSelected: selection == dest) {
                selection = dest
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Jarvis")
                        .font(Theme.TypeScale.title)
                        .foregroundColor(Theme.ink)
                    Spacer(minLength: 0)
                    Button(action: { showPalette = true }) {
                        Image(systemName: "command")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.inkFaint)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.voidSunken, in: RoundedRectangle(cornerRadius: 6))
                    .magnetic(strength: 5)
                    .help("Jump to… (⌘K)")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

                vitalsDock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)

                sectionLabel("Live")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(liveDestinations) { row(for: $0) }
                }
                .padding(.horizontal, 8)

                sectionLabel("Reference")
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(referenceDestinations) { row(for: $0) }
                }
                .padding(.horizontal, 8)

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.void)
            // Max pinned too: `.balanced` hands the sidebar a share of any extra
            // width otherwise, and a 600pt nav rail for five items is absurd.
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 240)
        } detail: {
            // A real transition on tab switch, not an instant cut — `.id`
            // gives each destination its own identity so SwiftUI actually
            // animates the swap instead of silently reusing the old view.
            Group {
                switch selection ?? .space {
                case .space: SpaceView()
                case .activity: ActivityView()
                case .code: CodeBrowserView()
                case .architecture: ArchitectureView()
                case .settings: SettingsView()
                }
            }
            .id(selection)
            .transition(.opacity.combined(with: .move(edge: .leading)).animation(.easeOut(duration: 0.22)))
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.amber)
        .preferredColorScheme(.dark)
        .overlay(CommandPalette(isPresented: $showPalette, items: paletteItems))
        .onChange(of: selection) { _, tab in
            if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "lastTab") }
        }
    }
}
