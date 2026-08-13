import Foundation
import CoreGraphics

/// One document orbiting the Jarvis core. Reference type on purpose: hundreds
/// of these advance every frame and a class avoids copying the array each step.
final class OrbitNode {
    let id: String
    let source: String
    let title: String
    let ring: Int
    let radius: CGFloat        // own orbital radius (ring radius + belt jitter)
    let speed: Double          // radians per frame
    let dotSize: CGFloat
    let shade: Double          // subtle per-body brightness variance
    var angle: Double
    var x: CGFloat = 0
    var y: CGFloat = 0
    /// Frames since this body was placed. Newly reconciled bodies render at a
    /// fixed low opacity for their first ~36 frames instead of popping in at
    /// full brightness — the "settle in" the whole belt already reads as calm.
    var age: Int = 0
    var isSettling: Bool { age < 36 }

    /// Per-body phase and amplitude for the ambient radius/angle wobble
    /// layered on top of the deterministic orbit — fixed at construction so
    /// each body drifts at its own, never-synchronized pace, the way a real
    /// organism's parts never move in perfect lockstep.
    let wobblePhase: Double
    let wobbleAmp: Double

    init(doc: DocNode, ring: Int, radius: CGFloat, speed: Double,
         angle: Double, dotSize: CGFloat, shade: Double) {
        self.id = doc.id
        self.source = doc.source
        self.title = doc.title
        self.ring = ring
        self.radius = radius
        self.speed = speed
        self.angle = angle
        self.dotSize = dotSize
        self.shade = shade
        self.wobblePhase = Double.random(in: 0...(2 * .pi))
        self.wobbleAmp = Double.random(in: 0.6...1.4)
    }

    /// Knowledge-graph entities ride this same generic body so hover/
    /// selection/hit-testing are shared with docs for free — `source ==
    /// "knowledge"` is all any other code needs to check to tell them apart.
    /// `ring` has no meaning here (nothing reads it beyond construction even
    /// for docs); -1 is just a clear "not a doc band" sentinel.
    init(entity: KGEntity, radius: CGFloat, speed: Double, angle: Double, dotSize: CGFloat, shade: Double) {
        self.id = entity.id
        self.source = "knowledge"
        self.title = entity.name
        self.ring = -1
        self.radius = radius
        self.speed = speed
        self.angle = angle
        self.dotSize = dotSize
        self.shade = shade
        self.wobblePhase = Double.random(in: 0...(2 * .pi))
        self.wobbleAmp = Double.random(in: 0.6...1.4)
    }
}

/// One of Jarvis's own scheduled routines — the innermost ring, closest to
/// the star, since these are Jarvis's own actions rather than memory.
struct CronTick: Identifiable {
    var id: String { job.id }
    let job: CronJob
    let angle: Double
}

/// An orrery, not a force graph. Jarvis is the star; each memory source is a
/// concentric orbital band; every indexed document is a body travelling that
/// band. Bodies are distributed evenly around the circumference (staggered by
/// index, the way a real orbit visualization spaces its satellites) and the
/// whole system is squashed on Y so it reads as a system seen at an angle
/// rather than flat concentric circles.
///
/// Periods follow Kepler's ordering (inner bands sweep faster than outer) but
/// are stretched far slower than any demo orrery: the outermost band takes
/// about five minutes to come around. This runs on screen all day and must
/// never pull the eye.
final class OrbitalSystem: ObservableObject {
    struct Ring {
        let source: String
        let radius: CGFloat
        let count: Int
        let labelAngle: Double
    }

    private(set) var nodes: [OrbitNode] = []
    private(set) var rings: [Ring] = []

    /// Bands run innermost to outermost. Ordering by population puts the lone
    /// voice memory close to the star and the 270-document opencode history
    /// out wide, where it reads as a dense belt instead of a crowded core.
    let bandOrder = ["voice", "context", "vault", "opencode"]

    var center: CGPoint = .zero
    var maxRadius: CGFloat = 240
    var reduceMotion = false

    /// Isometric squash on Y. Shallower than a true 65° camera so the system
    /// keeps real vertical presence instead of flattening into a ribbon.
    let tilt: CGFloat = 0.54

    private var coreSpin: Double = 0
    var coreAngle: Double { coreSpin }

