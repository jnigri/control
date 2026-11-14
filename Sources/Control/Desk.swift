import CoreGraphics

/// One node of a desk's layout tree.
/// A leaf holds a window. An inner node splits its space in two, along the longer side.
final class Node {
    var window: Window?
    var first: Node?
    var second: Node?
    var ratio: CGFloat = 0.5       // share of the space that goes to `first`
    weak var parent: Node?

    init(_ window: Window?) { self.window = window }

    /// All leaves, from left/top to right/bottom.
    var leaves: [Node] { window != nil ? [self] : first!.leaves + second!.leaves }
}

/// A group of windows shown together on one monitor.
final class Desk {
    let name: String               // the desk key, like "1" or "M"
    var root: Node?                // tiled windows
    var floating: [Window] = []    // windows we never move, except to hide them
    var fullscreen: Window?        // a tiled window that covers the whole desk
    var lastFocused: Window?       // gets focus when the desk is shown again

    init(_ name: String) { self.name = name }

    var tiled: [Window] { root?.leaves.map { $0.window! } ?? [] }
    var windows: [Window] { tiled + floating }

    func leaf(of window: Window) -> Node? { root?.leaves.first { $0.window == window } }

    /// Split the target window's space in two: old window first, new one second.
    /// Without a target, split the last window.
    func tile(_ window: Window, beside target: Window?) {
        let new = Node(window)
        guard let root else { self.root = new; return }
        let old = target.flatMap(leaf(of:)) ?? root.leaves.last!
        // `old` turns into an inner node holding a copy of itself and the new leaf.
        let copy = Node(old.window)
        old.window = nil
        old.first = copy
        old.second = new
        old.ratio = 0.5
        copy.parent = old
        new.parent = old
    }

    func remove(_ window: Window) {
        floating.removeAll { $0 == window }
        if fullscreen == window { fullscreen = nil }
        if lastFocused == window { lastFocused = nil }
        guard let gone = leaf(of: window) else { return }
        guard let parent = gone.parent else { root = nil; return }
        // The sibling moves up into the parent, so it gets the whole space.
        let sibling = parent.first === gone ? parent.second! : parent.first!
        parent.window = sibling.window
        parent.first = sibling.first
        parent.second = sibling.second
        parent.ratio = sibling.ratio
        parent.first?.parent = parent
        parent.second?.parent = parent
    }

    /// Where each tiled window goes when this desk fills `area`.
    func layout(in area: CGRect) -> [Window: CGRect] {
        var frames: [Window: CGRect] = [:]
        func split(_ node: Node, _ rect: CGRect) {
            if let window = node.window {
                frames[window] = rect.insetBy(dx: gap / 2, dy: gap / 2)
                return
            }
            let (a, b) = rect.width >= rect.height
                ? rect.divided(atDistance: rect.width * node.ratio, from: .minXEdge)
                : rect.divided(atDistance: rect.height * node.ratio, from: .minYEdge)
            split(node.first!, a)
            split(node.second!, b)
        }
        if let root { split(root, area.insetBy(dx: gap / 2, dy: gap / 2)) }
        if let fullscreen { frames[fullscreen] = area }
        return frames
    }
}
