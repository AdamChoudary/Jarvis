import SwiftUI
import AppKit

struct SpaceView: View {
    @EnvironmentObject var store: DataStore
    @StateObject private var sim = OrbitalSystem()
    @State private var selected: OrbitNode?
    @State private var hovered: OrbitNode?
    @State private var selectedCronID: String?
    @State private var slateContent: (title: String, source: String, path: String, content: String)?
    @State private var bandLabels: [BandLabel] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Camera — a presentation-layer transform wrapping the whole draw() call
    // and inverted before any hit-testing. OrbitalSystem's own center/radius
    // math never changes; this only affects what's shown and where clicks land.
    @State private var zoom: CGFloat = 1.0
    @State private var zoomBase: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var panVelocity: CGSize = .zero
    @State private var isPanning = false

    struct BandLabel: Identifiable {
        let id: String
        let count: Int
        let point: CGPoint
        let color: Color
    }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    TimelineView(.animation) { timeline in
                        Canvas { context, size in
                            sim.step()
                            sim.setCrons(store.crons)
                            sim.setRelations(store.kgRelations)
                            updateCamera()
                            draw(context: &context, size: size,
                                 now: timeline.date.timeIntervalSinceReferenceDate)
                        }
                    }
                    .onAppear {
                        sim.reduceMotion = reduceMotion
                        relayout(geo.size, seeding: true)
                    }
                    .onChange(of: reduceMotion) { _, newValue in
                        // The system setting can flip while the app is already
                        // running; the simulation's own copy must track it live,
                        // not just whatever it was at launch.
                        sim.reduceMotion = newValue
                    }
                    .onChange(of: store.docs.map(\.id)) { _, _ in
                        relayout(geo.size, seeding: true)
                    }
                    .onChange(of: store.kgEntities.map(\.id)) { _, _ in
                        relayout(geo.size, seeding: true)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        relayout(newSize, seeding: false)
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            hovered = sim.nearestNode(to: toSimSpace(point))
                            sim.wantsSlowMotion = hovered != nil
                        case .ended:
                            hovered = nil
                            sim.wantsSlowMotion = false
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let dist = hypot(value.translation.width, value.translation.height)
                                if !isPanning && dist > 6 {
                                    isPanning = true
                                    panBase = panOffset
                                }
                                if isPanning {
                                    let limit = panLimit()
                                    panOffset = CGSize(
                                        width: rubberBand(panBase.width + value.translation.width, limit: limit),
                                        height: rubberBand(panBase.height + value.translation.height, limit: limit)
                                    )
                                }
                            }
                            .onEnded { value in
                                if isPanning {
                                    isPanning = false
                                    let remainingW = value.predictedEndTranslation.width - value.translation.width
                                    let remainingH = value.predictedEndTranslation.height - value.translation.height
                                    panVelocity = reduceMotion ? .zero
                                        : CGSize(width: remainingW * 0.08, height: remainingH * 0.08)
                                } else if let hit = sim.nearestNode(to: toSimSpace(value.location)) {
                                    select(hit)
                                } else if let job = nearestCronTick(to: toSimSpace(value.location)) {
                                    selectCron(job)
                                } else {
                                    selected = nil
                                    selectedCronID = nil
                                    slateContent = nil
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in zoom = clampZoom(zoomBase * value) }
                            .onEnded { _ in zoomBase = zoom }
                    )
                    .overlay(
                        ScrollWheelObserver { deltaX, deltaY in
                            guard !isPanning else { return } // an active click-drag pan owns the camera
                            panVelocity = .zero
                            let limit = panLimit()
                            panOffset = CGSize(
                                width: rubberBand(panOffset.width + deltaX, limit: limit),
                                height: rubberBand(panOffset.height + deltaY, limit: limit)
                            )
                        }
                        .allowsHitTesting(false)
                    )

