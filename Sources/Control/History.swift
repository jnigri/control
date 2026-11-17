import Foundation
import CoreGraphics

// Layouts to go back to. Each time the layout changes (a window opens, closes, moves to another desk,
// trades places, a split moves), the layout it replaces goes into the history, if it stayed long
// enough to be one you had on purpose: the in-between layouts of a burst of changes are left out.
// The menu bar panel lists them: click one to put every window back where it was.
// Windows are kept by number, which lasts as long as the window, so the history lasts across
// restarts of Control but not across a reboot.

/// A desk's layout tree, by window number.
indirect enum Tree: Equatable, Codable {
    case window(CGWindowID)
    case split(Tree, Tree, CGFloat)
}

/// What a desk held.
struct DeskShape: Equatable, Codable {
    var tree: Tree?
    var floating: [CGWindowID] = []
    var fullscreen: CGWindowID?
}

/// Which window is on which desk, and where, without the frames.
struct Shape: Codable {
    var desks: [String: DeskShape] = [:]

    var windowCount: Int {
        desks.values.reduce(0) { count, desk in count + desk.floating.count + (desk.tree.map(leafCount) ?? 0) }
    }
}

private func leafCount(_ tree: Tree) -> Int {
    switch tree {
    case .window: 1
    case .split(let a, let b, _): leafCount(a) + leafCount(b)
    }
}

struct SavedLayout: Codable {
    /// When the layout was put in place, and when it was replaced (or now, for the one on screen).
    var since: Date
    var at: Date
    /// Why it was kept, when it is not just a change, like "before going back to 21:23".
    var why = ""
    var shape: Shape
    /// Where each floating window was, out of sight or not.
    var frames: [CGWindowID: CGRect]
    /// The window each desk focuses when it is shown.
    var focused: [String: CGWindowID]
}

/// The layouts to go back to, newest first.
var history: [SavedLayout] = []
let historyLimit = 10
/// A layout replaced sooner than this was on the way to another one: it is not kept.
let settleTime: TimeInterval = 5

/// The layout on screen, kept up to date at every change, with the time it was put in place.
private var settled: SavedLayout?

/// The layout right now.
func currentLayout() -> SavedLayout {
    func tree(_ node: Node) -> Tree? {
        if let window = node.window { return mac.number(of: window).map(Tree.window) }
        let first = tree(node.first!), second = tree(node.second!)
        guard let first, let second else { return first ?? second }
        return .split(first, second, node.ratio)
    }
    var shape = Shape()
    var frames: [CGWindowID: CGRect] = [:]
    var focused: [String: CGWindowID] = [:]
    for desk in allDesks where !desk.windows.isEmpty {
        var saved = DeskShape(tree: desk.root.flatMap(tree), fullscreen: desk.fullscreen.flatMap(mac.number(of:)))
        for window in desk.floating {
            guard let number = mac.number(of: window) else { continue }
            saved.floating.append(number)
            frames[number] = hidden[window] ?? mac.frame(of: window)
        }
        shape.desks[desk.name] = saved
        if let number = desk.lastFocused.flatMap(mac.number(of:)) { focused[desk.name] = number }
    }
    return SavedLayout(since: mac.now, at: mac.now, shape: shape, frames: frames, focused: focused)
}

/// After every arrange: when the layout changed, the one it replaced goes into the history,
/// if it stayed long enough.
func noteLayout() {
    var now = currentLayout()
    guard var last = settled else { settled = now; return }
    if now.shape.desks == last.shape.desks {
        // Same layout: keep when it started, take the rest (floating frames, focus) as it is now.
        now.since = last.since
        settled = now
        return
    }
    if mac.now.timeIntervalSince(last.since) >= settleTime {
        last.at = mac.now
        keep(last)
    }
    settled = now
}

