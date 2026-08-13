import SwiftUI

/// A deliberate, literal clone of a reference HUD dial the user supplied —
/// every chrome colour below is pixel-sampled from their reference images
/// (not approximated), overriding this project's own restrained-observatory
/// palette for this one object by explicit, repeated instruction. What's
/// generative rather than copied: the reference is itself a live animation
/// (six supplied frames each show a different waveform silhouette and a
/// different dot-trail shape from the same underlying instrument), so the
/// centre content is reproduced as the same kind of live, morphing signal —
/// tied to Jarvis's real state for energy, never for colour.
///
/// One implementation, two call sites: the desktop overlay widget
/// (`OverlayWindow.swift`) and the main dashboard's orrery centrepiece
/// (`SpaceView.swift`) both call `HeroDial.draw`, at their own centre/radius,
/// so the two can never drift apart into two slightly-different dials.
enum HeroDial {
    // MARK: - Pixel-sampled chrome (from the reference dial, clockwise from 12 o'clock, 45° each)
    private static let ringSegments: [(start: Double, end: Double, color: Color)] = [
        (0, 45, Color(hex: 0xFF4B4B)),    // red
        (45, 90, Color(hex: 0xFFA828)),   // orange
        (90, 135, Color(hex: 0x00FFAA)),  // turquoise
        (135, 180, Color(hex: 0x4D9CFF)), // blue
        (180, 225, Color(hex: 0x05DBE9)), // cyan
        (225, 270, Color(hex: 0xB7FF54)), // lime
        (270, 315, Color(hex: 0xFFCC2A)), // yellow
        (315, 360, Color(hex: 0x8DFF55)), // green
    ]
    private static let tickColor = Color(hex: 0x7A3232)
    private static let creamColor = Color(hex: 0xFFC7A8)
    private static let viewportColor = Color(hex: 0x212121)
    private static let glareColor = Color(hex: 0x423D3D)
    private static let waveColor = Color(hex: 0xFF4B4B)
    // Sprite-only palette (not part of the cloned chrome): steel and wood for
    // the forge, sparks borrowed from the ring's own orange for cohesion.
    private static let steelColor = Color(hex: 0x6B6B6B)
    private static let handleColor = Color(hex: 0x8B5A2B)
    private static let sparkColor = Color(hex: 0xFFA828)
    // The dense tick ring's own highlighted window — measured at r=635 across
    // all six frames, consistently 100.7°-149.3°.
    private static let tickCreamStart = 100.7
    private static let tickCreamEnd = 149.3
    private static let tickCount = 189 // pitch measured at 1.9047° — 360/1.9047 = 189

    /// `includeBackdrop` is off by default: the desktop widget's window is
    /// transparent and needs its own soft black vignette behind the dial;
    /// `SpaceView` already has real background content (other orbiting
    /// bodies drawn just before this call), so painting a black smudge over
    /// them there would be a visible bug, not a style choice.
    static func draw(context: inout GraphicsContext, center c: CGPoint, R: CGFloat, now: Double,
                      state: JarvisState, daemonAlive: Bool, includeBackdrop: Bool = false) {
        if includeBackdrop {
            drawBackdrop(context: &context, c: c, R: R)
        }
        drawRingSegments(context: &context, c: c, R: R, now: now)
        drawTicksAndCreamArcs(context: &context, c: c, R: R, now: now)
        drawViewportAndGlare(context: &context, c: c, R: R)
        drawStateSprite(context: &context, c: c, R: R, now: now, state: state, daemonAlive: daemonAlive)
    }

