import AppKit
import SwiftUI

/// Desktop companion — a borderless, transparent, click-through window
/// pinned one level above the wallpaper and below every real window, on
/// every Space, invisible to Cmd-Tab.
@MainActor
final class OverlayController {
    static let shared = OverlayController()
    private var window: NSWindow?

    func show(store: DataStore) {
        guard window == nil, let screen = NSScreen.main else { return }
        // Sized up from the original 230pt star so the dial's dense tick ring
        // and cream highlight band are actually legible, not a fidelity change.
        // Bumped again, from 340 to 400, purely to give the soft black
        // backdrop room to fade out past the ring — the dial itself stays
        // the same absolute size (see the R ratio in OverlayHUDView.draw).
        let size: CGFloat = 400
        let margin: CGFloat = 30
        let frame = NSRect(x: screen.visibleFrame.maxX - size - margin,
                           y: screen.visibleFrame.minY + margin,
                           width: size, height: size)

        let w = NSWindow(contentRect: frame, styleMask: .borderless,
                         backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true                 // click-through, always
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.contentView = NSHostingView(rootView: OverlayHUDView().environmentObject(store))
        w.orderFront(nil)
        window = w
    }
}

/// A thin wrapper: all the actual dial drawing lives in `HeroDial.swift` now,
/// shared with the in-app centrepiece in `SpaceView.swift` so the two can
/// never drift into two slightly-different dials. This view just owns the
/// window's own animation clock and reads live state straight off
/// `DataStore` — no separate polling loop of its own.
struct OverlayHUDView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                // R stays the same absolute size as the 340pt window's 0.474
                // ratio (161px) — the window grew to 400pt so the backdrop
                // has margin to fade into past the ring, not so the dial grew.
                let R = size.width * 0.403
                HeroDial.draw(context: &context, center: c, R: R, now: now,
                             state: store.liveState, daemonAlive: store.daemonAlive, includeBackdrop: true)
            }
        }
        .allowsHitTesting(false)
    }
}
