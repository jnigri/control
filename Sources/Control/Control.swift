import Foundation
import CoreGraphics

// The state of the window manager, and `refresh()`, which keeps it in line with the screen.

/// Every desk, by key. The main monitor shows one of them at a time.
var desks = Dictionary(uniqueKeysWithValues: deskKeys.map { ($0, Desk($0)) })
var current = "1"
var previous = "1"

/// The desk each extra monitor shows, by display. It stays there as long as the monitor does.
var monitorDesks: [CGDirectDisplayID: Desk] = [:]

/// The desk key each extra monitor took, kept after it is unplugged and between runs,
/// so a monitor that returns shows the same desk again.
var monitorKeys: [CGDirectDisplayID: String] = [:]

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

/// The same while the Mac sleeps.
var asleep = false

var paused: Bool { locked || asleep }

/// After the Mac wakes up or the screen unlocks, apps take a moment to report their windows again.
/// Until then, a missing window has not closed: it keeps its place on its desk.
var catchingUpUntil = Date.distantPast
let catchUpTime: TimeInterval = 10

/// The window that had focus at the last refresh. When it changes, someone picked another window.
var lastFocus: Window?

/// When a window last closed or was minimized. macOS then gives the focus to another window on
/// its own, maybe one on a desk out of sight. For this long after, that is not the user picking it.
var closedAt = Date.distantPast
let closeTime: TimeInterval = 1

/// The Mac woke up or the screen unlocked: catch up with what happened meanwhile.
func resume() {
    catchingUpUntil = mac.now.addingTimeInterval(catchUpTime)
    // Monitors may have come and gone meanwhile, and macOS then brings parked windows back into
    // view. They may be back to how they were, so park every hidden window again.
    parkedOn = []
    refresh()
}

var allDesks: [Desk] { Array(desks.values) }

/// Whether a desk is the one of an extra monitor right now.
func onMonitor(_ desk: Desk) -> Bool { monitorDesks.values.contains { $0 === desk } }

func desk(of window: Window) -> Desk? { allDesks.first { $0.windows.contains(window) } }

/// The monitor a desk lives on: its own for an extra monitor's desk, the main one for the others.
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
    guard !paused, !mac.screens.isEmpty else { return }
    syncMonitors()

    // Remember which window has focus, so the next new window splits it.
    if let focused = mac.focusedWindow(), let desk = desk(of: focused) { desk.lastFocused = focused }

    let live = mac.windows()
    covered = coveredMonitors(live)

    // Closed or minimized windows leave their desk. Their neighbor takes the space.
    // Not on a covered monitor: there, apps stop reporting windows that are still open.
    // The same goes for hidden windows, which may be parked in a corner of any monitor,
    // and for every window while apps catch up after a sleep or the lock screen.
    let catchingUp = mac.now < catchingUpUntil
    for desk in allDesks where !isCovered(desk) && !catchingUp {
        for window in desk.windows where !live.contains(window) && (covered.isEmpty || hidden[window] == nil) {
            desk.remove(window)
            closedAt = mac.now
        }
    }
    hidden = hidden.filter { desk(of: $0.key) != nil }
    placed = placed.filter { desk(of: $0.key) != nil }

    // New windows join a desk. A window born full screen (a video) waits until it is a normal window.
    let new = live.filter { desk(of: $0) == nil && !mac.isFullScreen($0) }
    for window in new { adopt(window) }

    // A new window has the focus because it just opened, maybe on its saved desk: not a pick.
    if !catchingUp, mac.focusedWindow().map(new.contains) != true { followFocus() }
    lastFocus = mac.focusedWindow()
    arrange()
}

/// The user picked a window on a desk out of sight, with Command + Tab, the Dock or Command + `:
/// that desk comes on screen. Right after a window closes, macOS picks one on its own: then the
/// focus goes back to the desk on screen instead. The same when the focus did not move but its
/// desk went out of sight, with its monitor.
func followFocus() {
    guard let window = mac.focusedWindow(), let desk = desk(of: window),
          !visibleDesks().contains(where: { $0.desk === desk }) else { return }
    if window == lastFocus || mac.now.timeIntervalSince(closedAt) < closeTime {
        let here = desks[current]!
        if let other = here.lastFocused ?? here.windows.first { mac.focus(other) } else { mac.unfocus() }
    } else {
        bringUp(window)
    }
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
            if let old = hidden.removeValue(forKey: window) { mac.setFrame(window, follow(old, to: area)) }
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

/// A frame for a floating window on a desk that fills `area`. Last seen on another monitor, the
/// window keeps its place relative to the monitor.
func follow(_ old: CGRect, to area: CGRect) -> CGRect {
    let center = CGPoint(x: old.midX, y: old.midY)
    guard let from = mac.screens.first(where: { $0.frame.contains(center) })?.area else { return inSight(old, on: area) }
    return inSight(old.offsetBy(dx: area.minX - from.minX, dy: area.minY - from.minY), on: area)
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

/// Each extra monitor takes a desk of its own: the first one desk 0, the next one 9, and so on
/// (see `monitorDeskKeys`). The main monitor keeps showing the other desks. When a monitor is
/// unplugged, its desk stays, with its windows and layout: its key shows it on the main monitor,
/// and it goes back to the monitor when that one returns. Monitors also come and go for a moment
/// when the Mac wakes up.
func syncMonitors() {
    let extra = mac.screens.dropFirst()
    monitorDesks = monitorDesks.filter { id, _ in extra.contains { $0.id == id } }
    for screen in extra where monitorDesks[screen.id] == nil {
        let free = monitorDeskKeys.filter { key in !monitorDesks.values.contains { $0.name == key } }
        // The key it had before, if no other monitor took it meanwhile. Past the last key, no desk.
        guard let key = monitorKeys[screen.id].flatMap({ free.contains($0) ? $0 : nil }) ?? free.first else { continue }
        let desk = desks[key]!
        monitorDesks[screen.id] = desk
        if monitorKeys[screen.id] != key {
            monitorKeys[screen.id] = key
            mac.save(Dictionary(uniqueKeysWithValues: monitorKeys.map { (String($0), $1) }), as: "monitors")
        }
        // The desk may be the one on the main monitor: its floating windows go along.
        for window in desk.floating where hidden[window] == nil {
            mac.setFrame(window, follow(mac.frame(of: window), to: screen.area))
        }
    }
    // The main monitor never shows a desk that an extra monitor took.
    if onMonitor(desks[current]!) {
        current = ([previous] + deskKeys).first { !onMonitor(desks[$0]!) }!
    }
}
