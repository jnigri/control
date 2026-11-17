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

/// The desk the user is on: the one whose window last had the focus, or the one a key last showed.
/// New windows open there, wherever their app puts them.
var activeDesk: Desk?

/// The window that had focus at the last refresh. When it changes, someone picked another window.
var lastFocus: Window?

/// When a window last closed or was minimized. macOS then gives the focus to another window on
/// its own, maybe one on a desk out of sight. For this long after, that is not the user picking it.
var closedAt = Date.distantPast
let closeTime: TimeInterval = 1

/// When the user last pressed a mouse button. A click gives the focus to the window under it:
/// then the pointer is already where the user wants it.
var clickedAt = Date.distantPast
let clickTime: TimeInterval = 1

/// The Mac woke up or the screen unlocked: catch up with what happened meanwhile.
func resume() {
    catchingUpUntil = mac.now.addingTimeInterval(catchUpTime)
    log("resume", ["catchUpFor": catchUpTime, "locked": locked, "asleep": asleep])
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
    logMonitors()
    // With the lid closed and no monitor, there is nothing to arrange.
    guard !paused, !mac.screens.isEmpty else {
        logChange("skip", \.skip, locked ? "locked" : asleep ? "asleep" : "no monitor") { ["why": $0] }
        return
    }
    logMemory.skip = ""
    syncMonitors()

    // Remember which window has focus, so the next new window splits it.
    if let focused = mac.focusedWindow(), let desk = desk(of: focused) {
        desk.lastFocused = focused
        // Only when the focus moves: after the key of an empty monitor, it stays on the old window.
        if focused != lastFocus, visibleDesks().contains(where: { $0.desk === desk }) { activeDesk = desk }
    }

    let live = mac.windows()
    covered = coveredMonitors(live)

    // Closed or minimized windows leave their desk. Their neighbor takes the space.
    // Not on a covered monitor: there, apps stop reporting windows that are still open.
    // The same goes for hidden windows, which may be parked in a corner of any monitor,
    // and for every window while apps catch up after a sleep or the lock screen.
    // An app that gave no answer did not say its windows closed: they stay too.
    let catchingUp = mac.now < catchingUpUntil
    let silent = mac.silentApps
    logChange("catch-up", \.catchingUp, catchingUp) { ["state": $0 ? "start" : "end"] }
    logChange("covered", \.covered, covered) { ["monitors": $0.map { Int($0) }.sorted()] }
    logChange("silent", \.silent, silent) { pids in
        ["apps": pids.sorted().map { id in
            ["pid": Int(id), "app": allDesks.flatMap(\.windows).first { pid(of: $0) == id }.flatMap(mac.app(of:)) ?? "?"]
        }]
    }
    // A missing window that stays, and why. The others leave their desk.
    var kept: [Window: String] = [:]
    for desk in allDesks {
        for window in desk.windows where !live.contains(window) {
            let why = catchingUp ? "catching up" : isCovered(desk) ? "covered monitor"
                : silent.contains(pid(of: window)) ? "silent app"
                : !covered.isEmpty && hidden[window] != nil ? "hidden beside full screen" : nil
            if let why {
                kept[window] = why
                continue
            }
            let minimized = mac.isMinimized(window)
            log("gone", tag(window, ["desk": desk.name, "minimized": minimized]))
            if !minimized { rememberGone(window, from: desk) }
            desk.remove(window)
            closedAt = mac.now
        }
    }
    logChange("kept", \.kept, kept) { kept in ["windows": kept.map { tag($0.key, ["why": $0.value]) }] }
    hidden = hidden.filter { desk(of: $0.key) != nil }
    placed = placed.filter { desk(of: $0.key) != nil }

    // New windows join a desk. A window born full screen (a video) waits until it is a normal window.
    let new = live.filter { desk(of: $0) == nil && !mac.isFullScreen($0) }
    for window in new { adopt(window) }

    // A new window has the focus because it just opened, maybe on its saved desk: not a pick.
    if !catchingUp, mac.focusedWindow().map(new.contains) != true { followFocus() }
    let before = lastFocus
    lastFocus = mac.focusedWindow()
    if lastFocus != before {
        log("focus", lastFocus.map { tag($0, ["desk": desk(of: $0)?.name ?? ""]) } ?? ["w": NSNull()])
    }
    arrange()
    if !catchingUp { followWithPointer(from: before) }
}

