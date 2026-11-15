import Foundation
import CoreGraphics

// The state of the window manager, and `refresh()`, which keeps it in line with the screen.

/// Desks with a key. The main monitor shows one of them at a time.
var desks = Dictionary(uniqueKeysWithValues: deskKeys.map { ($0, Desk($0)) })
var current = "1"
var previous = "1"

/// One desk per extra monitor, by display.
var monitorDesks: [CGDirectDisplayID: Desk] = [:]

/// The desks of monitors that went away. Each one comes back with its monitor.
var unplugged: [CGDirectDisplayID: Desk] = [:]

/// Windows moved out of sight, with the frame they had before.
var hidden: [Window: CGRect] = [:]

/// The monitor frames that the hidden windows were parked for.
var parkedOn: [CGRect] = []

/// The frame each tiled window really took the last time it was put in place.
/// Apps may not take the exact frame we ask for, and this tells a later mouse drag apart from that.
var placed: [Window: CGRect] = [:]

/// Monitors showing a window in macOS's own full screen mode. We leave those alone.
var covered: Set<CGDirectDisplayID> = []

/// While the screen is locked, apps report no windows. Don't take that as every window closing.
var locked = false

var allDesks: [Desk] { Array(desks.values) + Array(monitorDesks.values) }

func desk(of window: Window) -> Desk? { allDesks.first { $0.windows.contains(window) } }

/// The monitor a desk lives on: its own for a monitor's desk, the main one for a desk with a key.
func monitor(of desk: Desk) -> CGDirectDisplayID? {
    monitorDesks.first { $0.value === desk }?.key ?? mac.screens.first?.id
}

/// The desks on screen right now, with the area each one fills.
func visibleDesks() -> [(desk: Desk, area: CGRect)] {
    mac.screens.enumerated().compactMap { index, screen in
        guard let desk = index == 0 ? desks[current] : monitorDesks[screen.id] else { return nil }
        return (desk, screen.area)
    }
}

/// Bring the model in line with the windows that exist, then put every window in place.
/// Runs after every event and every key: simple, and it fixes itself if an event is missed.
func refresh() {
    // With the lid closed and no monitor, there is nothing to arrange.
    guard !locked, !mac.screens.isEmpty else { return }
    syncMonitors()

    // Remember which window has focus, so the next new window splits it.
    if let focused = mac.focusedWindow(), let desk = desk(of: focused) { desk.lastFocused = focused }

    let live = mac.windows()
    covered = coveredMonitors(live)

    // Closed or minimized windows leave their desk. Their neighbor takes the space.
    // Not on a covered monitor: there, apps stop reporting windows that are still open.
    // The same goes for hidden windows, which may be parked in a corner of any monitor.
    for desk in allDesks where !isCovered(desk) {
        for window in desk.windows where !live.contains(window) && (covered.isEmpty || hidden[window] == nil) {
            desk.remove(window)
        }
    }
    hidden = hidden.filter { desk(of: $0.key) != nil }
    placed = placed.filter { desk(of: $0.key) != nil }

    // New windows join a desk. A window born full screen (a video) waits until it is a normal window.
    for window in live where desk(of: window) == nil && !mac.isFullScreen(window) { adopt(window) }

    arrange()
}

/// The monitors showing a window in macOS's own full screen mode. That window sits on a Space
/// of its own, and apps do not report the windows left behind on the Space it covers.
func coveredMonitors(_ live: [Window]) -> Set<CGDirectDisplayID> {
    let full = live.filter(mac.isFullScreen)
    if full.isEmpty { return [] }
    // Without separate Spaces, one full screen window takes over every monitor.
    if !mac.separateSpaces { return Set(mac.screens.map(\.id)) }
    return Set(full.compactMap { window in
        let frame = mac.frame(of: window)
        return mac.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }?.id
    })
}

func isCovered(_ desk: Desk) -> Bool { monitor(of: desk).map(covered.contains) ?? false }

