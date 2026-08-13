import SwiftUI
import AppKit

/// Claude Desktop's own dark chrome — warm charcoal, warm near-white ink,
/// one terracotta accent — replacing the cool "observatory" palette this app
/// shipped with earlier this session. Deliberate, explicit, single-theme for
/// now: real light+dark would mean threading `colorScheme` through every
/// `Canvas` draw function in the app (they're plain funcs, not views, so
/// `@Environment` isn't reachable from inside them) — a second real pass,
/// not something to bolt on alongside this rewrite. Every property name below
/// is unchanged from before on purpose, so every other view's *logic* needed
/// zero changes — only what these tokens resolve to.
enum Theme {
    static let void = Color(hex: 0x262624)
    static let voidRaised = Color(hex: 0x30302E)
    static let voidSunken = Color(hex: 0x1F1E1D)
    static let ink = Color(hex: 0xF5F4ED)
    static let inkDim = Color(hex: 0xB3B0A8)
    static let inkFaint = Color(hex: 0x7A7870)
    /// The name stays `amber` because every call site already says
    /// `Theme.amber` — what it resolves to is now Claude's verified terracotta
    /// accent (`#da7756`, confirmed against the real logo/brand color, not
    /// the earlier "confident knowledge" approximation `#D97757` — one digit
    /// off, close enough nobody would spot it side by side, but a real
    /// correction now that a verified value exists).
    static let amber = Color(hex: 0xDA7756)
    /// The deeper terracotta Claude's own UI uses for pressed/hover states —
    /// verified against real chat-button styling, not guessed.
    static let amberDeep = Color(hex: 0xBD5D3A)
    static let fail = Color(hex: 0xC9504A)

    static let cOpencode = Color(hex: 0x5FA3A0)
    static let cVault = Color(hex: 0x8E86C9)
    static let cContext = Color(hex: 0x6E9E7C)
    static let cVoice = Color(hex: 0x7C89A6)
    /// The knowledge-graph layer's own identity — distinct from the 4 memory
    /// clusters above and reserved away from `amber` (which stays exclusive
    /// to Jarvis-state/selection everywhere else in the app).
    static let cKnowledge = Color(hex: 0xC9A15A)

    static func clusterColor(_ source: String) -> Color {
        switch source {
        case "opencode": return cOpencode
        case "vault": return cVault
        case "context": return cContext
        case "voice": return cVoice
        case "knowledge": return cKnowledge
        default: return cVoice
        }
    }

    /// 8-step tonal ramps, ported from the design artifact that never made it
    /// into this file the first time around (`amber`/`cVoice` above are
    /// already exact matches for one step each — aliased in below, not
    /// duplicated). Gives real depth/hierarchy instead of one flat accent.
    static let accentRamp: [Color] = [0xE8916B, 0xDA7756, 0xBD5D3A, 0xA2503C, 0x85402F, 0x663224, 0x4A2419, 0x33190F]
        .map { Color(hex: $0) }
    static let coolRamp: [Color] = [0x9FAAC2, 0x7C89A6, 0x67728C, 0x545D73, 0x434A5C, 0x363B48, 0x2C2F38, 0x24262C]
        .map { Color(hex: $0) }

    /// (hue, corona alpha, core alpha, spin multiplier) before the alive/dead
    /// gate — the one shared source every alive-dot/star/corona in the app
    /// reads from, lifted straight from the numbers OverlayWindow's star
    /// tuned first rather than reinvented per view.
    static func look(for state: JarvisState) -> (hue: Color, corona: Double, core: Double, spin: Double) {
        switch state {
        case .listening: return (cVoice, 0.18, 0.75, 1.0)
        case .thinking:  return (amber, 0.22, 1.0, 2.2)
        case .working:   return (amber, 0.30, 1.0, 3.4)
        case .speaking:  return (amber, 0.20, 1.0, 1.4)
        case .idle:      return (amber, 0.14, 1.0, 1.0)
        }
    }