/// The focus went to another window (Command + Tab, Command + `, the Dock, a key, a new window):
/// the pointer goes to the middle of that window, now that it is in place. Not after a click on
/// the window itself, and not when macOS picked the window because another one just closed.
func followWithPointer(from before: Window?) {
    guard let window = mac.focusedWindow(), window != before,
          mac.now.timeIntervalSince(closedAt) >= closeTime else { return }
    let clicked = mac.now.timeIntervalSince(clickedAt) < clickTime
    if clicked && mac.frame(of: window).contains(mac.pointer) { return }
    pointAt(window)
}

/// The pointer goes to the middle of a window, if its desk is on screen and not under a full screen video.
/// Only with the setting on (see `Config.swift`).
func pointAt(_ window: Window) {
    guard config.centerPointer, let desk = desk(of: window), !isCovered(desk),
          visibleDesks().contains(where: { $0.desk === desk }) else { return }
    let frame = mac.frame(of: window)
    mac.movePointer(to: CGPoint(x: frame.midX, y: frame.midY))
}

/// The pointer goes to the middle of a desk on screen. For an empty desk, which has no window to focus.
func pointAt(_ desk: Desk) {
    guard config.centerPointer, let area = visibleDesks().first(where: { $0.desk === desk })?.area else { return }
    mac.movePointer(to: CGPoint(x: area.midX, y: area.midY))
}

