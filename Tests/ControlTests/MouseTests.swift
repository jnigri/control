import CoreGraphics
import Testing
@testable import Control

// Dragging and resizing windows with the mouse.

extension ControlTests {
    /// Before, a window resized by hand kept its size and overlapped its neighbors until the next key.
    @Test func resizingAWindowWithTheMouseResizesItsNeighbor() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.drags(a, to: rect(8, 28, 688, 784))
        #expect(same(fake.frames, [a: rect(8, 28, 688, 784), b: rect(704, 28, 288, 784)]))
        // The new split stays for the next windows and keys.
        refresh()
        #expect(same(fake.frames, [a: rect(8, 28, 688, 784), b: rect(704, 28, 288, 784)]))
    }

    @Test func resizingFromTheOtherSideWorksToo() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        // The top edge of the bottom-right window, dragged up.
        fake.drags(c, to: rect(504, 224, 488, 588))
        #expect(same(fake.frames, [a: leftHalf, b: rect(504, 28, 488, 188), c: rect(504, 224, 488, 588)]))
    }

    @Test func resizingPastTheBorderOfTheMonitorSnapsBack() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.drags(b, to: rect(504, 28, 300, 500))   // right and bottom edges: no neighbor there
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
    }

    @Test func droppingAWindowOnAnotherTradesPlaces() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        fake.drags(a, to: rect(550, 500, 488, 784), pointer: CGPoint(x: 700, y: 510))
        #expect(fake.frames == [c: leftHalf, b: topRight, a: bottomRight])
    }

    @Test func droppingAWindowNowhereSnapsItBack() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.drags(a, to: rect(60, 90, 488, 784), pointer: CGPoint(x: 200, y: 100))
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
        // In the gap between two tiles: back too.
        fake.drags(a, to: rect(300, 90, 488, 784), pointer: CGPoint(x: 500, y: 100))
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
    }

    @Test func draggingAWindowToAnEmptyMonitorMovesItThere() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1), b = fake.opens(2)
        fake.drags(b, to: rect(1200, 200, 488, 784))
        #expect(monitorDesks[2]!.tiled == [b])
        #expect(fake.frames == [a: whole, b: whole.applying(onRight)])
    }

    @Test func droppingAWindowOnATileOfAnotherMonitorSplitsThatTile() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1)
        let x = fake.opens(2, on: rightMonitor), y = fake.opens(3, on: rightMonitor)
        fake.drags(a, to: rect(1100, 100, 984, 784), pointer: CGPoint(x: 1200, y: 110))
        #expect(desks["1"]!.windows.isEmpty)
        #expect(monitorDesks[2]!.tiled == [x, a, y])
        #expect(fake.frames[x] == rect(8, 28, 488, 388).applying(onRight))
        #expect(fake.frames[a] == rect(8, 424, 488, 388).applying(onRight))
        #expect(fake.frames[y] == rightHalf.applying(onRight))
    }

    /// Before, a dialog dragged to the other monitor still belonged to its old desk,
    /// and vanished when the main monitor changed desk.
    @Test func draggingAFloatingWindowToAnotherMonitorChangesItsDesk() {
        fake.screens = [mainMonitor, rightMonitor]
        let dialog = fake.opens(1, dialog: true)
        fake.drags(dialog, to: rect(1400, 300, 400, 300))
        #expect(monitorDesks[2]!.floating == [dialog])
        show("2")
        #expect(fake.frames[dialog] == rect(1400, 300, 400, 300))
    }

    @Test func aFloatingWindowDraggedAroundItsOwnMonitorStaysWhereItIsDropped() {
        let a = fake.opens(1)
        let dialog = fake.opens(2, dialog: true)
        fake.drags(dialog, to: rect(50, 60, 500, 350))
        #expect(fake.frames == [a: whole, dialog: rect(50, 60, 500, 350)])
    }

    /// Terminals only take sizes that fit whole lines of text. Moving one is not resizing it.
    @Test func movingAWindowThatDidNotTakeItsExactTileIsNotAResize() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.minimums[a] = CGSize(width: 520, height: 300)
        refresh()
        #expect(fake.frames[a] == rect(8, 28, 520, 784))
        fake.drags(a, to: rect(30, 60, 520, 784), pointer: CGPoint(x: 100, y: 70))
        #expect(desks["1"]!.root!.ratio == 0.5)
        #expect(fake.frames == [a: rect(8, 28, 520, 784), b: rightHalf])
    }

    @Test func draggingAFullscreenWindowSnapsItBack() {
        fake.opens(1)
        let b = fake.opens(2)
        toggleFullscreen()
        fake.drags(b, to: rect(100, 100, 600, 500), pointer: CGPoint(x: 300, y: 110))
        #expect(fake.frames[b] == mainMonitor.area)
        #expect(desks["1"]!.root!.ratio == 0.5)
    }

    /// The mouse button can be down for something else (selecting text) while Control itself
    /// moves windows. That is not a drag: nothing must trade places.
    @Test func aWindowMovedByControlIsNotADrag() {
        let a = fake.opens(1), b = fake.opens(2)
        dropped(a, at: CGPoint(x: 700, y: 400))   // a sits on its tile, the pointer is over b
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
        // A dialog is where it is, the pointer is on the other monitor.
        fake.screens = [mainMonitor, rightMonitor]
        let dialog = fake.opens(3, dialog: true)
        dropped(dialog, at: CGPoint(x: 1500, y: 400))
        #expect(desks["1"]!.floating == [dialog])
    }

    @Test func draggingAWindowWeDoNotManageDoesNothing() {
        let a = fake.opens(1)
        dropped(window(99), at: CGPoint(x: 100, y: 100))
        #expect(fake.frames == [a: whole])
    }
}
