import AppKit

// What each key does.

enum Direction { case left, down, up, right }

/// The focused window and its desk, if Control manages it.
func focusedOnDesk() -> (window: Window, desk: Desk)? {
    guard let window = focusedWindow(), let desk = desk(of: window) else { return nil }
    return (window, desk)
}

/// Option + desk key: show that desk on the main monitor.
func show(_ key: String) {
    guard key != current else { return }
    previous = current
    current = key
    arrange()
    if let window = desks[key]!.lastFocused ?? desks[key]!.windows.first { focus(window) }
}

/// Option + Shift + desk key: send the focused window to a desk, and follow it.
func send(to key: String) {
    guard let (window, from) = focusedOnDesk() else { return }
    let to = desks[key]!
    let wasFloating = from.floating.contains(window)
    from.remove(window)
    if wasFloating {
        to.floating.append(window)
    } else {
        to.tile(window, beside: to.lastFocused)
    }
    to.lastFocused = window
    if key != current {
        previous = current
        current = key
    }
    arrange()
    focus(window)
}

/// The closest tiled window on screen in a direction. Crosses monitors, since all
/// visible windows are compared by position.
func neighbor(of window: Window, _ direction: Direction) -> Window? {
    var frames: [Window: CGRect] = [:]
    for (desk, area) in visibleDesks() { frames.merge(desk.layout(in: area)) { first, _ in first } }
    guard let from = frames[window] else { return nil }

    let candidates = frames.filter { _, rect in
        switch direction {
        case .left: rect.midX < from.minX
        case .right: rect.midX > from.maxX
        case .up: rect.midY < from.minY
        case .down: rect.midY > from.maxY
        }
    }
    // Prefer windows straight ahead over windows off to the side.
    func distance(_ rect: CGRect) -> CGFloat {
        let dx = abs(rect.midX - from.midX)
        let dy = abs(rect.midY - from.midY)
        return direction == .left || direction == .right ? dx + 2 * dy : dy + 2 * dx
    }
    return candidates.min { distance($0.value) < distance($1.value) }?.key
}

/// Option + H/J/K/L
func moveFocus(_ direction: Direction) {
    guard let (window, _) = focusedOnDesk(), let other = neighbor(of: window, direction) else { return }
    focus(other)
}

/// Option + Shift + H/J/K/L: trade places with the neighbor, even on another monitor.
func swap(_ direction: Direction) {
    guard let (window, desk) = focusedOnDesk(),
          let other = neighbor(of: window, direction),
          let mine = desk.leaf(of: window),
          let theirs = Control.desk(of: other)?.leaf(of: other) else { return }
    mine.window = other
    theirs.window = window
    arrange()
    focus(window)
}

/// Option + Minus / Equal: move the split next to the focused window.
func resize(by step: CGFloat) {
    guard let (window, desk) = focusedOnDesk(),
          let leaf = desk.leaf(of: window),
          let parent = leaf.parent else { return }
    let change = parent.first === leaf ? step : -step
    parent.ratio = min(0.9, max(0.1, parent.ratio + change))
    arrange()
}

/// Option + Shift + F: the focused tiled window covers the whole desk, or stops covering it.
func toggleFullscreen() {
    guard let (window, desk) = focusedOnDesk(), desk.leaf(of: window) != nil else { return }
    desk.fullscreen = desk.fullscreen == window ? nil : window
    arrange()
    focus(window)
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
            setFrame(window, area.insetBy(dx: area.width / 6, dy: area.height / 6))
        }
    }
    arrange()
    focus(window)
}
