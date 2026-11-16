import Foundation
import CoreGraphics

// What each command does (see `Command.swift`), and what dragging a window with the mouse does.

enum Direction: String { case left, down, up, right }

/// The focused window and its desk, if Control manages it and the desk is on screen.
/// After a switch to an empty desk, the focus is still on a window we just hid: keys leave it alone.
func focusedOnDesk() -> (window: Window, desk: Desk)? {
    guard let window = mac.focusedWindow(), let desk = desk(of: window),
          visibleDesks().contains(where: { $0.desk === desk }) else { return nil }
    return (window, desk)
}

/// Option + desk key: show that desk on the main monitor. The desk of an extra monitor is
/// on screen already: the focus goes to it.
func show(_ key: String) {
    syncMonitors()
    activeDesk = desks[key]!
    if onMonitor(desks[key]!) {
        arrange()
        if let window = desks[key]!.lastFocused ?? desks[key]!.windows.first { mac.focus(window) }
        return
    }
    guard key != current else { return }
    previous = current
    current = key
    arrange()
    // On an empty desk, no window keeps the focus: the hidden one would swallow a click on its
    // app in the Dock. Picking any app then brings up its desk.
    if let window = desks[key]!.lastFocused ?? desks[key]!.windows.first { mac.focus(window) } else { mac.unfocus() }
}

/// Option + Shift + desk key: send the focused window to a desk, and follow it.
func send(to key: String) {
    syncMonitors()
    let to = desks[key]!
    guard let (window, from) = focusedOnDesk(), from !== to else { return }
    move(window, from: from, to: to)
    if key != current && !onMonitor(to) {
        previous = current
        current = key
    }
    // A floating window goes to the monitor of its new desk.
    if to.floating.contains(window), let area = visibleDesks().first(where: { $0.desk === to })?.area {
        mac.setFrame(window, follow(mac.frame(of: window), to: area))
    }
    arrange()
    mac.focus(window)
}

/// Focus a window wherever it is. If its desk is not on screen, that desk comes on screen first.
/// Another window covering the desk stops covering it, so the window shows.
func reveal(_ window: Window) {
    if desk(of: window) != nil {
        bringUp(window)
        arrange()
    }
    mac.focus(window)
}

/// Make a window's desk the one on screen, and the window the one that shows there.
/// The windows move on the next `arrange()`.
func bringUp(_ window: Window) {
    guard let desk = desk(of: window) else { return }
    if desk.leaf(of: window) != nil && desk.fullscreen != window { desk.fullscreen = nil }
    desk.lastFocused = window
    if !onMonitor(desk), desk.name != current {
        previous = current
        current = desk.name
    }
}

/// Take a window off its desk and put it on another. Tiled stays tiled, floating stays floating.
func move(_ window: Window, from: Desk, to: Desk, beside target: Window? = nil) {
    let wasFloating = from.floating.contains(window)
    from.remove(window)
    if wasFloating {
        to.floating.append(window)
    } else {
        to.tile(window, beside: target ?? to.lastFocused)
    }
    to.lastFocused = window
}

/// Two tiled windows trade places, even across desks.
func exchange(_ a: Window, _ b: Window) {
    guard let deskA = desk(of: a), let deskB = desk(of: b),
          let leafA = deskA.leaf(of: a), let leafB = deskB.leaf(of: b) else { return }
    leafA.window = b
    leafB.window = a
    guard deskA !== deskB else { return }
    // Each desk forgets the window that left.
    for (desk, gone, came) in [(deskA, a, b), (deskB, b, a)] {
        if desk.fullscreen == gone { desk.fullscreen = nil }
        if desk.lastFocused == gone { desk.lastFocused = came }
    }
}

/// Of some rectangles, the closest one in a direction. Straight ahead wins over off to the side.
func closest<Key>(_ rects: [(key: Key, value: CGRect)], to from: CGRect, _ direction: Direction) -> Key? {
    let ahead = rects.filter { _, rect in
        switch direction {
        case .left: rect.midX < from.minX
        case .right: rect.midX > from.maxX
        case .up: rect.midY < from.minY
        case .down: rect.midY > from.maxY
        }
    }
    func distance(_ rect: CGRect) -> CGFloat {
        let dx = abs(rect.midX - from.midX)
        let dy = abs(rect.midY - from.midY)
        return direction == .left || direction == .right ? dx + 2 * dy : dy + 2 * dx
    }
    // Two just as close (one above the other, say): the upper one, then the left one. Always the same.
    return ahead.min {
        (distance($0.value), $0.value.minY, $0.value.minX) < (distance($1.value), $1.value.minY, $1.value.minX)
    }?.key
}