    /// Ambient clock for the organic wobble layered on the deterministic
    /// orbit — a slow, real clock rather than a per-node accumulator, so
    /// every body's wobble stays in the same slow "breathing" register even
    /// though each one's phase and amplitude differ.
    private var wobbleClock: Double = 0
    var ambientClock: Double { wobbleClock }

    /// Jarvis's own scheduled routines — a small, effectively-static set, so
    /// unlike `nodes` there's no reconcile-with-settle-in dance: the whole
    /// ring is just recomputed from the latest jobs each time, which is
    /// imperceptibly cheap at this size and keeps angles stable as long as
    /// the jobs array's own order is stable.
    private(set) var cronTicks: [CronTick] = []
    /// Pushed out from its original 0.14 to clear the hero dial (below),
    /// which now needs real room at the centre instead of the old small
    /// amber star's footprint.
    var cronRingRadius: CGFloat { maxRadius * 0.40 }
    private var cronSpin: Double = 0
    var cronRingAngle: Double { cronSpin }

    /// The dial's own target radius — HeroDial's tick band and cream arcs
    /// were tuned for a dedicated window, and alias into mush if squeezed
    /// into the old ~78pt corona footprint. This gives it real presence as
    /// the centrepiece it's meant to be; the doc bands and cron ring below
    /// are laid out to clear it, not the other way around.
    var heroDialRadius: CGFloat { maxRadius * 0.32 }

    /// Knowledge-graph entities are Jarvis's own synthesized understanding —
    /// same category as the cron ring (Jarvis's own actions), not raw
    /// external memory — so they sit in the gap between the cron ring (0.40)
    /// and the innermost doc band (voice, 0.50), not squeezed against the
    /// densely-jittered outer opencode belt (0.93 + up to 15pt jitter, which
    /// already uses nearly all the room out to maxRadius on its own).
    var knowledgeRingRadius: CGFloat { maxRadius * 0.45 }

    /// Keyed by entity name (not id) since `KGRelation.source`/`.target`
    /// reference entity names directly — this is what lets SpaceView resolve
    /// a relation's two endpoints to draw a connecting thread between them.
    private(set) var entityNodesByName: [String: OrbitNode] = [:]

    /// The knowledge graph's own relations — same shape as `cronTicks`: a
    /// small, effectively-static set just recomputed each call, not diffed
    /// frame-by-frame.
    private(set) var relations: [KGRelation] = []

    func setCrons(_ jobs: [CronJob]) {
        cronTicks = jobs.enumerated().map { i, job in
            CronTick(job: job, angle: Double(i) / Double(max(jobs.count, 1)) * 2 * .pi)
        }
    }

    func setRelations(_ rels: [KGRelation]) {
        relations = rels
    }

    /// Bodies are small and always moving, so aiming at one is genuinely hard.
    /// While the cursor is near a body the whole system eases down to a crawl,
    /// which makes it clickable without ever fully freezing (a hard stop reads
    /// as a bug). Eased rather than switched so the change is never jarring.
    var wantsSlowMotion = false
    private var speedScale: Double = 1.0

    func layout(size: CGSize, helmInset: CGSize, railInset: CGFloat) {
        // The star sits in the open lane between the Helm and the Log rail, so
        // the system is never buried under an instrument panel.
        let laneStart = helmInset.width
        let laneWidth = max(320, size.width - laneStart - railInset)
        center = CGPoint(x: laneStart + laneWidth / 2, y: size.height * 0.48)
        let horizontal = laneWidth / 2 - 30
        let vertical = (size.height / 2 - 40) / tilt
        // No floor on purpose: a floor would force the outer belt to run under
        // the Log rail on a narrow lane. Containment beats size.
        maxRadius = min(min(horizontal, vertical), 460)
        rebuildRings()
        repositionNodes()
    }

    private func ringRadius(_ index: Int) -> CGFloat {
        // Shifted out from [0.26, 0.47, 0.68, 0.93] so the innermost band
        // clears the cron ring (0.40), which itself clears the larger hero
        // dial (0.32) — the whole stack now lays out around the centrepiece
        // instead of overlapping it.
        let fractions: [CGFloat] = [0.50, 0.65, 0.78, 0.93]
        return maxRadius * fractions[min(index, fractions.count - 1)]
    }