/// The user picked a window on a desk out of sight, with Command + Tab, the Dock or Command + `:
/// that desk comes on screen. Right after a window closes, macOS picks one on its own: then the
/// focus goes back to the desk on screen instead. The same when the focus did not move but its
/// desk went out of sight, with its monitor.
func followFocus() {
    guard let window = mac.focusedWindow(), let desk = desk(of: window),
          !visibleDesks().contains(where: { $0.desk === desk }) else { return }
    let stays = window == lastFocus || mac.now.timeIntervalSince(closedAt) < closeTime
    log("follow-focus", tag(window, ["desk": desk.name, "did": stays ? "focus went back" : "desk came up"]))
    if stays {
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

/// A new window joins the desk it had before Control started, or the desk it had when it went
/// missing a moment ago, or else the desk the user is on.
/// Not the desk of the monitor it appeared on: apps open windows where they last had one, maybe
/// on another monitor. Some windows do go by where they are: floating ones, which stay where
/// their app put them, the ones already open when Control started, and any window while a full
/// screen video covers the desk the user is on.
func adopt(_ window: Window) {
    let rect = mac.frame(of: window)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let shown = visibleDesks()
    let there = shown.first { $0.area.contains(center) }?.desk
    let floats = mac.shouldFloat(window)
    let stays = floats || wasOpenAtStart(window)
    let here = shown.first { $0.desk === activeDesk && !isCovered($0.desk) }?.desk
    let back = goneDesk(for: window)
    let saved = back ?? savedDesk(for: window)
    let desk = saved ?? (stays ? there : nil) ?? here ?? there ?? desks[current]!
    log("adopt", tag(window, [
        "desk": desk.name, "frame": box(rect), "floating": floats,
        "rule": back != nil ? "came back" : saved != nil ? "saved" : stays && there != nil ? "stays where it is"
            : here != nil ? "active desk" : there != nil ? "monitor under it" : "current",
    ]))
    if floats {
        desk.floating.append(window)
        // After a crash of Control the window may still be parked out of sight: bring it back.
        if let area = visibleDesks().first(where: { $0.desk === desk })?.area, inSight(rect, on: area) != rect {
            log("restore", tag(window, ["from": box(rect), "to": box(inSight(rect, on: area))]))
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
        for (window, old) in hidden {
            log("repark", tag(window, ["why": "monitors changed", "to": spot(parkingSpot(for: old.size, on: frames))]))
            mac.setPosition(window, parkingSpot(for: old.size, on: frames))
        }
    }
    // A parked window may be back in view all the same: macOS pulls windows back a moment after
    // monitors change, and an app busy waking up may not take the move. Park it again.
    for window in hidden.keys {
        let now = mac.frame(of: window)
        if frames.contains(where: { inView(now, on: $0) }) {
            log("repark", tag(window, ["why": "back in view", "found": box(now),
                                       "to": spot(parkingSpot(for: now.size, on: frames))]))
            mac.setPosition(window, parkingSpot(for: now.size, on: frames))
        }
    }

    let shown = visibleDesks()
    for (desk, area) in shown where !isCovered(desk) {
        for (window, rect) in desk.layout(in: area) {
            hidden[window] = nil
            mac.setFrame(window, rect)
            let took = mac.frame(of: window)
            if took != placed[window] { logPlace(window, on: desk, asked: rect, took: took) }
            placed[window] = took
        }
        for window in desk.floating {
            if let old = hidden.removeValue(forKey: window) {
                log("restore", tag(window, ["from": box(old), "to": box(follow(old, to: area))]))
                mac.setFrame(window, follow(old, to: area))
            }
        }
    }
    for desk in allDesks where !isCovered(desk) && !shown.contains(where: { $0.desk === desk }) {
        for window in desk.windows where hidden[window] == nil { hide(window) }
    }
    mac.changed()
    saveDesks()
    logLayout()
}

/// A tiled window took a new frame. When it is not the one asked for, say by how much on each
/// side: left, top, right, bottom. More than zero is a gap, less is the window sticking out.
func logPlace(_ window: Window, on desk: Desk, asked: CGRect, took: CGRect) {
    log("place", tag(window, ["desk": desk.name, "asked": box(asked), "took": box(took)]))
    let gaps = [took.minX - asked.minX, took.minY - asked.minY, asked.maxX - took.maxX, asked.maxY - took.maxY]
    if gaps.contains(where: { abs($0) > 2 }) {
        log("refused", tag(window, ["desk": desk.name, "gaps": gaps.map { (Double($0) * 10).rounded() / 10 }]))
    }
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
    log("park", tag(window, ["from": box(old), "to": spot(parkingSpot(for: old.size, on: mac.screens.map(\.frame)))]))
    mac.setPosition(window, parkingSpot(for: old.size, on: mac.screens.map(\.frame)))
}

/// Whether a window shows on a monitor. A parked window keeps a sliver 1 point wide in view, and
/// macOS pulls it up until its top 30 points or so show: still a sliver 1 point wide, so out of view.
/// Taking that sliver for a window in view parked it again at every refresh, and macOS pulled it
/// back up each time.
func inView(_ frame: CGRect, on screen: CGRect) -> Bool {
    let seen = frame.intersection(screen)
    return seen.width > 1 && seen.height > 1
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
    for (id, desk) in monitorDesks where !extra.contains(where: { $0.id == id }) {
        log("monitor-desk", ["did": "lost", "monitor": Int(id), "desk": desk.name])
    }
    monitorDesks = monitorDesks.filter { id, _ in extra.contains { $0.id == id } }
    for screen in extra where monitorDesks[screen.id] == nil {
        let free = monitorDeskKeys.filter { key in !monitorDesks.values.contains { $0.name == key } }
        // The key it had before, if no other monitor took it meanwhile. Past the last key, no desk.
        guard let key = monitorKeys[screen.id].flatMap({ free.contains($0) ? $0 : nil }) ?? free.first else { continue }
        let desk = desks[key]!
        log("monitor-desk", ["did": "took", "monitor": Int(screen.id), "desk": key, "savedKey": monitorKeys[screen.id] ?? "",
                             "windows": desk.windows.count])
        monitorDesks[screen.id] = desk
        if monitorKeys[screen.id] != key {
            monitorKeys[screen.id] = key
            mac.save(Dictionary(uniqueKeysWithValues: monitorKeys.map { (String($0), $1) }), as: "monitors")
        }
        // The desk may be the one on the main monitor: its floating windows go along.
        for window in desk.floating where hidden[window] == nil {
            log("restore", tag(window, ["why": "its desk went to a monitor", "to": box(follow(mac.frame(of: window), to: screen.area))]))
            mac.setFrame(window, follow(mac.frame(of: window), to: screen.area))
        }
    }
    // The main monitor never shows a desk that an extra monitor took.
    if onMonitor(desks[current]!) {
        let taken = current
        current = ([previous] + deskKeys).first { !onMonitor(desks[$0]!) }!
        log("desk", ["did": "a monitor took the desk of the main one", "from": taken, "to": current])
    }
}
