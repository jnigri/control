import AppKit

// The state of the window manager, and `refresh()`, which keeps it in line with the screen.

/// Desks with a key. The main monitor shows one of them at a time.
let desks = Dictionary(uniqueKeysWithValues: deskKeys.map { ($0, Desk($0)) })
var current = "1"
var previous = "1"

/// One desk per extra monitor, by display.
var monitorDesks: [CGDirectDisplayID: Desk] = [:]

/// Windows moved out of sight, with the frame they had before.
var hidden: [Window: CGRect] = [:]

/// While the screen is locked, apps report no windows. Don't take that as every window closing.
var locked = false

var allDesks: [Desk] { Array(desks.values) + Array(monitorDesks.values) }

func desk(of window: Window) -> Desk? { allDesks.first { $0.windows.contains(window) } }

/// The desks on screen right now, with the area each one fills.
func visibleDesks() -> [(desk: Desk, area: CGRect)] {
    NSScreen.screens.enumerated().map { index, screen in
        let desk = index == 0 ? desks[current]! : monitorDesks[displayID(of: screen)]!
        return (desk, usableArea(of: screen))
    }
}

/// Bring the model in line with the windows that exist, then put every window in place.
/// Runs after every event and every key: simple, and it fixes itself if an event is missed.
func refresh() {
    guard !locked else { return }
    syncMonitors()

    // Remember which window has focus, so the next new window splits it.
    if let focused = focusedWindow(), let desk = desk(of: focused) { desk.lastFocused = focused }

    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    watchApps(apps)
    let live = apps.flatMap { windows(of: $0.processIdentifier) }

    // Closed or minimized windows leave their desk. Their neighbor takes the space.
    for desk in allDesks {
        for window in desk.windows where !live.contains(window) { desk.remove(window) }
    }
    hidden = hidden.filter { live.contains($0.key) }

    // New windows join a desk.
    for window in live where desk(of: window) == nil { adopt(window) }

    arrange()
}

/// A new window joins the desk it had before Control started, or else the desk of the monitor it appeared on.
func adopt(_ window: Window) {
    let rect = frame(of: window)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let desk = savedDesk(for: window) ?? visibleDesks().first { $0.area.contains(center) }?.desk ?? desks[current]!
    if shouldFloat(window) {
        desk.floating.append(window)
    } else {
        desk.tile(window, beside: desk.lastFocused)
    }
}

/// Tile the desks on screen. Move every other window out of sight.
func arrange() {
    let shown = visibleDesks()
    for (desk, area) in shown {
        for (window, rect) in desk.layout(in: area) {
            hidden[window] = nil
            setFrame(window, rect)
        }
        for window in desk.floating {
            if let old = hidden.removeValue(forKey: window) { setFrame(window, old) }
        }
    }
    for desk in allDesks where !shown.contains(where: { $0.desk === desk }) {
        for window in desk.windows where hidden[window] == nil { hide(window) }
    }
    menuBar.update()
    saveDesks()
}

/// Park a window in a corner of the main monitor, with only 1 point left on screen.
/// The right corner, unless another monitor sits on the right: then the left corner.
func hide(_ window: Window) {
    let old = frame(of: window)
    hidden[window] = old
    let main = NSScreen.screens[0].frame
    let monitorOnRight = NSScreen.screens.dropFirst().contains { $0.frame.minX >= main.maxX }
    let x = monitorOnRight ? main.minX - old.width + 1 : main.maxX - 1
    setPosition(window, CGPoint(x: x, y: main.maxY - 1))
}

/// Each extra monitor gets a desk. An unplugged monitor sends its windows to the main monitor.
func syncMonitors() {
    let ids = NSScreen.screens.dropFirst().map(displayID(of:))
    for id in ids where monitorDesks[id] == nil {
        monitorDesks[id] = Desk("monitor \(id)")
    }
    for (id, desk) in monitorDesks where !ids.contains(id) {
        for window in desk.tiled { desks[current]!.tile(window, beside: nil) }
        desks[current]!.floating += desk.floating
        monitorDesks[id] = nil
    }
}
