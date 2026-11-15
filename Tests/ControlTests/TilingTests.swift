import CoreGraphics
import Testing
@testable import Control

// Windows opening and closing, desks, keys.

extension ControlTests {
    @Test func theFirstWindowFillsTheMonitor() {
        let a = fake.opens(1)
        #expect(fake.frames[a] == whole)
        #expect(desks["1"]!.tiled == [a])
    }

    @Test func aNewWindowSplitsTheLastOne() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        #expect(fake.frames == [a: leftHalf, b: topRight, c: bottomRight])
    }

    @Test func aNewWindowSplitsTheFocusedOne() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.focus(a)
        refresh()
        let c = fake.opens(3)
        #expect(fake.frames == [a: rect(8, 28, 488, 388), c: rect(8, 424, 488, 388), b: rightHalf])
    }

    @Test func aClosedWindowGivesItsSpaceBack() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        fake.closes(b)
        #expect(fake.frames == [a: leftHalf, c: rightHalf])
        fake.closes(a)
        fake.closes(c)
        #expect(allDesks.allSatisfy { $0.windows.isEmpty })
    }

    @Test func aMinimizedWindowLeavesAndComesBack() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.unreported = [a]
        refresh()
        #expect(fake.frames[b] == whole)
        fake.unreported = []
        refresh()
        #expect(desks["1"]!.tiled == [b, a])
        #expect(fake.frames[a] == rightHalf)
    }

    @Test func dialogsFloatWhereTheyAre() {
        let a = fake.opens(1)
        let dialog = fake.opens(2, dialog: true)
        let b = fake.opens(3)
        #expect(desks["1"]!.floating == [dialog])
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))
        #expect(fake.frames[a] == leftHalf)
        #expect(fake.frames[b] == rightHalf)
    }

    @Test func anAppThatRefusesToShrinkSticksOutAndNothingElseMoves() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.minimums[b] = CGSize(width: 700, height: 300)
        refresh()
        refresh()
        #expect(fake.frames[a] == leftHalf)
        #expect(fake.frames[b] == rect(504, 28, 700, 784))
        #expect(desks["1"]!.root!.ratio == 0.5)
    }

    @Test func refreshingAgainChangesNothing() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        send(to: "2")
        let before = fake.frames
        for _ in 0..<3 { refresh() }
        #expect(fake.frames == before)
        _ = (a, b, c)
    }

    // Desks.

    @Test func showingAnotherDeskHidesTheWindowsAndBringsThemBack() {
        let a = fake.opens(1)
        let dialog = fake.opens(2, dialog: true)
        show("2")
        #expect(current == "2" && previous == "1")
        #expect(visibleArea(of: a, on: fake) <= 1)
        #expect(visibleArea(of: dialog, on: fake) <= 1)
        show(previous)
        #expect(current == "1" && previous == "2")
        #expect(fake.frames[a] == whole)
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))
    }

    @Test func aWindowOpenedOnAnotherDeskStaysThere() {
        let a = fake.opens(1)
        show("2")
        let b = fake.opens(2)
        #expect(desks["2"]!.tiled == [b])
        #expect(fake.frames[b] == whole)
        #expect(visibleArea(of: a, on: fake) <= 1)
    }

    @Test func showingADeskFocusesItsLastWindow() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.focus(a)
        refresh()
        show("2")
        let c = fake.opens(3)
        refresh()
        show("1")
        #expect(fake.focused == a)
        show("2")
        #expect(fake.focused == c)
        _ = b
    }

    @Test func sendingAWindowToADeskFollowsIt() {
        let a = fake.opens(1), b = fake.opens(2)
        send(to: "5")
        #expect(current == "5" && previous == "1")
        #expect(desks["5"]!.tiled == [b])
        #expect(fake.frames[b] == whole)
        #expect(fake.focused == b)
        #expect(visibleArea(of: a, on: fake) <= 1)
        show("1")
        #expect(fake.frames[a] == whole)
    }

    @Test func sendingAFloatingWindowKeepsItFloating() {
        let dialog = fake.opens(1, dialog: true)
        send(to: "2")
        #expect(desks["2"]!.floating == [dialog])
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))
    }

    /// Before, this took the window out and tiled it again somewhere else on the same desk.
    @Test func sendingAWindowToItsOwnDeskChangesNothing() {
        let a = fake.opens(1)
        fake.opens(2)
        fake.opens(3)
        fake.focus(a)
        refresh()
        let before = fake.frames
        send(to: "1")
        #expect(fake.frames == before)
    }

    /// After a switch to an empty desk, the focus is still on a window that was just hidden.
    /// Before, keys still acted on that window you could not see.
    @Test func keysLeaveAHiddenWindowAlone() {
        let a = fake.opens(1)
        show("2")
        #expect(fake.focused == a)
        toggleFullscreen()
        toggleFloating()
        send(to: "3")
        resize(by: 0.2)
        #expect(current == "2")
        #expect(desks["1"]!.tiled == [a])
        #expect(desks["1"]!.fullscreen == nil)
        #expect(visibleArea(of: a, on: fake) <= 1)
    }

    // Keys.

    @Test func focusMovesToTheNeighbor() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        fake.focus(a)
        moveFocus(.right)
        #expect(fake.focused == b)   // straight ahead from the top wins
        moveFocus(.down)
        #expect(fake.focused == c)
        moveFocus(.left)
        #expect(fake.focused == a)
        moveFocus(.left)
        #expect(fake.focused == a)   // nothing that way
    }

    /// Before, with two windows just as close, the pick changed from one run of Control to the next.
    @Test func betweenTwoWindowsJustAsCloseTheUpperOneWins() {
        let from = leftHalf
        let both = [(key: "top", value: topRight), (key: "bottom", value: bottomRight)]
        #expect(closest(both, to: from, .right) == "top")
        #expect(closest(both.reversed(), to: from, .right) == "top")
        let sideBySide = [(key: "left", value: rect(8, 28, 240, 300)), (key: "right", value: rect(256, 28, 240, 300))]
        #expect(closest(sideBySide, to: rect(8, 424, 488, 388), .up) == "left")
        #expect(closest(sideBySide.reversed(), to: rect(8, 424, 488, 388), .up) == "left")
    }

    @Test func swappingTradesPlaces() {
        let a = fake.opens(1), b = fake.opens(2)
        swap(.left)
        #expect(fake.frames == [a: rightHalf, b: leftHalf])
        #expect(fake.focused == b)
        swap(.up)   // nothing that way
        #expect(fake.frames == [a: rightHalf, b: leftHalf])
    }

    @Test func growingAndShrinkingMovesTheSplit() {
        let a = fake.opens(1), b = fake.opens(2)
        resize(by: 0.25)   // b is second: growing it shrinks the first share
        #expect(desks["1"]!.root!.ratio == 0.25)
        #expect(same(fake.frames[a], rect(8, 28, 240, 784)))
        #expect(same(fake.frames[b], rect(256, 28, 736, 784)))
        for _ in 0..<10 { resize(by: 0.25) }
        #expect(desks["1"]!.root!.ratio == 0.1)
        for _ in 0..<10 { resize(by: -0.25) }
        #expect(desks["1"]!.root!.ratio == 0.9)
    }

    @Test func fullscreenCoversTheDeskAndGoesBack() {
        let a = fake.opens(1), b = fake.opens(2)
        toggleFullscreen()
        #expect(fake.frames[b] == mainMonitor.area)
        #expect(fake.frames[a] == leftHalf)
        toggleFullscreen()
        #expect(fake.frames[b] == rightHalf)
    }

    @Test func floatingAWindowFreesItsTile() {
        let a = fake.opens(1), b = fake.opens(2)
        toggleFloating()
        #expect(desks["1"]!.floating == [b])
        #expect(fake.frames[a] == whole)
        #expect(same(fake.frames[b], mainMonitor.area.insetBy(dx: 1000 / 6, dy: 800 / 6)))
        toggleFloating()
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
    }

    // The lock screen.

    /// While the screen is locked, apps report no windows at all.
    @Test func lockingTheScreenKeepsEveryWindowOnItsDesk() {
        let a = fake.opens(1), b = fake.opens(2)
        let c = fake.opens(3)
        send(to: "2")
        let before = fake.frames
        locked = true
        fake.unreported = [a, b, c]
        refresh()
        dropped(a, at: .zero)
        #expect(desks["1"]!.tiled == [a, b])
        #expect(desks["2"]!.tiled == [c])
        fake.unreported = []
        locked = false
        refresh()
        #expect(fake.frames == before)
    }
}