    /// A circle, not a box — the backing shape follows the dial's own round
    /// silhouette. A hard-edged disc left its own crisp circular seam visible
    /// just past the ring's glow, which read as a mistake rather than a
    /// backdrop, so this fades out over its outer ~18% instead of cutting off —
    /// a soft vignette sitting behind the dial, not a shape of its own.
    private static func drawBackdrop(context: inout GraphicsContext, c: CGPoint, R: CGFloat) {
        let bgR = R * 1.15
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - bgR, y: c.y - bgR, width: bgR * 2, height: bgR * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0.3), location: 0),
                    .init(color: .black.opacity(0.3), location: 0.82),
                    .init(color: .black.opacity(0), location: 1),
                ]),
                center: c, startRadius: 0, endRadius: bgR
            )
        )
    }

    // MARK: - Outer 8-colour ring

    /// Measured on the reference: solid ring core spans r=698-707 at R=702
    /// (thickness ratio 0.0128R), with a soft ~20px glow tail each side
    /// (ratio ~0.024R), and a real inter-segment gap of ~1.4° centred on
    /// each 45° boundary — not the wider, guessed values from the first pass.
    /// Colour and position are the exact clone; the one liberty taken for
    /// "living" is a very slow, faint breathing pulse on the glow itself —
    /// the ring never changes hue or moves, it just isn't a static bitmap.
    private static func drawRingSegments(context: inout GraphicsContext, c: CGPoint, R: CGFloat, now: Double) {
        let lineWidth = R * 0.0128
        let breathe = 0.85 + 0.15 * sin(now * 0.35)
        for seg in ringSegments {
            var path = Path()
            path.addArc(center: c, radius: R,
                        startAngle: .degrees(seg.start - 90 + 0.7),
                        endAngle: .degrees(seg.end - 90 - 0.7),
                        clockwise: false)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: seg.color, radius: R * 0.024 * CGFloat(breathe)))
                layer.stroke(path, with: .color(seg.color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
    }

    // MARK: - Dense tick ring + cream highlight sector

    /// Tick geometry measured directly: radial lines from 0.8875R to 0.9402R,
    /// 189 of them (1.9047° pitch), ~3.3px chord width at R=702 (0.0047R).
    ///
    /// "Living" here means real independent motion, the way the actual
    /// animejs engine this dial is drawn from runs each of its own layers on
    /// its own never-synchronized period rather than one rigid disc: the
    /// tick ring turns at its own slow rate, and each of the three highlight
    /// arcs turns at its own slightly different slow rate too, so the whole
    /// assembly is always gently drifting in and out of alignment with
    /// itself rather than spinning as one frozen pattern. Each tick also
    /// carries its own faint shimmer phase, like a circuit with current
    /// moving through it — all on top of the exact sampled colour/geometry,
    /// none of it changing what the dial fundamentally looks like.
    private static func drawTicksAndCreamArcs(context: inout GraphicsContext, c: CGPoint, R: CGFloat, now: Double) {
        let inner = R * 0.8875
        let outer = R * 0.9402

        var ticks = context
        ticks.translateBy(x: c.x, y: c.y)
        ticks.rotate(by: .degrees(now * 2.4))
        ticks.translateBy(x: -c.x, y: -c.y)
        for i in 0..<tickCount {
            let angle = Double(i) / Double(tickCount) * 360
            let inCream = angle >= tickCreamStart && angle <= tickCreamEnd
            let rad: Double = (angle - 90) * .pi / 180
            let cosR = CGFloat(cos(rad))
            let sinR = CGFloat(sin(rad))
            let p0 = CGPoint(x: c.x + cosR * inner, y: c.y + sinR * inner)
            let p1 = CGPoint(x: c.x + cosR * outer, y: c.y + sinR * outer)
            var path = Path()
            path.move(to: p0)
            path.addLine(to: p1)
            let shimmer = 0.72 + 0.28 * sin(now * 0.6 + Double(i) * 0.17)
            let base = inCream ? creamColor : tickColor
            ticks.stroke(path, with: .color(base.opacity(shimmer)), style: StrokeStyle(lineWidth: R * 0.0047))
        }

        // Three genuinely distinct highlight arcs, not four evenly-spaced
        // guesses — each one's own radius, angular span, dash pattern and
        // stroke width measured directly off the reference (radius histogram
        // of cream pixels, then per-radius angular on/off scan):
        //   innermost (0.7493R): dashed, ~7.4° dash / ~7.2° gap, 95.4°-154.8°
        //   middle    (0.7977R): solid, 96.8°-153.2°
        //   outer     (0.8490R): solid, 98.8°-151.6°, right before the tick band
        // Each turns at its own rate (1.8/2.1/2.7 °/s) — close to the tick
        // ring's 2.4°/s but never locked to it, so the layered arcs visibly
        // slide past one another over the course of a minute or two.
        func rotatedLayer(_ rate: Double) -> GraphicsContext {
            var layer = context
            layer.translateBy(x: c.x, y: c.y)
            layer.rotate(by: .degrees(now * rate))
            layer.translateBy(x: -c.x, y: -c.y)
            return layer
        }

        let innerArcR = R * 0.7493
        var innerPath = Path()
        innerPath.addArc(center: c, radius: innerArcR,
                         startAngle: .degrees(95.4 - 90), endAngle: .degrees(154.8 - 90), clockwise: false)
        rotatedLayer(1.8).stroke(innerPath, with: .color(creamColor.opacity(0.9)),
                                style: StrokeStyle(lineWidth: R * 0.0043,
                                                    dash: [innerArcR * 0.129, innerArcR * 0.124]))

        let midArcR = R * 0.7977
        var midPath = Path()
        midPath.addArc(center: c, radius: midArcR,
                      startAngle: .degrees(96.8 - 90), endAngle: .degrees(153.2 - 90), clockwise: false)
        rotatedLayer(2.1).stroke(midPath, with: .color(creamColor.opacity(0.85)), style: StrokeStyle(lineWidth: R * 0.010))

        let outerArcR = R * 0.8490
        var outerPath = Path()
        outerPath.addArc(center: c, radius: outerArcR,
                         startAngle: .degrees(98.8 - 90), endAngle: .degrees(151.6 - 90), clockwise: false)
        rotatedLayer(2.7).stroke(outerPath, with: .color(creamColor.opacity(0.8)), style: StrokeStyle(lineWidth: R * 0.0085))
    }

    // MARK: - Dark viewport + soft glass glare

    /// The flat dark fill is NOT a small inset circle — a radial profile
    /// through a tick gap reads flat #212121 continuously from the centre
    /// out to where the ring's own glow begins (~0.955R). Filling only to
    /// 0.856R (an earlier guess) left the tick band floating over whatever
    /// sits behind it instead of the dark disc it belongs on.
    ///
    /// The glare itself isn't a centred blob either: it's a soft arc-shaped
    /// highlight following the circle's own curvature, measured at radius
    /// ~0.705R spanning 260°-347° (upper-left), like light catching a curved
    /// glass surface — reproduced as a blurred stroked arc, not a gradient ellipse.
    private static func drawViewportAndGlare(context: inout GraphicsContext, c: CGPoint, R: CGFloat) {
        let viewportR = R * 0.955
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - viewportR, y: c.y - viewportR, width: viewportR * 2, height: viewportR * 2)),
            with: .color(viewportColor)
        )
        context.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: CGRect(x: c.x - viewportR, y: c.y - viewportR,
                                                   width: viewportR * 2, height: viewportR * 2)))
            layer.addFilter(.blur(radius: R * 0.028))
            var glarePath = Path()
            glarePath.addArc(center: c, radius: R * 0.705,
                             startAngle: .degrees(260 - 90), endAngle: .degrees(347 - 90), clockwise: false)
            layer.stroke(glarePath, with: .color(glareColor.opacity(0.85)),
                        style: StrokeStyle(lineWidth: R * 0.071, lineCap: .round))
        }
    }

    // MARK: - Centre signal: a pixel-art vignette of what Jarvis is actually doing

    private static func energy(for state: JarvisState) -> Double {
        switch state {
        case .idle: return 0.32
        case .listening: return 0.48
        case .thinking: return 0.72
        case .working: return 0.9
        case .speaking: return 0.82
        }
    }

    /// Deterministic, re-computed each call rather than `Int.random` — a
    /// sprite needs the same "random" value to hold steady for an entire
    /// animation step, not re-roll every frame.
    private static func pseudoRandom(_ seed: Int) -> Double {
        var x = seed
        x = (x ^ (x >> 15)) &* 2246822519
        x = (x ^ (x >> 13)) &* 3266489917
        x = x ^ (x >> 16)
        return Double(x & 0xFFFF) / Double(0xFFFF)
    }

    /// One state, one small living scene — not a generic meter reused across
    /// every action. Each sprite is deliberately blocky/stepped (quantized
    /// animation phases, hard-edged rects) for the pixel-art, not smoothly
    /// interpolated, feel the reference's own instrument never asked for but
    /// this addition explicitly does.
    private static func drawStateSprite(context: inout GraphicsContext, c: CGPoint, R: CGFloat, now: Double,
                                         state: JarvisState, daemonAlive: Bool) {
        let effective: JarvisState = daemonAlive ? state : .idle
        let e = daemonAlive ? energy(for: effective) : 0.22

        switch effective {
        case .idle:      drawIdleSprite(context: &context, c: c, R: R, now: now, e: e)
        case .listening: drawListeningSprite(context: &context, c: c, R: R, now: now, e: e)
        case .thinking:  drawThinkingSprite(context: &context, c: c, R: R, now: now, e: e)
        case .working:   drawWorkingSprite(context: &context, c: c, R: R, now: now, e: e)
        case .speaking:  drawSpeakingSprite(context: &context, c: c, R: R, now: now, e: e)
        }
    }

    /// A calm breathing dot, layered: the core pulse (three discrete sizes),
    /// a stepped expanding heartbeat ring timed to it, and a handful of
    /// slow-drifting ambient dust motes that each get a fresh pseudo-random
    /// position every few seconds — depth through layering, still all
    /// stepped/quantized rather than smoothly tweened.
    private static func drawIdleSprite(context: inout GraphicsContext, c: CGPoint, R: CGFloat, now: Double, e: Double) {
        let breathPeriod = 1.8
        let step = Int(now / (breathPeriod / 3)) % 3
        let sizes: [CGFloat] = [0.10, 0.13, 0.16]
        let r = R * sizes[step]

        // Heartbeat ring: expands through 4 stepped radii each breath cycle, fading out.
        let ringStep = Int(now.truncatingRemainder(dividingBy: breathPeriod) / (breathPeriod / 4))
        let ringR = R * (0.12 + CGFloat(ringStep) * 0.045)
        context.stroke(
            Path(ellipseIn: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2)),
            with: .color(waveColor.opacity(0.22 - Double(ringStep) * 0.05)),
            style: StrokeStyle(lineWidth: R * 0.006)
        )

        // Ambient dust motes: 4 slow points, each re-seeded to a new spot every ~4s.
        let moteCycle = Int(now / 4.0)
        for i in 0..<4 {
            let seed = i * 97 + moteCycle
            let a = pseudoRandom(seed) * 2 * .pi
            let dist = R * (0.22 + CGFloat(pseudoRandom(seed + 500)) * 0.16)
            let visible = (Int(now / 0.9) + i) % 4 != 0 // each mote blinks off roughly a quarter of the time
            guard visible else { continue }
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * dist, y: c.y + CGFloat(sin(a)) * dist)
            let s = R * 0.012
            context.fill(Path(CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                        with: .color(waveColor.opacity(0.3)))
        }

        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .color(waveColor.opacity(0.5)))
    }

    /// A 7-bar equalizer over expanding sound-ripple rings — the bars alone
    /// read as a meter, the ripples sell "hearing something arrive."
    private static func drawListeningSprite(context: inout GraphicsContext, c: CGPoint, R: CGFloat, now: Double, e: Double) {
        let ripplePeriod = 1.1
        let rippleStep = Int(now.truncatingRemainder(dividingBy: ripplePeriod) / (ripplePeriod / 4))
        for k in 0..<2 {
            let phase = (rippleStep + k * 2) % 4
            let ringR = R * (0.14 + CGFloat(phase) * 0.10)
            context.stroke(
                Path(ellipseIn: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2)),
                with: .color(waveColor.opacity(0.18 - Double(phase) * 0.04)),
                style: StrokeStyle(lineWidth: R * 0.005)
            )
        }

        let unit = R * 0.045
        let step = Int(now / (0.22 / max(e, 0.3)))
        let barCount = 7
        for i in 0..<barCount {
            let level = 1 + Int(pseudoRandom(i * 1013 + step) * 4.0 * e + 0.5)
            let clamped = min(5, max(1, level))
            let h = CGFloat(clamped) * unit
            let x = c.x + CGFloat(i - barCount / 2) * unit * 1.5
            let rect = CGRect(x: x - unit * 0.35, y: c.y + unit * 2.5 - h, width: unit * 0.7, height: h)
            context.fill(Path(rect), with: .color(waveColor.opacity(0.55 + Double(clamped) * 0.08)))
        }
    }

    /// A small rotating gear over the classic three-dot "..." — the gear
    /// sells active processing, the dots sell "still going."
    private static func drawThinkingSprite(context: inout GraphicsContext, c: CGPoint, R: CGFloat, now: Double, e: Double) {
        let gearCenter = CGPoint(x: c.x, y: c.y - R * 0.16)
        let gearR = R * 0.10
        let stepAngles = 16
        let gearStepDur = 0.09 / max(e, 0.3)
        let gearAngle = Double(Int(now / gearStepDur) % stepAngles) * (360.0 / Double(stepAngles))

        var gear = context
        gear.translateBy(x: gearCenter.x, y: gearCenter.y)
        gear.rotate(by: .degrees(gearAngle))
        gear.translateBy(x: -gearCenter.x, y: -gearCenter.y)
        let toothCount = 6
        for t in 0..<toothCount {
            let a = Double(t) / Double(toothCount) * 2 * .pi
            let toothLen = gearR * 0.5
            let inner = CGPoint(x: gearCenter.x + CGFloat(cos(a)) * gearR, y: gearCenter.y + CGFloat(sin(a)) * gearR)
            let s = toothLen
            gear.fill(Path(CGRect(x: inner.x - s / 2, y: inner.y - s / 2, width: s, height: s)),
                     with: .color(waveColor.opacity(0.55)))
        }
        gear.fill(Path(ellipseIn: CGRect(x: gearCenter.x - gearR, y: gearCenter.y - gearR, width: gearR * 2, height: gearR * 2)),
                 with: .color(waveColor.opacity(0.75)))
        gear.fill(Path(ellipseIn: CGRect(x: gearCenter.x - gearR * 0.35, y: gearCenter.y - gearR * 0.35, width: gearR * 0.7, height: gearR * 0.7)),
                 with: .color(viewportColor))

        let unit = R * 0.075
        let dotStep = Int(now / (0.42 / max(e, 0.3))) % 3
        let dotsY = c.y + R * 0.17
        for i in 0..<3 {
            let lit = i == dotStep
            let size = unit * (lit ? 1.0 : 0.7)
            let x = c.x + CGFloat(i - 1) * unit * 1.8
            let rect = CGRect(x: x - size / 2, y: dotsY - size / 2, width: size, height: size)
            context.fill(Path(rect), with: .color(waveColor.opacity(lit ? 0.9 : 0.35)))
        }
    }

    /// The sword-maker, properly layered: anvil, a glowing half-forged blade
    /// resting on it (brighter with each completed strike), an arm carrying
    /// the hammer through four stepped angles, a spark burst with real
    /// (if brief) flight motion on the exact strike frame, and faint heat
    /// shimmer drifting off the work — a small scene, not a single icon.
    private static func drawWorkingSprite(context: inout GraphicsContext, c: CGPoint, R: CGFloat, now: Double, e: Double) {
        let unit = R * 0.05

        let stepDur = 0.16 / max(e, 0.35)
        let stepIndex = Int(now / stepDur)
        let step = stepIndex % 4
        let progress = CGFloat((now.truncatingRemainder(dividingBy: stepDur)) / stepDur)
        // A brief, decaying jolt on the anvil itself right as the hammer
        // lands — the difference between an animation and an impact.
        let shake: CGFloat = step == 2 ? sin(Double(progress) * .pi) * unit * 0.12 : 0
        let anvilTop = c.y + unit * 0.5 + shake

        // Anvil: wide face, narrower stem, a thin highlight along the top edge.
        context.fill(Path(CGRect(x: c.x - unit * 3, y: anvilTop, width: unit * 6, height: unit * 1.3)),
                    with: .color(steelColor))
        context.fill(Path(CGRect(x: c.x - unit * 3, y: anvilTop, width: unit * 6, height: unit * 0.22)),
                    with: .color(Color.white.opacity(0.25)))
        context.fill(Path(CGRect(x: c.x - unit * 1.1, y: anvilTop + unit * 1.3, width: unit * 2.2, height: unit * 1.4)),
                    with: .color(steelColor.opacity(0.9)))

        // 0° = hanging straight down, head at the anvil (the struck pose) —
        // raised swings the head up and back, not the reverse.
        let angles: [Double] = [-65, -30, 0, 0] // raised, mid-swing, struck, hold
        let angle = angles[step]
        let pivot = CGPoint(x: c.x + unit * 2.6, y: anvilTop - unit * 3.6)
        let handleLen = unit * 3.2

        // The workpiece: a hot blade that visibly grows more finished across
        // 8 strikes before the cycle starts over, so this reads as building
        // toward something rather than looping in place.
        let strikeCount = (stepIndex / 4) % 8
        let bladeProgress = CGFloat(strikeCount + 1) / 8
        let bladeLen = unit * 2.6 * bladeProgress
        let bladeGlow = 0.55 + 0.35 * sin(now * 3)
        context.fill(Path(CGRect(x: c.x - unit * 0.4, y: anvilTop - unit * 0.28, width: bladeLen, height: unit * 0.5)),
                    with: .color(sparkColor.opacity(bladeGlow)))

        // Faint heat shimmer: three thin bands drifting upward off the blade, looping.
        for i in 0..<3 {
            let localPhase = (now * 0.6 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            let y = anvilTop - unit * 0.4 - CGFloat(localPhase) * unit * 3
            let alpha = (1 - localPhase) * 0.12
            context.fill(Path(CGRect(x: c.x - unit * 0.3 + CGFloat(i) * unit * 0.5, y: y, width: unit * 0.3, height: unit * 0.9)),
                        with: .color(Color.white.opacity(alpha)))
        }

        // Arm + hammer share the same swing so the hammer reads as carried,
        // not floating: a short forearm from a fixed shoulder to the pivot.
        var swing = context
        swing.translateBy(x: pivot.x, y: pivot.y)
        swing.rotate(by: .degrees(angle))
        swing.translateBy(x: -pivot.x, y: -pivot.y)
        let shoulder = CGPoint(x: pivot.x + unit * 1.6, y: pivot.y - unit * 0.6)
        swing.fill(Path(CGRect(x: min(shoulder.x, pivot.x), y: pivot.y - unit * 0.5,
                               width: abs(shoulder.x - pivot.x) + unit * 0.5, height: unit * 0.7)),
                  with: .color(handleColor.opacity(0.85)))
        // Handle hangs down from the pivot; the head sits at its far end,
        // landing on the anvil exactly when angle is back to 0.
        swing.fill(Path(CGRect(x: pivot.x - unit * 0.22, y: pivot.y, width: unit * 0.44, height: handleLen)),
                  with: .color(handleColor))
        swing.fill(Path(CGRect(x: pivot.x - unit * 1.1, y: pivot.y + handleLen - unit * 0.3, width: unit * 2.2, height: unit * 1.1)),
                  with: .color(steelColor))

        // Sparks on the exact "struck" step, with real flight: they travel
        // outward across the step's own duration rather than popping in fixed.
        if step == 2 {
            let impact = CGPoint(x: pivot.x, y: anvilTop)
            for i in 0..<9 {
                let a = Double(i) / 9.0 * .pi + pseudoRandom(i + strikeCount * 13) * 0.5
                let maxDist = unit * (1.4 + CGFloat(pseudoRandom(i + 50)) * 1.2)
                let dist = maxDist * progress
                let drop = progress * progress * unit * 0.6 // a little gravity as they arc out
                let p = CGPoint(x: impact.x + CGFloat(cos(a + .pi)) * dist,
                                y: impact.y - abs(CGFloat(sin(a))) * dist + drop)
                let s = unit * (0.42 - progress * 0.2)
                let warm = pseudoRandom(i + 900) > 0.5 ? sparkColor : Color.white
                context.fill(Path(CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                            with: .color(warm.opacity(0.95 * Double(1 - progress * 0.6))))
            }
        }
    }

    /// A talking face: eyes with eyebrows that lift on the wider mouth
    /// shapes, and a real 4-shape viseme cycle (closed smile → small → medium
    /// → wide) chosen pseudo-randomly per step rather than a flat on/off
    /// toggle, plus a couple of emphasis lines beside a wide-open mouth.
    private static func drawSpeakingSprite(context: inout GraphicsContext, c: CGPoint, R: CGFloat, now: Double, e: Double) {
        let unit = R * 0.09
        let stepDur = 0.2 / max(e, 0.4)
        let step = Int(now / stepDur)
        let shape = Int(pseudoRandom(step) * 4) // 0 closed, 1 small, 2 medium, 3 wide
        let browLift: CGFloat = shape >= 2 ? -unit * 0.25 : 0

        // A faint head-bob riding the mouth shape itself — a wider mouth
        // nods the whole face down a touch, the way a real talking head
        // never holds perfectly still.
        var context = context
        context.translateBy(x: 0, y: CGFloat(shape) * unit * 0.05)

        for side: CGFloat in [-1, 1] {
            let eyeX = c.x + side * unit * 2.2
            context.fill(Path(CGRect(x: eyeX - unit * 0.25, y: c.y - unit * 1.6, width: unit * 0.5, height: unit * 0.5)),
                        with: .color(waveColor.opacity(0.8)))
            context.fill(Path(CGRect(x: eyeX - unit * 0.35, y: c.y - unit * 2.15 + browLift, width: unit * 0.7, height: unit * 0.2)),
                        with: .color(waveColor.opacity(0.6)))
        }

        switch shape {
        case 0:
            var smile = Path()
            smile.move(to: CGPoint(x: c.x - unit * 1.6, y: c.y + unit * 1.0))
            smile.addQuadCurve(to: CGPoint(x: c.x + unit * 1.6, y: c.y + unit * 1.0),
                              control: CGPoint(x: c.x, y: c.y + unit * 2.0))
            context.stroke(smile, with: .color(waveColor.opacity(0.85)),
                          style: StrokeStyle(lineWidth: unit * 0.4, lineCap: .round))
        default:
            let scale = CGFloat(shape) / 3.0
            let w = unit * (1.4 + scale * 1.4), h = unit * (0.5 + scale * 1.3)
            context.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y + unit * 0.6, width: w, height: h)),
                        with: .color(waveColor.opacity(0.85)))
            if shape == 3 {
                for side: CGFloat in [-1, 1] {
                    var line = Path()
                    line.move(to: CGPoint(x: c.x + side * (w / 2 + unit * 0.3), y: c.y + unit * 1.0))
                    line.addLine(to: CGPoint(x: c.x + side * (w / 2 + unit * 0.9), y: c.y + unit * 0.8))
                    context.stroke(line, with: .color(waveColor.opacity(0.5)), style: StrokeStyle(lineWidth: unit * 0.15, lineCap: .round))
                }
            }
        }
    }
}
