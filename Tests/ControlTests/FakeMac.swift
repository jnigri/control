import ApplicationServices
import Foundation
import Testing
@testable import Control

// A pretend Mac: monitors and windows are plain values the tests set up and read back.

/// A window for tests. Any number gives a distinct window: no real app is behind it.
func window(_ number: Int) -> Window { AXUIElementCreateApplication(pid_t(number)) }

/// A monitor 1000 wide and 820 high, with a 20-point menu bar. Monitors sit side by side by default.
func monitor(_ id: CGDirectDisplayID, x: CGFloat = 0, y: CGFloat = 0) -> Screen {
    Screen(id: id, frame: CGRect(x: x, y: y, width: 1000, height: 820),
           area: CGRect(x: x, y: y + 20, width: 1000, height: 800))
}

let mainMonitor = monitor(1)
let rightMonitor = monitor(2, x: 1000)

final class FakeMac: System {
    var screens = [mainMonitor]
    var separateSpaces = true
    var now = Date(timeIntervalSince1970: 1_000_000)
    var bootTime = 1

    var open: [Window] = []               // every window that exists, oldest first
    var frames: [Window: CGRect] = [:]
    var focused: Window?
    var unreported: Set<Window> = []      // open, but apps do not list them (another Space, locked screen)
    var dialogs: Set<Window> = []         // windows that float
    var fullScreen: Set<Window> = []      // windows in macOS's own full screen mode
    var fullScreenOn: [Window: CGDirectDisplayID] = [:]
    var minimums: [Window: CGSize] = [:]  // apps that refuse to get smaller
    var bundles: [Window: String] = [:]
    var names: [Window: String] = [:]
    var titles: [Window: String] = [:]
    var store: [String: Any] = [:]
    var redraws = 0
    var writes = 0

    func windows() -> [Window] { open.filter { !unreported.contains($0) } }
    func focusedWindow() -> Window? { focused }
    func focus(_ window: Window) { focused = window }
    func unfocus() { focused = nil }
    func frame(of window: Window) -> CGRect { frames[window] ?? .zero }

    func setPosition(_ window: Window, _ point: CGPoint) {
        guard let old = frames[window], !fullScreen.contains(window) else { return }
        frames[window] = CGRect(origin: point, size: old.size)
    }

    func setFrame(_ window: Window, _ rect: CGRect) {
        guard frames[window] != nil, !fullScreen.contains(window) else { return }
        let least = minimums[window] ?? .zero
        frames[window] = CGRect(x: rect.minX, y: rect.minY,
                                width: max(rect.width, least.width), height: max(rect.height, least.height))
    }

    func shouldFloat(_ window: Window) -> Bool { dialogs.contains(window) }
    func isFullScreen(_ window: Window) -> Bool { fullScreen.contains(window) }
    func number(of window: Window) -> CGWindowID? { CGWindowID(pid(of: window)) }
    func app(of window: Window) -> String? { bundles[window] }
    func appName(of window: Window) -> String? { names[window] }
    func title(of window: Window) -> String { titles[window] ?? "" }
    func saved(_ key: String) -> Any? { store[key] }
    func save(_ value: Any, as key: String) { store[key] = value; writes += 1 }
    func changed() { redraws += 1 }

    // What the user and the apps do.

    /// An app opens a window. Like on a real Mac, it takes the focus. Then Control hears about it.
    @discardableResult
    func opens(_ number: Int, on screen: Screen = mainMonitor, dialog: Bool = false, app: String? = nil) -> Window {
        let new = window(number)
        open.append(new)
        frames[new] = CGRect(x: screen.area.minX + 300, y: screen.area.minY + 250, width: 400, height: 300)
        if dialog { dialogs.insert(new) }
        bundles[new] = app ?? "app.\(number)"
        focused = new
        refresh()
        return new
    }

    func closes(_ window: Window) {
        open.removeAll { $0 == window }
        frames[window] = nil
        unreported.remove(window)
        fullScreen.remove(window)
        fullScreenOn[window] = nil
        if focused == window { focused = windows().last }
        refresh()
    }

    /// The window goes into macOS's own full screen mode, on a Space of its own. On its monitor,
    /// apps stop reporting the windows left behind.
    func entersFullScreen(_ window: Window, on screen: Screen = mainMonitor, before: () -> Void = {}) -> CGRect {
        let old = frames[window]!
        fullScreen.insert(window)
        fullScreenOn[window] = screen.id
        frames[window] = screen.frame
        leaveBehind()
        focused = window
        before()
        refresh()
        return old
    }

    /// Apps stop reporting the windows on a monitor that shows a full screen window. Anything with
    /// at least one point on the monitor lives on its Space: parked windows too.
    private func leaveBehind() {
        let covered = separateSpaces ? screens.filter { fullScreenOn.values.contains($0.id) } : screens
        unreported = Set(open.filter { window in
            !fullScreen.contains(window) && covered.contains { $0.frame.intersects(frames[window]!) }
        })
    }

    func leavesFullScreen(_ window: Window, backTo old: CGRect) {
        fullScreen.remove(window)
        fullScreenOn[window] = nil
        frames[window] = old
        unreported = []
        refresh()
    }

    /// Monitors are plugged, unplugged or moved. Like macOS, bring back any window left fully off screen.
    func plugs(_ screens: [Screen]) {
        self.screens = screens
        guard let main = screens.first else { return }
        for window in open where !screens.contains(where: { $0.frame.intersects(frames[window]!) }) {
            frames[window]!.origin = CGPoint(x: main.area.minX + 40, y: main.area.minY + 40)
        }
        // A full screen window follows its monitor, or goes to the main one if its monitor is gone.
        for window in fullScreen {
            let screen = screens.first { $0.id == fullScreenOn[window] } ?? main
            fullScreenOn[window] = screen.id
            frames[window] = screen.frame
        }
        if !fullScreen.isEmpty { leaveBehind() }
    }

    /// The user drags a window's frame with the mouse and lets go, with the pointer at `pointer`.
    func drags(_ window: Window, to frame: CGRect, pointer: CGPoint? = nil) {
        frames[window] = frame
        focused = window
        dropped(window, at: pointer ?? CGPoint(x: frame.midX, y: frame.minY + 10))
    }
}

/// All the tests that touch Control's state. One at a time, since that state is global.
@Suite(.serialized) struct ControlTests {
    let fake = FakeMac()

    /// Start from an empty Control on a Mac with one monitor and no windows.
    init() { restart(on: fake) }
}

/// Control starts: fresh state, then it reads what the last run saved.
func restart(on fake: FakeMac) {
    mac = fake
    desks = Dictionary(uniqueKeysWithValues: deskKeys.map { ($0, Desk($0)) })
    current = "1"
    previous = "1"
    monitorDesks = [:]
    hidden = [:]
    parkedOn = []
    placed = [:]
    covered = []
    locked = false
    asleep = false
    catchingUpUntil = .distantPast
    lastFocus = nil
    closedAt = .distantPast
    loadSavedDesks()
    refresh()
}

/// How much of a window shows on any monitor, in square points.
func visibleArea(of window: Window, on fake: FakeMac) -> CGFloat {
    let frame = fake.frame(of: window)
    return fake.screens.map { frame.intersection($0.frame) }.map { $0.width * $0.height }.reduce(0, +)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
}

// With an 8-point gap, the main monitor's area (0, 20, 1000, 800) gives these tiles.
let whole = rect(8, 28, 984, 784)
let leftHalf = rect(8, 28, 488, 784)
let rightHalf = rect(504, 28, 488, 784)
let topRight = rect(504, 28, 488, 388)
let bottomRight = rect(504, 424, 488, 388)
