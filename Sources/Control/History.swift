import Foundation
import CoreGraphics

// Layouts to go back to. Control keeps a copy of the layout before anything that may undo it: the
// screen locking, the Mac sleeping, monitors changing, several windows going missing at once, and
// every few minutes. The menu bar panel lists them: click one to put every window back where it was.
// Windows are kept by number, which lasts as long as the window. They are kept in memory only.

/// A desk's layout tree, by window number.
indirect enum Tree: Equatable {
    case window(CGWindowID)
    case split(Tree, Tree, CGFloat)
}

/// What a desk held.
struct DeskShape: Equatable {
    var tree: Tree?
    var floating: [CGWindowID] = []
    var fullscreen: CGWindowID?
}

/// Which window is where, without the frames. Two layouts with the same shape are the same layout.
struct Shape: Equatable {
    var desks: [String: DeskShape] = [:]
    var current = ""
    var previous = ""

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

struct SavedLayout {
    let at: Date
    /// What was about to happen, like "before the screen locked".
    let why: String
    let shape: Shape
    /// Where each floating window was, out of sight or not.
    let frames: [CGWindowID: CGRect]
    /// The window each desk focuses when it is shown.
    let focused: [String: CGWindowID]
}

/// The layouts to go back to, newest first.
var history: [SavedLayout] = []
let historyLimit = 10
/// How often the layout is kept anyway, when it changed meanwhile.
let historyTime: TimeInterval = 600

/// The layout right now.
func currentLayout(_ why: String) -> SavedLayout {
    func tree(_ node: Node) -> Tree? {
        if let window = node.window { return mac.number(of: window).map(Tree.window) }
        let first = tree(node.first!), second = tree(node.second!)
        guard let first, let second else { return first ?? second }
        return .split(first, second, node.ratio)
    }
    var shape = Shape(current: current, previous: previous)
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
    return SavedLayout(at: mac.now, why: why, shape: shape, frames: frames, focused: focused)
}

/// Keep the layout as it is now, unless it is the one kept last.
func saveLayout(_ why: String) {
    let layout = currentLayout(why)
    guard layout.shape.windowCount > 0, layout.shape != history.first?.shape else { return }
    history.insert(layout, at: 0)
    if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
    log("layout-saved", ["why": why, "windows": layout.shape.windowCount, "kept": history.count])
}

/// Put every window back where a saved layout had it. Windows that closed since are left out.
/// Windows opened since stay on the desk they are on, after the others. The layout just before
/// is kept too, so a restore can be undone.
func restore(_ layout: SavedLayout) {
    saveLayout("before going back to \(clock(layout.at))")
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
    // The desk on the main monitor, unless an extra monitor shows it now.
    if !onMonitor(desks[layout.shape.current]!) { current = layout.shape.current }
    if !onMonitor(desks[layout.shape.previous]!) { previous = layout.shape.previous }
    activeDesk = desks[current]
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