    private func rebuildRings() {
        guard !nodes.isEmpty || !rings.isEmpty else { return }
        var counts: [String: Int] = [:]
        for n in nodes { counts[n.source, default: 0] += 1 }
        // Captions sit at the low point of their own band. Because each band
        // has a different minor axis they stack into a neat legend below the
        // star, each one still touching the ring it names.
        let labelAngles: [Double] = Array(repeating: .pi / 2, count: 4)
        rings = bandOrder.enumerated().map { i, source in
            Ring(source: source, radius: ringRadius(i),
                 count: counts[source] ?? 0, labelAngle: labelAngles[i])
        }
        // Same caption mechanism as the 4 doc bands above (all share one
        // label angle already, forming a stacked legend column) — the
        // knowledge ring gets a real caption for free, unlike the cron ring,
        // which deliberately has none.
        rings.append(Ring(source: "knowledge", radius: knowledgeRingRadius,
                           count: counts["knowledge"] ?? 0, labelAngle: .pi / 2))
    }

    /// Diffs incoming docs against the live system instead of seeding once and
    /// never touching it again. Removed ids drop their bodies; added ids are
    /// placed into their band using the same per-body math the original seed
    /// used — existing bodies never move or get repositioned, so a refresh
    /// never makes the belt jump.
    ///
    /// `vaultStatus` maps a vault doc's title to its real frontmatter status
    /// (active/spark/parked/...) so Projects and Ideas already inside the
    /// vault band read as visually distinct without a second, invented ring —
    /// they're already the same data, just sized and shaded by lifecycle.
    func reconcile(docs: [DocNode], vaultStatus: [String: String] = [:], entities: [KGEntity] = []) {
        reconcileEntities(entities)

        if docs.isEmpty {
            // A transient/partial read must never be mistaken for "everything
            // was removed" — only an intentionally empty result (no existing
            // nodes either) is a real no-op.
            return
        }

        let incomingIDs = Set(docs.map(\.id))
        let removedIDs = Set(nodes.map(\.id)).subtracting(incomingIDs)
        if !removedIDs.isEmpty {
            nodes.removeAll { removedIDs.contains($0.id) }
        }

        var byBand: [String: [DocNode]] = [:]
        for d in docs { byBand[d.source, default: []].append(d) }
        let existingIDs = Set(nodes.map(\.id))
        var existingCountByBand: [String: Int] = [:]
        for n in nodes { existingCountByBand[n.source, default: 0] += 1 }

        var added: [OrbitNode] = []
        for (index, source) in bandOrder.enumerated() {
            let members = byBand[source] ?? []
            let newMembers = members.filter { !existingIDs.contains($0.id) }
            guard !newMembers.isEmpty else { continue }
            let base = ringRadius(index)
            // A populous band spreads into a belt; a sparse one stays a clean line.
            let spread: CGFloat = members.count > 60 ? 15 : (members.count > 8 ? 6 : 0)
            let period = basePeriod(forRingRadiusFraction: base / max(maxRadius, 1))
            let existingCount = existingCountByBand[source, default: 0]
            let totalCount = existingCount + newMembers.count
            for (j, doc) in newMembers.enumerated() {
                let evenAngle = Double(existingCount + j) / Double(totalCount) * 2 * .pi
                let wobble = Double.random(in: -0.05...0.05)
                let r = base + CGFloat.random(in: -spread...spread)
                // Slight per-body period variance keeps the belt from turning
                // as one rigid disc.
                let speed = (2 * .pi / period) * Double.random(in: 0.94...1.06)
                // Vault docs with a known lifecycle status size/shade by it;
                // everything else (and vault docs with no match, e.g. Daily
                // notes) keeps the original uniform range.
                let (sizeRange, shadeRange): (ClosedRange<CGFloat>, ClosedRange<Double>) = {
                    guard source == "vault", let status = vaultStatus[doc.title] else {
                        return (1.3...2.2, 0.62...1.0)
                    }
                    switch status {
                    case "parked": return (1.0...1.3, 0.35...0.5)
                    case "active": return (1.8...2.6, 0.85...1.0)
                    default: return (1.3...1.9, 0.6...0.78)
                    }
                }()
                added.append(OrbitNode(
                    doc: doc, ring: index, radius: r, speed: speed,
                    angle: evenAngle + wobble,
                    dotSize: CGFloat.random(in: sizeRange),
                    shade: Double.random(in: shadeRange)
                ))
            }
        }

        guard !removedIDs.isEmpty || !added.isEmpty else { return }
        nodes.append(contentsOf: added)
        rebuildRings()
        repositionNodes()
    }

