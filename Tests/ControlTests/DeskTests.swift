import CoreGraphics
import Testing
@testable import Control

// The layout tree on its own: no Mac, real or fake.

@Suite struct DeskTests {
    let area = rect(0, 20, 1000, 800)
    let desk = Desk("1")
    let a = window(1), b = window(2), c = window(3)

    @Test func oneWindowFillsTheDesk() {
        desk.tile(a, beside: nil)
        #expect(desk.layout(in: area) == [a: whole])
    }

    @Test func secondWindowSplitsTheSpaceSideBySide() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        #expect(desk.layout(in: area) == [a: leftHalf, b: rightHalf])
    }

    @Test func aTallTileSplitsTopAndBottom() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.tile(c, beside: b)
        #expect(desk.layout(in: area) == [a: leftHalf, b: topRight, c: bottomRight])
        #expect(desk.tiled == [a, b, c])
    }

    @Test func withoutATargetTheLastWindowSplits() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: nil)
        desk.tile(c, beside: nil)
        #expect(desk.layout(in: area) == [a: leftHalf, b: topRight, c: bottomRight])
    }

    @Test func aClosedWindowGivesItsSpaceToItsNeighbor() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.tile(c, beside: b)
        desk.remove(b)
        #expect(desk.layout(in: area) == [a: leftHalf, c: rightHalf])
        desk.remove(a)
        #expect(desk.layout(in: area) == [c: whole])
        desk.remove(c)
        #expect(desk.root == nil)
        #expect(desk.layout(in: area).isEmpty)
    }

    @Test func openingThenClosingAWindowChangesNothing() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.root!.ratio = 0.3
        let before = desk.layout(in: area)
        desk.tile(c, beside: a)
        desk.remove(c)
        #expect(desk.layout(in: area) == before)
    }

    @Test func removingForgetsEverythingAboutTheWindow() {
        desk.tile(a, beside: nil)
        desk.floating.append(b)
        desk.fullscreen = a
        desk.lastFocused = b
        desk.remove(a)
        desk.remove(b)
        desk.remove(c)   // never was here: nothing happens
        #expect(desk.windows.isEmpty)
        #expect(desk.fullscreen == nil)
        #expect(desk.lastFocused == nil)
    }

    @Test func aFullscreenWindowCoversTheWholeArea() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.fullscreen = b
        #expect(desk.layout(in: area) == [a: leftHalf, b: area])
        #expect(desk.tiles(in: area) == [a: leftHalf, b: rightHalf])
    }

    @Test func aTileThinnerThanTheGapStillHasAFrame() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.root!.ratio = 0.9
        // In a tiny area, the second window gets a strip 5 points wide: no room for an 8-point gap.
        let frames = desk.layout(in: rect(0, 0, 60, 30))
        #expect(frames.values.allSatisfy { !$0.isNull && $0.width > 0 && $0.height > 0 })
    }

    // Dragging edges with the mouse.

    @Test func draggingTheRightEdgeMovesTheSplit() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.resize(a, from: leftHalf, to: rect(8, 28, 688, 784), in: area)
        #expect(same(desk.layout(in: area), [a: rect(8, 28, 688, 784), b: rect(704, 28, 288, 784)]))
    }

    @Test func draggingTheLeftEdgeOfTheRightWindowMovesTheSameSplit() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.resize(b, from: rightHalf, to: rect(304, 28, 688, 784), in: area)
        #expect(same(desk.layout(in: area), [a: rect(8, 28, 288, 784), b: rect(304, 28, 688, 784)]))
    }

    @Test func draggingACornerMovesBothSplits() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.tile(c, beside: b)
        // The bottom-left corner of the top-right window: wider and taller.
        desk.resize(b, from: topRight, to: rect(404, 28, 588, 488), in: area)
        #expect(same(desk.layout(in: area), [a: rect(8, 28, 388, 784), b: rect(404, 28, 588, 488), c: rect(404, 524, 588, 288)]))
    }

    @Test func anEdgeOnTheBorderOfTheMonitorGoesBack() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        // The left window's left, top and bottom edges have no split behind them.
        desk.resize(a, from: leftHalf, to: rect(100, 100, 396, 600), in: area)
        #expect(desk.layout(in: area) == [a: leftHalf, b: rightHalf])
    }

    @Test func aSplitNeverSqueezesAWindowAway() {
        desk.tile(a, beside: nil)
        desk.tile(b, beside: a)
        desk.resize(a, from: leftHalf, to: rect(8, 28, 980, 784), in: area)
        #expect(desk.root!.ratio == 0.9)
        desk.resize(a, from: leftHalf, to: rect(8, 28, 10, 784), in: area)
        #expect(desk.root!.ratio == 0.1)
    }

    /// Many random layouts. Whatever happens, the tiles fill the desk exactly, with no overlap.
    @Test func randomLayoutsAlwaysFillTheDesk() {
        var random = Seeded(seed: 7)
        for _ in 0..<200 {
            let desk = Desk("1")
            var next = 0
            for _ in 0..<40 {
                let tiled = desk.tiled
                // Past a handful of windows, tiles get too thin to mean anything.
                switch tiled.count > 6 ? 0 : Int.random(in: 0..<4, using: &random) {
                case 0 where !tiled.isEmpty:
                    desk.remove(tiled.randomElement(using: &random)!)
                case 1 where tiled.count > 1:
                    let moved = tiled.randomElement(using: &random)!
                    let frame = desk.tiles(in: area)[moved]!
                    let grown = rect(frame.minX + .random(in: -200...200, using: &random),
                                     frame.minY + .random(in: -200...200, using: &random),
                                     max(50, frame.width + .random(in: -200...200, using: &random)),
                                     max(50, frame.height + .random(in: -200...200, using: &random)))
                    desk.resize(moved, from: frame, to: grown, in: area)
                default:
                    next += 1
                    desk.tile(window(next), beside: tiled.randomElement(using: &random))
                }
                expectSound(desk, in: area)
            }
        }
    }
}

