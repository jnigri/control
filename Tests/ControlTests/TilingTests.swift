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

    // Picking a window with Command + Tab, the Dock or Command + `.

    @Test func pickingAWindowOnAHiddenDeskShowsThatDesk() {
        let a = fake.opens(1)
        show("2")
        let b = fake.opens(2)
        fake.focus(a)
        refresh()
        #expect(current == "1" && previous == "2")
        #expect(fake.frames[a] == whole)
        #expect(visibleArea(of: b, on: fake) <= 1)
    }

    @Test func anEmptyDeskLeavesNoWindowFocused() {
        let a = fake.opens(1)
        show("2")
        #expect(fake.focused == nil)
        refresh()
        // A click on the app in the Dock: its window has the focus again.
        fake.focus(a)
        refresh()
        #expect(current == "1")
        #expect(fake.frames[a] == whole)
    }

    @Test func pickingAWindowCoveredByAnotherOnItsDeskShowsIt() {
        let a = fake.opens(1), b = fake.opens(2)
        toggleFullscreen()
        show("2")
        fake.focus(a)
        refresh()
        #expect(current == "1")
        #expect(desks["1"]!.fullscreen == nil)
        #expect(fake.frames[a] == leftHalf && fake.frames[b] == rightHalf)
    }

    /// When a window closes, macOS gives the focus to another one, maybe on a hidden desk.
    /// That is not the user picking it: the desk on screen stays, and one of its windows gets the focus.
    @Test func closingAWindowStaysOnTheDesk() {
        show("2")
        let b = fake.opens(2)
        show("1")
        let a = fake.opens(1)
        show("2")
        let c = fake.opens(3)
        fake.closes(c)   // the focus falls on `a`, the last window opened before it
        #expect(current == "2")
        #expect(fake.focused == b)
        #expect(visibleArea(of: a, on: fake) <= 1)
        // A moment later, picking `a` does bring up its desk.
        fake.now = fake.now.addingTimeInterval(closeTime)
        fake.focus(a)
        refresh()
        #expect(current == "1")
    }

    @Test func closingTheLastWindowOfADeskLeavesNoWindowFocused() {
        let a = fake.opens(1)
        show("2")
        let b = fake.opens(2)
        fake.closes(b)
        #expect(current == "2")
        #expect(fake.focused == nil)
        #expect(visibleArea(of: a, on: fake) <= 1)
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

    /// After a switch to an empty desk, macOS may leave the focus on a window that was just hidden.
    /// Keys leave that window you cannot see alone.
    @Test func keysLeaveAHiddenWindowAlone() {
        let a = fake.opens(1)
        show("2")
        fake.focused = a
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

    /// Before, the new window took its tile, and the fullscreen window stayed behind it, covering the rest.
    @Test func aNewWindowEndsFullscreen() {
        let a = fake.opens(1), b = fake.opens(2)
        toggleFullscreen()
        let c = fake.opens(3)
        #expect(desks["1"]!.fullscreen == nil)
        #expect(fake.frames == [a: leftHalf, b: topRight, c: bottomRight])
    }

    @Test func aWindowSentToAFullscreenDeskEndsFullscreen() {
        let a = fake.opens(1)
        send(to: "2")
        toggleFullscreen()
        show("1")
        let b = fake.opens(2)
        send(to: "2")
        #expect(desks["2"]!.fullscreen == nil)
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
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

    /// Apps report no windows while the Mac sleeps, and for a moment after it wakes up.
    /// Before, the windows were taken for closed, and all came back on the desk you were on.
    @Test func sleepingKeepsEveryWindowOnItsDesk() {
        let a = fake.opens(1), b = fake.opens(2)
        let c = fake.opens(3)
        send(to: "2")
        let before = fake.frames
        asleep = true
        fake.unreported = [a, b, c]
        refresh()
        asleep = false
        resume()
        #expect(desks["1"]!.tiled == [a, b])
        fake.unreported = [c]
        refresh()
        fake.unreported = []
        refresh()
        #expect(desks["1"]!.tiled == [a, b])
        #expect(desks["2"]!.tiled == [c])
        #expect(fake.frames == before)
    }

    /// A window that closes while apps catch up keeps its tile for a moment, then gives it up.
    @Test func aWindowClosedAfterWakingUpLeavesItsDeskOnceAppsCaughtUp() {
        let a = fake.opens(1), b = fake.opens(2)
        locked = true
        locked = false
        resume()
        fake.closes(b)
        #expect(desks["1"]!.tiled == [a, b])
        fake.now = fake.now.addingTimeInterval(catchUpTime)
        refresh()
        #expect(desks["1"]!.tiled == [a])
        #expect(fake.frames[a] == whole)
    }

    /// Monitors come and go while the Mac sleeps, and macOS brings the parked windows back into view.
    /// Before, they stayed in sight once the monitors were back as they were.
    @Test func windowsBroughtBackIntoViewDuringSleepAreParkedAgain() {
        let a = fake.opens(1)
        send(to: "2")
        show("1")
        let b = fake.opens(2)
        let parked = fake.frames[a]!
        asleep = true
        fake.plugs([monitor(1, x: 3000)])
        fake.plugs([mainMonitor])
        #expect(fake.frames[a] != parked)
        asleep = false
        resume()
        #expect(fake.frames[a] == parked)
        #expect(fake.frames[b] == whole)
    }

    /// An app busy waking up gives no answer, long after the others caught up.
    /// Before, its windows were taken for closed, and came back on the desk you were on.
    @Test func anAppThatGivesNoAnswerKeepsItsWindowsOnTheirDesks() {
        let a = fake.opens(1), b = fake.opens(2)
        send(to: "2")
        show("1")
        let before = fake.frames
        fake.silent = [b]
        fake.now = fake.now.addingTimeInterval(catchUpTime * 10)
        refresh()
        #expect(desks["2"]!.tiled == [b])
        fake.silent = []
        refresh()
        #expect(desks["1"]!.tiled == [a])
        #expect(desks["2"]!.tiled == [b])
        #expect(fake.frames == before)
    }
}