    static let mono = Font.system(.body, design: .monospaced)
    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }

    /// Claude's actual body/display font stack is serif (`ui-serif, Georgia,
    /// Cambria, "Times New Roman", Times, serif` — verified from the real
    /// site, not assumed) — a genuinely distinctive choice most AI products
    /// don't make, and the previous pass used a plain system sans throughout,
    /// which is likely the single biggest reason nothing here read as "part
    /// of Claude" regardless of how correct the colors were. `.system(...,
    /// design: .serif)` is the native SwiftUI equivalent of the web's
    /// `ui-serif` generic (renders as San Francisco's serif companion, "New
    /// York," on macOS).
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// A small named type scale so future rounds stop picking sizes ad hoc
    /// per view — mirrors the design artifact's `.75rem→2.5rem` progression.
    /// `display`/`title`/`body` are serif (real content, Claude's own voice);
    /// `caption`/`micro` stay system sans — small dense UI chrome (labels,
    /// badges) reads better geometric, and Claude's own interface keeps its
    /// smallest UI text sans too, serif reserved for actual content.
    enum TypeScale {
        static let display = Font.system(size: 20, weight: .semibold, design: .serif)
        static let title = Font.system(size: 15, weight: .medium, design: .serif)
        static let body = Font.system(size: 13, design: .serif)
        static let caption = Font.system(size: 11)
        static let micro = Font.system(size: 10, weight: .medium)
    }
}

extension Animation {
    /// Named spring presets ported directly from the design artifact's real
    /// numbers (SwiftUI takes stiffness/damping natively — no response/
    /// dampingFraction conversion needed). Every new interaction added this
    /// round uses one of these two, not a fresh bespoke spring value.
    static let settle = Animation.interpolatingSpring(stiffness: 210, damping: 16)
    static let snappy = Animation.interpolatingSpring(stiffness: 320, damping: 20)
}

/// Jarvis's own real turn state, mirrored from the daemon's write_state()
/// calls — the single vocabulary every view's "is Jarvis alive/active" signal
/// speaks, instead of four independently hand-rolled alive dots.
enum JarvisState: String {
    case idle, listening, thinking, working, speaking

    /// Only these count as Jarvis genuinely *doing* something. Listening is
    /// receiving, not acting, and idle has nothing to signal — amber (and any
    /// leading-edge accent tied to it) stays reserved for real activity.
    var isActing: Bool {
        switch self {
        case .thinking, .working, .speaking: return true
        case .idle, .listening: return false
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The glass instrument-panel look shared by every panel in the app.
struct GlassPanel: ViewModifier {
    var active: JarvisState? = nil

    func body(content: Content) -> some View {
        let acting = active?.isActing ?? false
        let hue = active.map { Theme.look(for: $0).hue }

        content
            .padding(16)
            .background(.regularMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(acting ? 0.16 : 0.1), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(acting ? 0.22 : 0.14), .clear],
                            startPoint: .top, endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .leading) {
                if acting, let hue {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(hue.opacity(0.65))
                        .frame(width: 2)
                        .padding(.vertical, 14)
                }
            }
            // Artifact recipe: `0 18px 40px -20px shadow, inset 0 1px 0 highlight`
            // — SwiftUI has no shadow spread, so the -20px tightening is
            // approximated with a smaller blur radius than the raw 40px.
            .shadow(color: Theme.void.opacity(0.5), radius: 20, x: 0, y: 10)
    }
}

extension View {
    func glassPanel(active: JarvisState? = nil) -> some View { modifier(GlassPanel(active: active)) }
}

/// Selectable list row in the palette's own language — used by the inner
/// navigation columns (Code, Way of Working, and the app's own sidebar)
/// because macOS `List` paints its saturated system-blue selection material
/// over any listRowBackground, and that blue has no place in this palette.
struct PaletteRow<Accessory: View>: View {
    let title: String
    var icon: String? = nil
    var mono = false
    let isSelected: Bool
    /// The tint a selected row commits to — a live state hue for a row that
    /// has one, `Theme.amber` otherwise. Selection is a solid tinted chip,
    /// not a thin bar, on purpose: it needs to read at a glance, not on close
    /// inspection.
    var accentColor: Color = Theme.amber
    let action: () -> Void
    /// A small trailing live-signal view (e.g. a count badge) — only passed
    /// by rows that have a real, non-fabricated live data source.
    var accessory: () -> Accessory
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let icon {
                        Label(title, systemImage: icon).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    } else {
                        Text(title).font(mono ? Theme.mono(12) : .system(size: 13, weight: isSelected ? .semibold : .regular))
                    }
                }
                .foregroundColor(isSelected ? accentColor : Theme.inkDim)
                .lineLimit(1)
                Spacer(minLength: 0)
                accessory()
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? accentColor.opacity(0.16)
                              : (hovering ? Color.white.opacity(0.04) : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? accentColor.opacity(0.4) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension PaletteRow where Accessory == EmptyView {
    /// Every pre-existing call site (no accessory) still compiles unchanged.
    init(title: String, icon: String? = nil, mono: Bool = false, isSelected: Bool,
         accentColor: Color = Theme.amber, action: @escaping () -> Void) {
        self.init(title: title, icon: icon, mono: mono, isSelected: isSelected,
                  accentColor: accentColor, action: action, accessory: { EmptyView() })
    }
}

// MARK: - Motion: magnetic hover

/// A control that leans very slightly toward the cursor while hovered and
/// springs back on release — animejs's own site does exactly this on its
/// nav/buttons. Reads the view's own size via a background GeometryReader
/// (doesn't affect layout) rather than an overlay, so it never sits in front
/// of the content and never intercepts the click a magnetic button still
/// needs to fire.
private struct MagneticModifier: ViewModifier {
    let strength: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { size = geo.size }
                        .onChange(of: geo.size) { _, newValue in size = newValue }
                }
            )
            .offset(x: offset.width, y: offset.height)
            .onContinuousHover { phase in
                guard !reduceMotion else { return }
                switch phase {
                case .active(let p):
                    guard size.width > 0, size.height > 0 else { return }
                    let dx = (p.x / size.width - 0.5) * 2
                    let dy = (p.y / size.height - 0.5) * 2
                    offset = CGSize(width: dx * strength, height: dy * strength)
                case .ended:
                    withAnimation(.settle) {
                        offset = .zero
                    }
                }
            }
    }
}