                    // Band captions are plain views, not Canvas text. Laying text out
                    // inside the draw loop meant re-resolving every caption 60 times
                    // a second for labels that only move when the window resizes —
                    // and letting Canvas scale them with the camera would shrink
                    // type as you zoom out, which reads as broken, not intentional.
                    ForEach(bandLabels) { label in
                        (Text(label.id).foregroundColor(label.color.opacity(0.9))
                         + Text("  \(label.count)").foregroundColor(label.color.opacity(0.5)))
                            .font(Theme.mono(10.5))
                            .position(toScreenSpace(label.point))
                            .allowsHitTesting(false)
                    }

                    if isCameraDisplaced {
                        Button(action: recenter) {
                            Image(systemName: "scope")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.inkDim)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        .padding(16)
                        .help("Reset zoom and pan")
                        .transition(.opacity)
                    }

                    if let content = slateContent {
                        SlateView(
                            title: content.title, path: content.path,
                            color: Theme.clusterColor(content.source), content: content.content,
                            onClose: { selected = nil; selectedCronID = nil; slateContent = nil }
                        )
                        .padding(22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(duration: 0.38), value: slateContent != nil)
                    }
                }
            }
            // The depth wash behind the system is a static layer, composited once by
            // the GPU. It used to be a full-screen radial gradient repainted inside
            // the Canvas on every single frame, which was the single most expensive
            // thing in the view and the main reason the orrery felt heavy.
            .background {
                RadialGradient(
                    colors: [Color.white.opacity(0.030), .clear],
                    center: UnitPoint(x: 0.46, y: 0.48),
                    startRadius: 0, endRadius: 640
                )
                .background(Theme.void)
            }

            // A real fixed-width instrument column — Helm and the Log rail as
            // actual layout siblings, not cards floating over the canvas. The
            // orrery to the left is now genuinely bounded to its own region
            // instead of bleeding under floating panel islands (the previous
            // structure, however much the tokens on top of it changed).
            VStack(alignment: .leading, spacing: 16) {
                HelmView()
                LogRailView(
                    onSelectCron: { selectCron($0) },
                    onSelectVaultNote: { selectVaultNote($0) }
                )
                .frame(maxHeight: .infinity)
            }
            .padding(16)
            .frame(width: 320)
            .background(Theme.voidRaised)
        }
    }

    // MARK: - Camera

    /// Gesture-recognizer noise can leave zoom/pan a fraction of a point off
    /// their resting values even when nothing was meaningfully dragged or
    /// pinched — an exact `!= 1` / `!= .zero` check would flicker the recenter
    /// control on at rest. Only a real displacement should show it.
    private var isCameraDisplaced: Bool {
        abs(zoom - 1) > 0.01 || abs(panOffset.width) > 1 || abs(panOffset.height) > 1
    }

    private func panLimit() -> CGFloat { sim.maxRadius * zoom * 0.55 + 150 }

    private func clampZoom(_ z: CGFloat) -> CGFloat { min(4.0, max(0.5, z)) }

    /// macOS-style soft bound: movement past `limit` keeps responding, just
    /// with steeply diminishing returns, rather than hard-stopping.
    private func rubberBand(_ raw: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0, abs(raw) > limit else { return raw }
        let sign: CGFloat = raw < 0 ? -1 : 1
        let excess = (abs(raw) - limit) * 0.25
        return sign * (limit + excess / (1 + excess / limit))
    }

    private func updateCamera() {
        guard !reduceMotion else { panVelocity = .zero; return }
        guard abs(panVelocity.width) > 0.05 || abs(panVelocity.height) > 0.05 else { return }
        let limit = panLimit()
        panOffset = CGSize(
            width: rubberBand(panOffset.width + panVelocity.width, limit: limit),
            height: rubberBand(panOffset.height + panVelocity.height, limit: limit)
        )
        panVelocity.width *= 0.92
        panVelocity.height *= 0.92
    }

    private func recenter() {
        panVelocity = .zero
        if reduceMotion {
            zoom = 1; zoomBase = 1; panOffset = .zero
        } else {
            withAnimation(.spring(duration: 0.4)) { zoom = 1; zoomBase = 1; panOffset = .zero }
        }
    }

    private func cameraCenter() -> CGPoint { sim.center }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    /// Sim-space -> screen-space, matching the transform `draw()` applies to
    /// the Canvas. Used to keep hoisted-out labels and controls in step with
    /// pan/zoom without touching OrbitalSystem's own coordinates.
    private func toScreenSpace(_ p: CGPoint) -> CGPoint {
        let c = cameraCenter()
        return CGPoint(x: c.x + panOffset.width + (p.x - c.x) * zoom,
                       y: c.y + panOffset.height + (p.y - c.y) * zoom)
    }

    /// Screen-space -> sim-space, the inverse — every hit-test goes through
    /// this before asking OrbitalSystem "what's here."
    private func toSimSpace(_ p: CGPoint) -> CGPoint {
        let c = cameraCenter()
        return CGPoint(x: c.x + (p.x - c.x - panOffset.width) / zoom,
                       y: c.y + (p.y - c.y - panOffset.height) / zoom)
    }

    private func relayout(_ size: CGSize, seeding: Bool) {
        // No insets to reserve any more — the canvas is now genuinely bounded
        // to its own HStack region (Helm/the Log rail live in a real sibling
        // column, not floating over this space), so it owns its full size.
        sim.layout(size: size, helmInset: .zero, railInset: 0)
        if seeding {
            var vaultStatus: [String: String] = [:]
            for note in store.projects + store.ideas where !note.status.isEmpty {
                vaultStatus[note.name] = note.status
            }
            sim.reconcile(docs: store.docs, vaultStatus: vaultStatus, entities: store.kgEntities)
            if let sel = selected, !sim.nodes.contains(where: { $0.id == sel.id }) {
                selected = nil
                slateContent = nil
            }
        }
        bandLabels = sim.rings.filter { $0.count > 0 }.map { ring in
            let p = sim.ringPoint(ring, angle: ring.labelAngle)
            return BandLabel(id: ring.source, count: ring.count,
                             point: CGPoint(x: p.x, y: p.y + 12),
                             color: Theme.clusterColor(ring.source))
        }
    }

    private func select(_ node: OrbitNode) {
        selected = node
        if node.source == "knowledge" {
            selectKnowledgeEntity(node)
            return
        }
        slateContent = (node.title, node.source, "Loading...", "")
        Task.detached(priority: .userInitiated) {
            var result = GraphReader.docContent(id: node.id)
            if case .readFailed = result {
                try? await Task.sleep(nanoseconds: 400_000_000)
                result = GraphReader.docContent(id: node.id)
            }
            await MainActor.run {
                guard selected?.id == node.id else { return }
                switch result {
                case .found(let title, let source, let path, let content):
                    slateContent = (title, source, path.isEmpty ? source : path, content)
                case .readFailed:
                    slateContent = (node.title, node.source, "", "Read failed — try again in a moment.")
                case .notFound:
                    let justRestarted = (store.uptimeHours ?? 99) < (2.0 / 60.0)
                    slateContent = (node.title, node.source, "",
                        justRestarted ? "Jarvis just restarted and is still re-indexing."
                                       : "No longer indexed — this memory has aged out.")
                }
            }
        }
    }

    /// Entity content lives entirely in already-published `DataStore` state —
    /// no SQL round-trip needed, unlike the doc path above (simpler, not
    /// harder, per the plan-review pass that caught this branch was missing).
    private func selectKnowledgeEntity(_ node: OrbitNode) {
        let name = node.title
        guard let entity = store.kgEntities.first(where: { $0.name == name }) else {
            slateContent = (name, "knowledge", "", "Entity no longer present in the knowledge graph.")
            return
        }
        let related = store.kgRelations.filter { $0.source == name || $0.target == name }
        var body = "Type: \(entity.type)\nMentions: \(entity.mentions)\n"
        if related.isEmpty {
            body += "\nNo known relations yet."
        } else {
            body += "\nRelations:\n" + related.map { r in
                r.source == name ? "  \u{2192} \(r.relation) \u{2192} \(r.target)"
                                  : "  \u{2190} \(r.relation) \u{2190} \(r.source)"
            }.joined(separator: "\n")
        }
        slateContent = (name, "knowledge", "", body)
    }

    /// A routine ring tick's Slate loads the job's real metadata and its
    /// actual latest run output — not a placeholder, the genuine markdown
    /// the daemon wrote for that run.
    private func selectCron(_ job: CronJob) {
        selected = nil
        selectedCronID = job.id
        let detail = job.lastStatus.map { "last run: \($0)" } ?? "no runs yet"
        slateContent = (job.name, "cron", job.schedule,
            "\(detail)\n\n" + (CronReader.lastOutput(jobId: job.id) ?? "No run output recorded yet for this job."))
    }

    /// LogRail's Projects/Ideas rows are the exact same vault docs already in
    /// the orrery — clicking one highlights the matching body instead of
    /// opening a second, disconnected preview.
    private func selectVaultNote(_ note: VaultNote) {
        guard let node = sim.nodes.first(where: { $0.source == "vault" && $0.title == note.name }) else { return }
        select(node)
    }

    private func nearestCronTick(to point: CGPoint, within radius: CGFloat = 14) -> CronJob? {
        let c = sim.center, r = sim.cronRingRadius
        var best: CronJob?
        var bestDist = radius
        for tick in sim.cronTicks {
            let a = tick.angle + sim.cronRingAngle
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * sim.tilt)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < bestDist { bestDist = d; best = tick.job }
        }
        return best
    }

    /// 0.3 (resting) ramping to 0.95 as a job's next scheduled run approaches
    /// over its final 15 minutes — Jarvis's own upcoming actions, not a
    /// generic pulse.
    private func cronBrightness(_ job: CronJob) -> Double {
        guard let nextRunAt = job.nextRunAt,
              let next = SpaceView.iso8601.date(from: nextRunAt) else { return 0.35 }
        let secondsUntil = next.timeIntervalSinceNow
        guard secondsUntil > 0 else { return 0.35 }
        let rampWindow: TimeInterval = 15 * 60
        let proximity = 1 - min(1, secondsUntil / rampWindow)
        return 0.3 + proximity * 0.65
    }

    private static let iso8601 = ISO8601DateFormatter()

    // MARK: - Drawing

    /// Painter's algorithm: the far half of every orbit, then the star, then the
    /// near half. Bodies genuinely pass behind and in front of the sun, which is
    /// what sells the tilt as depth rather than as a squashed circle. The whole
    /// pass runs inside the camera transform; only text draws counter it.
    private func draw(context: inout GraphicsContext, size: CGSize, now: Double) {
        let c = cameraCenter()
        context.translateBy(x: c.x + panOffset.width, y: c.y + panOffset.height)
        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -c.x, y: -c.y)

        drawOrbitRings(context: &context)
        drawKnowledgeThreads(context: &context)
        drawBodies(context: &context, half: .far)
        drawCore(context: &context, now: now)
        drawCronRing(context: &context)
        drawBodies(context: &context, half: .near)
        drawHover(context: &context)
        drawSelection(context: &context)
        drawActivityComets(context: &context, now: now)
    }

    private func ellipse(radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: sim.center.x - radius,
            y: sim.center.y - radius * sim.tilt,
            width: radius * 2,
            height: radius * 2 * sim.tilt
        ))
    }

    private func drawOrbitRings(context: inout GraphicsContext) {
        for ring in sim.rings where ring.count > 0 {
            context.stroke(
                ellipse(radius: ring.radius),
                with: .color(Theme.clusterColor(ring.source).opacity(0.22)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 7])
            )
        }
    }

    /// The literal, data-real answer to "map the connections": every
    /// `KGRelation` becomes a thin thread between the two entity bodies it
    /// connects. Resolved by name against `entityNodesByName` fresh each
    /// frame (cheap — relations is a small, effectively-static set, same
    /// shape as `cronTicks`) rather than cached, so a relation whose entity
    /// was dropped or renamed (the schema enforces no foreign key) is simply
    /// skipped, never a dangling line to nowhere.
    private func drawKnowledgeThreads(context: inout GraphicsContext) {
        guard !sim.relations.isEmpty else { return }
        var path = Path()
        for rel in sim.relations {
            guard let a = sim.entityNodesByName[rel.source],
                  let b = sim.entityNodesByName[rel.target] else { continue }
            path.move(to: CGPoint(x: a.x, y: a.y))
            path.addLine(to: CGPoint(x: b.x, y: b.y))
        }
        context.stroke(path, with: .color(Theme.cKnowledge.opacity(0.28)), lineWidth: 0.75)
    }

    /// Jarvis itself: the same HeroDial the desktop widget shows, at the
    /// orrery's centre — the rainbow ring, its living tick band, and
    /// whichever per-state pixel-art scene is currently active (the forge
    /// while working, the talking face while speaking, etc). Deliberately
    /// drawn as a true circle rather than squashed by `sim.tilt` like the
    /// orbit ellipses around it — the dial is pixel-sampled from a real
    /// reference and a tilted, distorted copy of it would just look broken,
    /// not "in perspective." `includeBackdrop: false` because this view
    /// already has its own real background — the widget's vignette is only
    /// needed behind a dial floating on bare desktop.
    private func drawCore(context: inout GraphicsContext, now: Double) {
        HeroDial.draw(context: &context, center: sim.center, R: sim.heroDialRadius, now: now,
                     state: store.liveState, daemonAlive: store.daemonAlive, includeBackdrop: false)
    }

    /// Jarvis's own scheduled routines — the innermost ring, diamond ticks
    /// rather than discs so they never read as more memory bodies. Neutral
    /// ink, not a band colour: these are Jarvis's own actions, not a 5th
    /// memory source. Brightness ramps as a run approaches; an errored last
    /// run gets a faint fail-tinted outline; a job actually executing right
    /// now (fireClaim set) gets a brief amber flare.
    private func drawCronRing(context: inout GraphicsContext) {
        guard !sim.cronTicks.isEmpty else { return }
        let c = sim.center
        let baseR = sim.cronRingRadius
        for tick in sim.cronTicks {
            // Same organic-wobble language as the orbiting bodies, at its own
            // per-job phase — Jarvis's own routines breathe gently too,
            // instead of sitting on the ring like fixed clock marks.
            let phase = Double(abs(tick.job.id.hashValue % 1000)) / 1000.0 * 2 * .pi
            let r = reduceMotion ? baseR : baseR * (1 + sin(sim.ambientClock + phase) * 0.03)
            let a = tick.angle + sim.cronRingAngle
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * sim.tilt)
            let job = tick.job
            let isFiring = job.fireClaim != nil
            let isSelected = tick.job.id == selectedCronID
            let brightness = cronBrightness(job)
            let size: CGFloat = isFiring ? 5 : 3.2

            if isFiring {
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Theme.amber.opacity(0.5), location: 0),
                            .init(color: Theme.amber.opacity(0), location: 1),
                        ]),
                        center: p, startRadius: 0, endRadius: 9
                    )
                )
            }

            context.fill(
                diamond(at: p, size: size),
                with: .color((isFiring ? Theme.amber : Theme.ink).opacity(brightness))
            )
            if job.lastStatus == "error" {
                context.stroke(diamond(at: p, size: size + 2.5), with: .color(Theme.fail.opacity(0.6)), lineWidth: 1)
            }
            if isSelected {
                context.stroke(diamond(at: p, size: size + 4.5), with: .color(Theme.amber.opacity(0.8)), lineWidth: 1.1)
            }
        }
    }

    private func diamond(at p: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y - size))
        path.addLine(to: CGPoint(x: p.x + size, y: p.y))
        path.addLine(to: CGPoint(x: p.x, y: p.y + size))
        path.addLine(to: CGPoint(x: p.x - size, y: p.y))
        path.closeSubpath()
        return path
    }

    /// Knowledge-graph entities' own glyph — circle means doc, diamond
    /// already means cron (Jarvis's own routines); hex is reserved for
    /// Jarvis's own synthesized understanding, a third shape that never
    /// collides with either established meaning.
    private func hexagon(at p: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        for i in 0..<6 {
            let angle = Double(i) / 6 * 2 * .pi - .pi / 2
            let point = CGPoint(x: p.x + cos(angle) * size, y: p.y + sin(angle) * size)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    /// Aim assist: the body under the cursor brightens and names itself before
    /// you commit to a click, so you always know what you are about to open.
    private func drawHover(context: inout GraphicsContext) {
        guard let node = hovered, node.id != selected?.id else { return }
        let p = CGPoint(x: node.x, y: node.y)
        let color = Theme.clusterColor(node.source)
        let r: CGFloat = 5.5
        context.fill(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Theme.ink.opacity(0.95), location: 0),
                    .init(color: color.opacity(0.55), location: 0.55),
                    .init(color: color.opacity(0), location: 1),
                ]),
                center: p, startRadius: 0, endRadius: r
            )
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
            with: .color(Theme.ink.opacity(0.45)), lineWidth: 1
        )
        drawLabel(node.title, at: p, in: context, color: Theme.ink.opacity(0.9), fontSize: 10.5)
    }

    private enum OrbitHalf { case far, near }

    /// Bodies are batched into one path per (band, depth tier) and filled with a
    /// flat colour. That is roughly a dozen fills a frame instead of one radial
    /// gradient per body, which is what made the first build stutter, and a hard
    /// edged disc is what makes a star field look sharp instead of smeared.
    /// Freshly reconciled bodies get their own low-opacity tier for their first
    /// ~36 frames instead of popping in at full brightness.
    private func drawBodies(context: inout GraphicsContext, half: OrbitHalf) {
        struct Batch: Hashable { let source: String; let tier: Int }
        let tierAlpha: [Double] = [0.40, 0.66, 0.94, 0.16]
        var batches: [Batch: Path] = [:]

        for node in sim.nodes {
            guard selected?.id != node.id, hovered?.id != node.id else { continue }
            // sin(angle) > 0 puts the body on the lower, nearer arc of the tilt.
            let depth = (sin(node.angle) + 1) / 2
            let isNear = sin(node.angle) > 0
            guard (half == .near) == isNear else { continue }

            let tier = node.isSettling ? 3 : (depth < 0.34 ? 0 : (depth < 0.67 ? 1 : 2))
            let r = node.dotSize * (0.82 + 0.30 * depth)
            if node.source == "knowledge" {
                batches[Batch(source: node.source, tier: tier), default: Path()]
                    .addPath(hexagon(at: CGPoint(x: node.x, y: node.y), size: r))
            } else {
                batches[Batch(source: node.source, tier: tier), default: Path()]
                    .addEllipse(in: CGRect(x: node.x - r, y: node.y - r, width: r * 2, height: r * 2))
            }
        }

        for (batch, path) in batches {
            context.fill(
                path,
                with: .color(Theme.clusterColor(batch.source).opacity(tierAlpha[batch.tier]))
            )
        }
    }

    /// The selected document: a beam home to the star, a bright body, an amber
    /// ring, and its title. Amber stays reserved for exactly this and the core.
    private func drawSelection(context: inout GraphicsContext) {
        guard let node = selected else { return }
        let p = CGPoint(x: node.x, y: node.y)

        var beam = Path()
        beam.move(to: sim.center)
        beam.addLine(to: p)
        context.stroke(
            beam,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Theme.amber.opacity(0.05), location: 0),
                    .init(color: Theme.amber.opacity(0.45), location: 1),
                ]),
                startPoint: sim.center, endPoint: p
            ),
            lineWidth: 1
        )

        let r: CGFloat = 7
        context.fill(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hex: 0xF6EAD2).opacity(0.98), location: 0),
                    .init(color: Theme.amber.opacity(0.45), location: 0.5),
                    .init(color: Theme.amber.opacity(0), location: 1),
                ]),
                center: p, startRadius: 0, endRadius: r
            )
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)),
            with: .color(Theme.amber.opacity(0.8)), lineWidth: 1.1
        )
        drawLabel(node.title, at: p, in: context, color: Color(hex: 0xF6EAD2).opacity(0.95), fontSize: 11)
    }

    /// Draws sim-space-anchored text at a screen-constant size — resets to a
    /// pure translation (no scale) so zooming the camera never shrinks or
    /// enlarges labels the way it correctly does the bodies themselves.
    private func drawLabel(_ text: String, at simPoint: CGPoint, in context: GraphicsContext,
                           color: Color, fontSize: CGFloat) {
        let screenPoint = simPoint.applying(context.transform)
        var textCtx = context
        textCtx.transform = CGAffineTransform(translationX: screenPoint.x, y: screenPoint.y)
        textCtx.draw(
            Text(text).font(Theme.mono(fontSize)).foregroundColor(color),
            at: CGPoint(x: 15, y: -13), anchor: .leading
        )
    }

    /// The single most concrete "work in flight" signal in the whole system:
    /// a live opencode/Claude Code tool call, swinging in from beyond the
    /// outer belt and back out — not Jarvis's own state (the star already
    /// carries that), a genuinely separate session doing something real.
    /// Labelled with its actual tool name and target, capped at 5 so a burst
    /// of concurrent sessions never turns into clutter.
    private func drawActivityComets(context: inout GraphicsContext, now: Double) {
        let calls = store.pendingToolCalls.prefix(5)
        guard !calls.isEmpty else { return }
        let c = sim.center
        for call in calls {
            let seed = Double(abs(call.id.hashValue % 1000)) / 1000.0
            let angle = seed * 2 * .pi
            // Reduce-motion gets a fixed resting position, not a frozen swing —
            // this is ambient decoration, and DESIGN.md reserves continuous
            // motion for the calm, deliberate kind only.
            let travel: Double
            if reduceMotion {
                travel = 0.5
            } else {
                let phase = (now * 0.25 + seed * 6.28).truncatingRemainder(dividingBy: 2 * .pi)
                travel = (sin(phase) + 1) / 2
            }
            let r = lerp(sim.maxRadius * 1.05, sim.maxRadius * 0.55, travel)
            let p = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r * sim.tilt)
            let alpha = 0.35 + travel * 0.5

            context.fill(
                Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                with: .color(Theme.cOpencode.opacity(alpha))
            )
            drawLabel("\(call.tool) \(call.summary)", at: p, in: context,
                      color: Theme.cOpencode.opacity(0.8), fontSize: 10)
        }
    }
}

/// SwiftUI's Canvas has no scroll-wheel recognizer of its own — same
/// "drop to AppKit for real OS behaviour" precedent as OverlayWindow's raw
/// NSWindow. A local event monitor observes scroll-wheel events without ever
/// consuming them, so it can drive panning while every existing click/drag/
/// hover gesture on the Canvas keeps working completely untouched.
private struct ScrollWheelObserver: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view, onScroll: onScroll)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onScroll: ((CGFloat, CGFloat) -> Void)?
        private weak var hostView: NSView?
        private var monitor: Any?

        func attach(to view: NSView, onScroll: @escaping (CGFloat, CGFloat) -> Void) {
            hostView = view
            self.onScroll = onScroll
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let host = self.hostView, host.window != nil else { return event }
                let pointInView = host.convert(event.locationInWindow, from: nil)
                if host.bounds.contains(pointInView) {
                    self.onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
                }
                return event // always let the event continue its normal dispatch
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