/// The closest tiled window on screen in a direction. Crosses monitors, since all
/// visible windows are compared by position.
func neighbor(of window: Window, _ direction: Direction) -> Window? {
    var frames: [Window: CGRect] = [:]
    for (desk, area) in visibleDesks() { frames.merge(desk.layout(in: area)) { first, _ in first } }
    guard let from = frames[window] else { return nil }
    return closest(Array(frames), to: from, direction)
}

/// Option + H/J/K/L
func moveFocus(_ direction: Direction) {
    guard let (window, _) = focusedOnDesk(), let other = neighbor(of: window, direction) else { return }
    mac.focus(other)
}

/// Option + Shift + H/J/K/L: trade places with the neighbor, even on another monitor.
/// With no neighbor that way but a monitor, the window moves to that monitor.
func swap(_ direction: Direction) {
    guard let (window, desk) = focusedOnDesk() else { return }
    let shown = visibleDesks()
    if desk.leaf(of: window) != nil, let other = neighbor(of: window, direction) {
        exchange(window, other)
    } else if let here = shown.first(where: { $0.desk === desk })?.area,
              let there = closest(shown.map { (key: $0.area, value: $0.area) }, to: here, direction),
              let beside = shown.first(where: { $0.area == there })?.desk {
        // A floating window keeps its place relative to the monitor.
        if desk.floating.contains(window) {
            mac.setFrame(window, follow(mac.frame(of: window), to: there))
        }
        move(window, from: desk, to: beside)
    } else {
        return
    }
    arrange()
    mac.focus(window)
}

/// Option + Minus / Equal: move the split next to the focused window.
func resize(by step: CGFloat) {
    guard let (window, desk) = focusedOnDesk(),
          let leaf = desk.leaf(of: window),
          let parent = leaf.parent else { return }
    let change = parent.first === leaf ? step : -step
    parent.ratio = min(ratioLimits.upperBound, max(ratioLimits.lowerBound, parent.ratio + change))
    arrange()
}

/// Option + Shift + F: the focused tiled window covers the whole desk, or stops covering it.
func toggleFullscreen() {
    guard let (window, desk) = focusedOnDesk(), desk.leaf(of: window) != nil else { return }
    desk.fullscreen = desk.fullscreen == window ? nil : window
    arrange()
    mac.focus(window)
}

/// Option + Shift + Space: float a tiled window in the middle of its monitor, or tile it again.
func toggleFloating() {
    guard let (window, desk) = focusedOnDesk() else { return }
    if desk.floating.contains(window) {
        desk.floating.removeAll { $0 == window }
        desk.tile(window, beside: nil)
    } else {
        desk.remove(window)
        desk.floating.append(window)
        if let area = visibleDesks().first(where: { $0.desk === desk })?.area {
            mac.setFrame(window, area.insetBy(dx: area.width / 6, dy: area.height / 6))
        }
    }
    arrange()
    mac.focus(window)
}

/// The tiled window shown at a point. A window that covers its desk hides the others.
func tile(at point: CGPoint) -> Window? {
    guard let (desk, area) = visibleDesks().first(where: { $0.area.contains(point) }) else { return nil }
    return desk.fullscreen ?? desk.tiles(in: area).first { $0.value.contains(point) }?.key
}

/// The user let go of a window after dragging or resizing it with the mouse.
/// - An edge of a tiled window was dragged: the neighbors follow.
/// - A tiled window was dropped on another one: they trade places. On another monitor, it splits that one.
/// - Any window was dropped on another monitor: it now belongs to that monitor's desk.
/// - Anything else: the window snaps back to its tile.
func dropped(_ window: Window, at pointer: CGPoint) {
    defer { refresh() }
    let shown = visibleDesks()
    guard !paused, let desk = desk(of: window), !isCovered(desk),
          let home = shown.first(where: { $0.desk === desk }) else { return }
    let now = mac.frame(of: window)
    // We move windows too, and the mouse button may be down for something else, like selecting text.
    // A real drag keeps the pointer on the window, and takes a tiled window off the frame we gave it.
    guard now.insetBy(dx: -20, dy: -20).contains(pointer), placed[window] != now else { return }
    let tiled = desk.leaf(of: window) != nil
    // The pointer may be in the menu bar or the Dock of the monitor: look at whole monitors.
    let screen = mac.screens.first { $0.frame.contains(pointer) }
    let target = shown.first { $0.area == screen?.area }?.desk
    let under = tile(at: pointer)

    if tiled, desk.fullscreen != window, let before = placed[window],
       abs(now.width - before.width) > 2 || abs(now.height - before.height) > 2 {
        desk.resize(window, from: before, to: now, in: home.area)
    } else if let target, target !== desk {
        move(window, from: desk, to: target, beside: under)
    } else if tiled, let under, under != window {
        exchange(window, under)
    }
}
