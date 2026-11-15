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

/// A split never gives one side less than this share.
let ratioLimits: ClosedRange<CGFloat> = 0.1...0.9

/// Cut a rect in two along its longer side.
private func cut(_ rect: CGRect, at ratio: CGFloat) -> (CGRect, CGRect) {
    rect.width >= rect.height
        ? rect.divided(atDistance: rect.width * ratio, from: .minXEdge)
        : rect.divided(atDistance: rect.height * ratio, from: .minYEdge)
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
        var frames = tiles(in: area)
        if let fullscreen { frames[fullscreen] = area }
        return frames
    }

    /// Where each tiled window sits in the layout tree, as if none covered the whole desk.
    func tiles(in area: CGRect) -> [Window: CGRect] {
        var frames: [Window: CGRect] = [:]
        func split(_ node: Node, _ rect: CGRect) {
            if let window = node.window {
                // A tile thinner than the gap keeps all of its space: there is no room for a gap.
                frames[window] = min(rect.width, rect.height) > gap ? rect.insetBy(dx: gap / 2, dy: gap / 2) : rect
                return
            }
            let (a, b) = cut(rect, at: node.ratio)
            split(node.first!, a)
            split(node.second!, b)
        }
        if let root { split(root, area.insetBy(dx: gap / 2, dy: gap / 2)) }
        return frames
    }

    /// The user dragged edges of a tiled window with the mouse. The split behind each edge
    /// that moved follows it, so the neighbors give or take the space.
    func resize(_ window: Window, from before: CGRect, to after: CGRect, in area: CGRect) {
        // For each edge: how far it moved, where its split should now be, which way that split
        // runs, and on which side of it the window sits.
        let edges: [(moved: CGFloat, to: CGFloat, wide: Bool, first: Bool)] = [
            (after.minX - before.minX, after.minX - gap / 2, true, false),    // left
            (after.maxX - before.maxX, after.maxX + gap / 2, true, true),     // right
            (after.minY - before.minY, after.minY - gap / 2, false, false),   // top
            (after.maxY - before.maxY, after.maxY + gap / 2, false, true),    // bottom
        ]
        for edge in edges where abs(edge.moved) > 2 {
            // Walk down to the window. The last split that fits is the one right behind the edge.
            // No split fits an edge that touches the border of the monitor.
            var found: (split: Node, rect: CGRect)?
            var node = root
            var rect = area.insetBy(dx: gap / 2, dy: gap / 2)
            while let split = node, split.window == nil {
                let inFirst = split.first!.leaves.contains { $0.window == window }
                if (rect.width >= rect.height) == edge.wide && inFirst == edge.first { found = (split, rect) }
                let (a, b) = cut(rect, at: split.ratio)
                node = inFirst ? split.first : split.second
                rect = inFirst ? a : b
            }
            guard let found else { continue }
            let ratio = edge.wide ? (edge.to - found.rect.minX) / found.rect.width
                                  : (edge.to - found.rect.minY) / found.rect.height
            found.split.ratio = min(ratioLimits.upperBound, max(ratioLimits.lowerBound, ratio))
        }
    }
}