/// A new window joins the desk it had before Control started, or else the desk of the monitor it appeared on.
func adopt(_ window: Window) {
    let rect = mac.frame(of: window)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let desk = savedDesk(for: window) ?? visibleDesks().first { $0.area.contains(center) }?.desk ?? desks[current]!
    if mac.shouldFloat(window) {
        desk.floating.append(window)
        // After a crash of Control the window may still be parked out of sight: bring it back.
        if let area = visibleDesks().first(where: { $0.desk === desk })?.area, inSight(rect, on: area) != rect {
            mac.setFrame(window, inSight(rect, on: area))
        }
    } else {
        desk.tile(window, beside: desk.lastFocused)
    }
}

/// Tile the desks on screen. Move every other window out of sight.
func arrange() {
    guard !mac.screens.isEmpty else { return }
    syncMonitors()

    // When monitors come, go or move, the corner that hid the parked windows may now be in view.
    let frames = mac.screens.map(\.frame)
    if frames != parkedOn {
        parkedOn = frames
        for (window, old) in hidden { mac.setPosition(window, parkingSpot(for: old.size, on: frames)) }
    }

    let shown = visibleDesks()
    for (desk, area) in shown where !isCovered(desk) {
        for (window, rect) in desk.layout(in: area) {
            hidden[window] = nil
            mac.setFrame(window, rect)
            placed[window] = mac.frame(of: window)
        }
        for window in desk.floating {
            if let old = hidden.removeValue(forKey: window) { mac.setFrame(window, inSight(old, on: area)) }
        }
    }
    for desk in allDesks where !isCovered(desk) && !shown.contains(where: { $0.desk === desk }) {
        for window in desk.windows where hidden[window] == nil { hide(window) }
    }
    mac.changed()
    saveDesks()
}

/// A frame to give back to a floating window. Its old frame may be out of sight by now: on a
/// monitor that is gone, or in the corner where a Control that crashed had parked it.
/// Then it goes to the middle of its desk.
func inSight(_ old: CGRect, on area: CGRect) -> CGRect {
    let seen = mac.screens.contains { $0.area.intersection(old).width > 40 && $0.area.intersection(old).height > 40 }
    if seen { return old }
    let size = CGSize(width: min(old.width, area.width), height: min(old.height, area.height))
    return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
}

/// Park a window out of sight.
func hide(_ window: Window) {
    // After a crash of Control the window may still be parked: don't take that for its real place.
    let old = inSight(mac.frame(of: window), on: mac.screens[0].area)
    hidden[window] = old
    mac.setPosition(window, parkingSpot(for: old.size, on: mac.screens.map(\.frame)))
}

/// Where to park a window of this size: just past a bottom corner of a monitor, with 1 point
/// left on screen (macOS pulls back a window that is fully off screen). The corner must have
/// no other monitor behind it. The main monitor's corners come first, the right one before the left.
func parkingSpot(for size: CGSize, on screens: [CGRect]) -> CGPoint {
    let spots = screens.flatMap { screen in
        [CGPoint(x: screen.maxX - 1, y: screen.maxY - 1), CGPoint(x: screen.minX - size.width + 1, y: screen.maxY - 1)]
    }
    return spots.first { spot in
        let parked = CGRect(origin: spot, size: size)
        return screens.allSatisfy { parked.intersection($0).width * parked.intersection($0).height <= 1 }
    } ?? spots[0]
}

/// Each extra monitor gets a desk. An unplugged monitor lends its windows to the main monitor,
/// and takes them back, in the same layout, when it returns. Monitors also come and go
/// for a moment when the Mac wakes up.
func syncMonitors() {
    let ids = mac.screens.dropFirst().map(\.id)
    for id in ids where monitorDesks[id] == nil {
        let desk = unplugged.removeValue(forKey: id) ?? Desk("monitor \(id)")
        for window in desk.windows {
            // A window still open leaves the desk that held it meanwhile. A closed one is forgotten.
            if let holder = Control.desk(of: window) { holder.remove(window) } else { desk.remove(window) }
        }
        monitorDesks[id] = desk
    }
    for (id, desk) in monitorDesks where !ids.contains(id) {
        monitorDesks[id] = nil
        unplugged[id] = desk
        for window in desk.tiled { desks[current]!.tile(window, beside: nil) }
        desks[current]!.floating += desk.floating
    }
}