/// The tree is well formed, and its tiles cover the area without overlapping.
func expectSound(_ desk: Desk, in area: CGRect) {
    func check(_ node: Node) {
        guard node.window == nil else {
            #expect(node.first == nil && node.second == nil)
            return
        }
        #expect(node.first?.parent === node && node.second?.parent === node)
        #expect(ratioLimits.contains(node.ratio))
        check(node.first!)
        check(node.second!)
    }
    if let root = desk.root {
        #expect(root.parent == nil)
        check(root)
    }
    let tiles = Array(desk.tiles(in: area).values)
    #expect(tiles.count == desk.tiled.count)
    #expect(Set(desk.tiled).count == desk.tiled.count)
    let inside = area.insetBy(dx: gap / 2, dy: gap / 2)
    var covered: CGFloat = 0
    for (index, tile) in tiles.enumerated() {
        #expect(inside.insetBy(dx: -0.01, dy: -0.01).contains(tile))
        covered += (tile.width + gap) * (tile.height + gap)
        for other in tiles[(index + 1)...] {
            let overlap = tile.intersection(other)
            #expect(overlap.width < 0.01 || overlap.height < 0.01)
        }
    }
    // Tiles thinner than the gap have no gap around them, so the sum below does not hold.
    if !tiles.isEmpty, tiles.allSatisfy({ min($0.width, $0.height) > gap }) { #expect(abs(covered - (area.width - gap) * (area.height - gap)) < 1) }
}

/// Equal, give or take a rounding error.
func same(_ a: CGRect?, _ b: CGRect?) -> Bool {
    guard let a, let b else { return a == b }
    return abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01
        && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
}

func same(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }

func same(_ a: [Window: CGRect], _ b: [Window: CGRect]) -> Bool {
    a.count == b.count && a.allSatisfy { same($0.value, b[$0.key]) }
}

/// Random numbers that are the same on every run, so a failure can be repeated.
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
