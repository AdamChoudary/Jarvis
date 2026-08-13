# Jarvis Dashboard — component plan

End-to-end spec for every component. Written after the first orrery build shipped
laggy and blurry, so each entry names the failure it is correcting.

## Root causes of the first build feeling wrong

| Symptom | Real cause | Fix |
| --- | --- | --- |
| Laggy | 326 separate `radialGradient` fills per frame, one per body, plus a full-screen gradient and 4 stroked ellipses. Every gradient is its own GPU pass. | Batch bodies into one `Path` per (cluster x depth tier). 12 solid fills per frame instead of 326 gradients. |
| Blurry | Every body was a soft radial falloff ~5px wide with no hard edge, so nothing in the field had a crisp pixel. | Bodies become solid crisp discs 1.3-2.2px. Glow is reserved for the star, the hovered body and the selected body only. |
| Flat / fake | Everything drew in one pass, so bodies at the front of the orbit rendered behind the star. | Depth-sorted painting: far half, then the star, then the near half. Bodies genuinely pass in front of and behind the sun. |
| Hard to click | 2px targets moving continuously, 13px hit radius, no hover feedback. | 20px hit radius, hover highlight with name, and the system eases to 8% speed while aiming. |

## Rendering budget (per frame)

Target: 60fps with zero dropped frames on an M1 while the voice daemon is also running.

| Pass | Ops | Notes |
| --- | --- | --- |
| Vignette | 1 gradient | Static geometry, cheap. |
| Orbit rings | 4 strokes | 1px dashed ellipses. |
| Bodies (far half) | <= 6 fills | Batched paths, solid colour. |
| Star | 4 ops | Corona gradient, 2 dashed rings, core gradient. |
| Bodies (near half) | <= 6 fills | Batched. |
| Labels | 4 text | Band captions. |
| Hover + selection | <= 6 ops | Only when something is targeted. |
| **Total** | **~31** | Down from 330+. |

## Components

### Star (Jarvis core)
Amber only when the daemon is alive; desaturates to `inkFaint` when it is not, so the
one warm signal in the app always means "awake". Corona gradient, two counter-rotating
dashed rings at 23px and 31px, solid core at 7.5px. Rings slow with the system when the
user is aiming, so the whole scene decelerates as one object.

### Orbit bands
One band per memory source, ordered by population inward to outward: voice, context,
vault, opencode. Dashed 1px ellipse in the band's own hue at 22% opacity. Tilt is a
0.54 Y-squash: shallow enough to read as a system seen at an angle, deep enough to keep
vertical presence instead of flattening to a ribbon.

### Bodies
One per indexed document. Crisp solid disc, 1.3-2.2px, coloured by band. Three depth
tiers by orbital phase (far 42% / mid 68% / near 95% opacity) give roundness without
per-body gradients. Populous bands spread into a belt (radius jitter); sparse bands stay
a clean line. Per-body period variance of +-6% keeps a belt from turning as a rigid disc.

### Hover
20px capture radius. Target brightens to near-white, gains a 1px ring, and names itself
to the right. Simultaneously the system eases to 8% speed. Easing, never switching:
a hard freeze reads as a crash.

### Selection
Beam from the star to the body (gradient, faint at the core end), bright body, amber
ring, title. Opens the Slate. Amber is reserved for exactly this, the star, and the
sidebar's live dot.

### Helm (top-left glass)
Live vitals. Numbers are monospaced and tabular so nothing shifts as values update.
Sparkline is `inkDim`, never amber.

### Log rail (right glass)
Today / Projects / Ideas. Hairline dividers between sections, none above the first.

### Slate (file inspector)
Rises from the bottom-left over the system on selection. Spring, 0.38s, no bounce.
Escape and the close button both dismiss.

### Sidebar
Pinned open (it auto-collapsed when the window went wide). Custom rows rather than
system `List` selection, because the default selection blue fights the palette.
Selected row: 9% white fill plus a 2.5px amber left accent.

## Motion rules

- Nothing pulses or sweeps on a timer. The only continuous motion is orbital, and the
  outermost band takes about five minutes to come around.
- Every speed change is eased, so it is interruptible and never jarring.
- `prefers-reduced-motion` freezes the orbits and the core spin entirely; the system
  still renders and stays fully interactive.