/// Put a layout at the top of the history, unless it is the one there already.
func keep(_ layout: SavedLayout) {
    guard layout.shape.windowCount > 0, layout.shape.desks != history.first?.shape.desks else { return }
    history.insert(layout, at: 0)
    if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
    log("layout-kept", ["windows": layout.shape.windowCount, "desks": layout.shape.desks.count,
                        "lasted": Int(layout.at.timeIntervalSince(layout.since)), "kept": history.count])
    if let data = try? JSONEncoder().encode(StoredHistory(boot: mac.bootTime, layouts: history)) {
        mac.save(data, as: "history")
    }
}

/// The history as kept between runs. Window numbers only mean something within the same boot.
private struct StoredHistory: Codable {
    let boot: Int
    let layouts: [SavedLayout]
}

/// Read the history the last run kept. Call once, before the first refresh.
func loadHistory() {
    settled = nil
    history = []
    guard let data = mac.saved("history") as? Data,
          let stored = try? JSONDecoder().decode(StoredHistory.self, from: data), stored.boot == mac.bootTime else { return }
    history = stored.layouts
}

/// Put every window back where a saved layout had it. Windows that closed since are left out.
/// Windows opened since stay on the desk they are on, after the others. The layout just before
/// is kept too, so a restore can be undone.
func restore(_ layout: SavedLayout) {
    var now = settled ?? currentLayout()
    now.at = mac.now
    now.why = "before going back to \(clock(layout.at))"
    keep(now)
    // The layout put back is a new start, not a change to keep.
    settled = nil
    var windows: [CGWindowID: Window] = [:]
    var opened: [(window: Window, desk: Desk, floating: Bool)] = []
    let saved = Set(layout.shape.desks.values.flatMap { numbers(in: $0) })
    for desk in orderedDesks() {
        for window in desk.windows {
            guard let number = mac.number(of: window), saved.contains(number) else {
                opened.append((window, desk, desk.floating.contains(window)))
                continue
            }
            windows[number] = window
        }
    }
    log("layout-restored", ["from": stampText(layout.at), "why": layout.why, "windows": windows.count,
                            "openedSince": opened.count])

    func node(_ tree: Tree) -> Node? {
        switch tree {
        case .window(let number): return windows[number].map(Node.init)
        case .split(let a, let b, let ratio):
            let first = node(a), second = node(b)
            guard let first, let second else { return first ?? second }
            let parent = Node(nil)
            parent.first = first
            parent.second = second
            parent.ratio = ratio
            first.parent = parent
            second.parent = parent
            return parent
        }
    }
    for desk in allDesks {
        let shape = layout.shape.desks[desk.name] ?? DeskShape()
        desk.root = shape.tree.flatMap(node)
        desk.floating = shape.floating.compactMap { windows[$0] }
        desk.fullscreen = shape.fullscreen.flatMap { windows[$0] }.flatMap { desk.leaf(of: $0) != nil ? $0 : nil }
        desk.lastFocused = layout.focused[desk.name].flatMap { windows[$0] }.flatMap { desk.windows.contains($0) ? $0 : nil }
    }
    for (window, desk, floating) in opened {
        if floating { desk.floating.append(window) } else { desk.tile(window, beside: nil) }
    }
    // Floating windows go back to their frame now, or when their desk is shown.
    for (number, frame) in layout.frames {
        guard let window = windows[number] else { continue }
        if hidden[window] != nil { hidden[window] = frame } else { mac.setFrame(window, frame) }
    }
    // The desk on screen stays: its windows change.
    arrange()
    if let window = desks[current]!.lastFocused ?? desks[current]!.windows.first { mac.focus(window) }
}

private func numbers(in desk: DeskShape) -> [CGWindowID] {
    func leaves(_ tree: Tree) -> [CGWindowID] {
        switch tree {
        case .window(let number): [number]
        case .split(let a, let b, _): leaves(a) + leaves(b)
        }
    }
    return (desk.tree.map(leaves) ?? []) + desk.floating
}

private func stampText(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

/// A time for the menu: "21:23" today, "Mon 21:23" before.
func clock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: mac.now) ? "HH:mm" : "EEE HH:mm"
    return formatter.string(from: date)
}