extension View {
    func magnetic(strength: CGFloat = 8) -> some View { modifier(MagneticModifier(strength: strength)) }
}

// MARK: - Command palette

/// Global ⌘K, the animejs/Claude-Desktop-adjacent way: a local event monitor
/// that only ever consumes the exact ⌘K combination and returns every other
/// keydown untouched — the same non-intrusive pattern `ScrollWheelObserver`
/// in OverlayWindow.swift already established for scroll, applied to a
/// keyboard shortcut that needs to fire regardless of which control has focus.
private struct CommandPaletteHotkeyObserver: NSViewRepresentable {
    let onTrigger: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(onTrigger: onTrigger)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onTrigger = onTrigger
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onTrigger: (() -> Void)?
        private var monitor: Any?

        func attach(onTrigger: @escaping () -> Void) {
            self.onTrigger = onTrigger
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "k" {
                    self?.onTrigger?()
                    return nil // consume only this exact combination
                }
                return event
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// A real command palette, not the HTML preview's mockup — jump to any
/// section of the app from anywhere, ⌘K to open, Escape or a scrim click to close.
struct CommandPalette: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let action: () -> Void
    }

    @Binding var isPresented: Bool
    let items: [Item]
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var filtered: [Item] {
        query.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            CommandPaletteHotkeyObserver { toggle() }
                .frame(width: 0, height: 0)

            if isPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Theme.inkFaint)
                        TextField("Jump to…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .focused($focused)
                    }
                    .padding(14)
                    Divider().overlay(Theme.inkFaint.opacity(0.15))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if filtered.isEmpty {
                                Text("No matches").font(.system(size: 12)).foregroundColor(Theme.inkFaint).padding(10)
                            }
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { i, item in
                                Button(action: { item.action(); close() }) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title).font(.system(size: 13)).foregroundColor(Theme.ink)
                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle).font(.system(size: 11)).foregroundColor(Theme.inkFaint)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(i == selected ? Color.white.opacity(0.08) : .clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 280)
                }
                .frame(width: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.inkFaint.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .onAppear { focused = true; selected = 0 }
                .onChange(of: query) { _, _ in selected = 0 }
                .onExitCommand { close() }
                .onKeyPress(.downArrow) {
                    guard !filtered.isEmpty else { return .handled }
                    selected = min(selected + 1, filtered.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !filtered.isEmpty else { return .handled }
                    selected = max(selected - 1, 0)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard filtered.indices.contains(selected) else { return .handled }
                    filtered[selected].action()
                    close()
                    return .handled
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
    }

    private func toggle() {
        if isPresented { close() } else { isPresented = true }
    }

    private func close() {
        isPresented = false
        query = ""
    }
}