    /// Same "transient-empty must never mean remove everything" guard as the
    /// doc path above, and the same never-reposition-existing-bodies rule.
    /// Placed on a clean, unjittered ring (`radius: base`, no random spread)
    /// — a deliberate visual contrast with the jittered doc belts, since
    /// entities are expected to stay a much sparser set.
    private func reconcileEntities(_ entities: [KGEntity]) {
        guard !entities.isEmpty else { return }

        let incomingIDs = Set(entities.map(\.id))
        let removedIDs = Set(entityNodesByName.values.map(\.id)).subtracting(incomingIDs)
        if !removedIDs.isEmpty {
            nodes.removeAll { removedIDs.contains($0.id) }
            entityNodesByName = entityNodesByName.filter { !removedIDs.contains($0.value.id) }
        }

        let existingIDs = Set(entityNodesByName.values.map(\.id))
        let newEntities = entities.filter { !existingIDs.contains($0.id) }
        guard !removedIDs.isEmpty || !newEntities.isEmpty else { return }

        let base = knowledgeRingRadius
        let period = basePeriod(forRingRadiusFraction: base / max(maxRadius, 1))
        let existingCount = entityNodesByName.count
        let totalCount = existingCount + newEntities.count
        for (j, entity) in newEntities.enumerated() {
            let evenAngle = Double(existingCount + j) / Double(max(totalCount, 1)) * 2 * .pi
            let speed = (2 * .pi / period) * Double.random(in: 0.94...1.06)
            // More-mentioned entities read as bigger/brighter — same idea as
            // vault's lifecycle-driven size/shade, applied to mention count.
            let mentionScale = min(Double(entity.mentions), 20) / 20
            let node = OrbitNode(
                entity: entity, radius: base, speed: speed, angle: evenAngle,
                dotSize: CGFloat(1.6 + mentionScale * 1.4),
                shade: 0.6 + mentionScale * 0.4
            )
            nodes.append(node)
            entityNodesByName[entity.name] = node
        }

        rebuildRings()
        repositionNodes()
    }

    /// Frames per revolution. Kepler ordering, stretched for an all-day window:
    /// the inner band comes around in about 100 seconds, the outer in about five
    /// minutes, at 60fps.
    private func basePeriod(forRingRadiusFraction f: CGFloat) -> Double {
        let normalized = max(0.2, Double(f))
        return 6000 * pow(normalized / 0.93, 1.5)
    }

    /// Deterministic angle/radius drive the real orbit; the wobble terms are
    /// a pure cosmetic perturbation on top, small enough to read as "alive"
    /// rather than as jitter. Skipped entirely under reduce-motion rather
    /// than merely frozen, so it never even contributes a static offset.
    private func repositionNodes() {
        for n in nodes {
            if reduceMotion {
                n.x = center.x + cos(n.angle) * n.radius
                n.y = center.y + sin(n.angle) * n.radius * tilt
            } else {
                let breatheR = 1 + sin(wobbleClock + n.wobblePhase) * 0.02 * n.wobbleAmp
                let driftA = sin(wobbleClock * 0.6 + n.wobblePhase * 1.3) * 0.012 * n.wobbleAmp
                let r = n.radius * breatheR
                let a = n.angle + driftA
                n.x = center.x + cos(a) * r
                n.y = center.y + sin(a) * r * tilt
            }
        }
    }

    func step() {
        let target = wantsSlowMotion ? 0.08 : 1.0
        speedScale += (target - speedScale) * 0.12
        if !reduceMotion {
            for n in nodes {
                n.angle += n.speed * speedScale
                if n.isSettling { n.age += 1 }
            }
            coreSpin += 0.0016 * speedScale
            // Slower than any doc band — a routine ring drifting, not a memory.
            cronSpin += 0.0009 * speedScale
            wobbleClock += 0.008 * speedScale
        }
        repositionNodes()
    }

    func ringPoint(_ ring: Ring, angle: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * ring.radius,
                y: center.y + sin(angle) * ring.radius * tilt)
    }

    func nearestNode(to point: CGPoint, within radius: CGFloat = 20) -> OrbitNode? {
        var best: OrbitNode?
        var bestDist = radius
        for node in nodes {
            let d = hypot(node.x - point.x, node.y - point.y)
            if d < bestDist { bestDist = d; best = node }
        }
        return best
    }
}
