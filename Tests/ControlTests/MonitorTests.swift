import CoreGraphics
import Testing
@testable import Control

// Extra monitors: plugging, unplugging, waking up, and moving windows between them.

let onRight = CGAffineTransform(translationX: 1000, y: 0)

extension ControlTests {
    @Test func anExtraMonitorGetsItsOwnDesk() {
        let a = fake.opens(1)
        fake.screens = [mainMonitor, rightMonitor]
        refresh()
        #expect(fake.frames[a] == whole)
        let x = fake.opens(2, on: rightMonitor)
        #expect(monitorDesks[2]!.tiled == [x])
        #expect(fake.frames[x] == whole.applying(onRight))
        // The main monitor changes desk. The other one keeps its windows.
        show("2")
        #expect(visibleArea(of: a, on: fake) <= 1)
        #expect(fake.frames[x] == whole.applying(onRight))
    }

    /// The monitor is there, but Control has not heard about it yet. Before, this crashed.
    @Test func aKeyPressedRightAfterPluggingAMonitorWorks() {
        let a = fake.opens(1)
        fake.screens = [mainMonitor, rightMonitor]
        moveFocus(.right)
        swap(.up)
        show("2")
        show("1")
        #expect(monitorDesks[2] != nil)
        #expect(fake.frames[a] == whole)
    }

    // Each extra monitor takes a desk with a key: 0 for the first one, then 9, then 8...

    @Test func theFirstExtraMonitorTakesDeskZeroAndTheNextOneNine() {
        let left = monitor(3, x: -1000)
        fake.screens = [mainMonitor, rightMonitor]
        refresh()
        #expect(monitorDesks[2] === desks["0"])
        fake.screens = [mainMonitor, rightMonitor, left]
        refresh()
        #expect(monitorDesks[2] === desks["0"])
        #expect(monitorDesks[3] === desks["9"])
        // The first one leaves and comes back: each keeps its desk.
        fake.screens = [mainMonitor, left]
        refresh()
        #expect(monitorDesks[3] === desks["9"])
        fake.screens = [mainMonitor, left, rightMonitor]
        refresh()
        #expect(monitorDesks[2] === desks["0"])
        #expect(monitorDesks[3] === desks["9"])
    }

    @Test func aTenthExtraMonitorHasNoDesk() {
        fake.screens = [mainMonitor] + (2...11).map { monitor($0, x: CGFloat($0) * 1000) }
        refresh()
        #expect(monitorDesks.count == 9)
        #expect(!onMonitor(desks["1"]!))
        show("2")   // taken by a monitor: desk 1 stays on the main one
        #expect(current == "1")
    }

    @Test func theKeyOfAMonitorsDeskGivesItTheFocus() {
        fake.screens = [mainMonitor, rightMonitor]
        let x = fake.opens(1, on: rightMonitor)
        let a = fake.opens(2, on: mainMonitor)
        show("0")
        #expect(fake.focused == x)
        #expect(current == "1")
        #expect(fake.frames == [a: whole, x: whole.applying(onRight)])
        // An empty monitor: nothing to focus, and the main monitor stays as it is.
        fake.closes(x)
        fake.focus(a)
        show("0")
        #expect(fake.focused == a)
        #expect(fake.frames[a] == whole)
    }

    @Test func sendingAWindowToAMonitorsDeskMovesItToThatMonitor() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1), b = fake.opens(2)
        send(to: "0")
        #expect(current == "1")
        #expect(desks["0"]!.tiled == [b])
        #expect(fake.frames == [a: whole, b: whole.applying(onRight)])
        #expect(fake.focused == b)
        // And back, to a desk of the main monitor: that desk shows.
        send(to: "3")
        #expect(current == "3")
        #expect(fake.frames[b] == whole)
        #expect(visibleArea(of: a, on: fake) == 1)
    }

    @Test func aFloatingWindowSentToAMonitorsDeskMovesThereToo() {
        fake.screens = [mainMonitor, rightMonitor]
        let dialog = fake.opens(1, dialog: true)
        send(to: "0")
        #expect(desks["0"]!.floating == [dialog])
        #expect(fake.frames[dialog] == rect(1300, 270, 400, 300))
        send(to: "2")
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))
    }

    @Test func aNewMonitorTakesItsDeskWithTheWindowsOnIt() {
        let a = fake.opens(1)
        send(to: "0")
        let dialog = fake.opens(2, dialog: true)
        show("1")
        fake.screens = [mainMonitor, rightMonitor]
        refresh()
        #expect(current == "1")
        #expect(fake.frames[a] == whole.applying(onRight))
        #expect(fake.frames[dialog] == rect(1300, 270, 400, 300))
    }

    /// The main monitor never shows the same desk as another monitor.
    @Test func aNewMonitorThatTakesTheDeskOnScreenLeavesThePreviousOneOnTheMainMonitor() {
        let a = fake.opens(1)
        show("3")
        let b = fake.opens(2)
        show("0")
        let x = fake.opens(3)
        let dialog = fake.opens(4, dialog: true)
        fake.screens = [mainMonitor, rightMonitor]
        refresh()
        #expect(current == "3")
        #expect(fake.frames[b] == whole)
        #expect(fake.frames[x] == whole.applying(onRight))
        #expect(fake.frames[dialog] == rect(1300, 270, 400, 300))
        #expect(visibleArea(of: a, on: fake) == 1)
    }

    @Test func anUnpluggedMonitorLeavesItsDeskAKeyAway() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1)
        let x = fake.opens(2, on: rightMonitor)
        let dialog = fake.opens(3, on: rightMonitor, dialog: true)
        fake.screens = [mainMonitor]
        refresh()
        #expect(monitorDesks.isEmpty)
        #expect(current == "1")
        #expect(fake.focused == a)   // the focus does not stay on a window out of sight
        #expect(desks["1"]!.windows == [a])
        #expect(fake.frames[a] == whole)
        #expect(visibleArea(of: x, on: fake) == 1)
        #expect(visibleArea(of: dialog, on: fake) == 1)
        show("0")
        #expect(fake.frames[x] == whole)
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))
        #expect(visibleArea(of: a, on: fake) == 1)
    }

    /// A monitor also goes away for a moment each time the Mac wakes up.
    @Test func aMonitorThatComesBackGetsItsWindowsAndLayoutBack() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1)
        let x = fake.opens(2, on: rightMonitor), y = fake.opens(3, on: rightMonitor)
        let dialog = fake.opens(4, on: rightMonitor, dialog: true)
        fake.focus(y)
        resize(by: 0.2)
        let before = fake.frames

        fake.screens = [mainMonitor]
        refresh()
        #expect(desks["1"]!.windows == [a])

        fake.screens = [mainMonitor, rightMonitor]
        refresh()
        #expect(monitorDesks[2]!.tiled == [x, y])
        #expect(monitorDesks[2]!.floating == [dialog])
        #expect(fake.frames == before)
    }

    /// The same when its desk was on the main monitor meanwhile.
    @Test func aMonitorThatComesBackTakesItsDeskFromTheMainMonitor() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1)
        let x = fake.opens(2, on: rightMonitor)
        fake.screens = [mainMonitor]
        refresh()
        show("0")
        let y = fake.opens(3)   // opened meanwhile, on desk 0: it goes along
        fake.screens = [mainMonitor, rightMonitor]
        refresh()
        #expect(current == "1")
        #expect(fake.frames[a] == whole)
        #expect(monitorDesks[2]!.tiled == [x, y])
    }

    @Test func aWindowClosedWhileItsMonitorWasAwayIsForgotten() {
        fake.screens = [mainMonitor, rightMonitor]
        let x = fake.opens(1, on: rightMonitor), y = fake.opens(2, on: rightMonitor)
        fake.screens = [mainMonitor]
        refresh()
        fake.closes(x)
        let b = fake.opens(3)   // opened meanwhile: it stays on the main monitor
        fake.screens = [mainMonitor, rightMonitor]
        refresh()
        #expect(monitorDesks[2]!.tiled == [y])
        #expect(fake.frames[y] == whole.applying(onRight))
        #expect(fake.frames[b] == whole)
    }

    @Test func windowsOnAnUnpluggedMonitorCanBeSentToADesk() {
        fake.screens = [mainMonitor, rightMonitor]
        let x = fake.opens(1, on: rightMonitor)
        fake.screens = [mainMonitor]
        refresh()
        show("0")
        send(to: "3")
        #expect(desks["3"]!.tiled == [x])
        #expect(fake.frames[x] == whole)
    }

    /// With the lid closed and the monitor asleep, macOS reports no monitor at all for a moment.
    @Test func noMonitorAtAllChangesNothing() {
        let a = fake.opens(1), b = fake.opens(2)
        fake.screens = []
        refresh()
        show("2")
        show("1")
        swap(.left)
        dropped(a, at: .zero)
        fake.screens = [mainMonitor]
        refresh()
        #expect(desks["1"]!.windows.count == 2)
        #expect(visibleArea(of: a, on: fake) > 1 && visibleArea(of: b, on: fake) > 1)
    }

    // Hidden windows stay hidden, whatever the monitors.

    @Test(arguments: [
        [mainMonitor],
        [mainMonitor, rightMonitor],
        [mainMonitor, monitor(2, x: -1000)],
        [mainMonitor, rightMonitor, monitor(3, x: -1000)],
        [mainMonitor, monitor(2, y: 820)],
        [mainMonitor, monitor(2, y: -820)],
        [mainMonitor, monitor(2, x: 1000, y: 400)],
        [mainMonitor, monitor(2, x: 1000, y: -400)],
        [mainMonitor, monitor(2, x: -1000, y: 400), monitor(3, y: 820)],
    ])
    func hiddenWindowsShowOnePointAtMost(screens: [Screen]) {
        fake.screens = screens
        let a = fake.opens(1)
        let dialog = fake.opens(2, dialog: true)
        show("2")
        for window in [a, dialog] {
            #expect(visibleArea(of: window, on: fake) == 1, "one point must stay on screen, or macOS moves the window back")
        }
        show("1")
        #expect(fake.frames[a] == whole)
    }

    /// Before, windows parked past the right edge showed up on a monitor plugged in on the right.
    @Test func hiddenWindowsStayHiddenWhenMonitorsChange() {
        let a = fake.opens(1)
        show("2")
        #expect(fake.frames[a]!.minX == 999)
        for screens in [[mainMonitor, rightMonitor], [mainMonitor, monitor(2, y: 820)], [mainMonitor]] {
            fake.screens = screens
            refresh()
            #expect(visibleArea(of: a, on: fake) == 1)
        }
        show("1")
        #expect(fake.frames[a] == whole)
    }

    /// The main monitor changes (a laptop leaves its big monitor). A dialog hidden on another desk
    /// was last seen far to the right, where there is nothing now.
    @Test func aFloatingWindowLastSeenOnAMonitorThatIsGoneComesBackInSight() {
        let dialog = fake.opens(1, dialog: true)
        fake.frames[dialog] = rect(1500, 300, 400, 300)   // dragged half onto... nothing yet
        fake.plugs([mainMonitor, rightMonitor])
        refresh()
        show("2")
        fake.plugs([mainMonitor])
        refresh()
        show("1")
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))
    }

    // Moving between monitors with keys.

    @Test func focusCrossesMonitors() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1), b = fake.opens(2)
        let x = fake.opens(3, on: rightMonitor)
        fake.focus(a)
        moveFocus(.right)
        #expect(fake.focused == b)
        moveFocus(.right)
        #expect(fake.focused == x)
        moveFocus(.left)
        #expect(fake.focused == b)
    }

    @Test func swappingCrossesMonitors() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1), b = fake.opens(2)
        let x = fake.opens(3, on: rightMonitor)
        fake.focus(b)
        swap(.right)
        #expect(desks["1"]!.tiled == [a, x])
        #expect(monitorDesks[2]!.tiled == [b])
        #expect(fake.frames == [a: leftHalf, x: rightHalf, b: whole.applying(onRight)])
        #expect(fake.focused == b)
    }

    /// Before, there was no way to put a window on a monitor with no windows.
    @Test func swappingTowardAnEmptyMonitorMovesTheWindowThere() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1), b = fake.opens(2)
        fake.focus(a)
        swap(.right)   // a neighbor that way: trade places first
        #expect(fake.frames == [b: leftHalf, a: rightHalf])
        swap(.right)   // then on to the monitor
        #expect(monitorDesks[2]!.tiled == [a])
        #expect(fake.frames == [b: whole, a: whole.applying(onRight)])
        swap(.down)    // no window and no monitor that way
        #expect(fake.frames == [b: whole, a: whole.applying(onRight)])
        swap(.left)    // a neighbor again, on the other monitor: trade places
        #expect(fake.frames == [a: whole, b: whole.applying(onRight)])
    }

    @Test func aFloatingWindowMovesToTheOtherMonitorWithTheSameKeys() {
        fake.screens = [mainMonitor, rightMonitor]
        let dialog = fake.opens(1, dialog: true)
        swap(.right)
        #expect(monitorDesks[2]!.floating == [dialog])
        #expect(fake.frames[dialog] == rect(1300, 270, 400, 300))
        show("2")   // it no longer belongs to desk 1
        #expect(fake.frames[dialog] == rect(1300, 270, 400, 300))
    }

    /// A dialog can belong to the main monitor's desk and sit on another monitor already.
    @Test func aFloatingWindowNeverFliesOffEveryMonitor() {
        fake.screens = [mainMonitor, rightMonitor]
        let dialog = fake.opens(1, dialog: true)
        fake.frames[dialog] = rect(1300, 270, 400, 300)
        swap(.right)
        #expect(monitorDesks[2]!.floating == [dialog])
        #expect(fake.frames[dialog] == rect(1300, 270, 400, 300))   // the middle of that monitor
    }

    /// Before, the desk kept showing a window that had left for the other monitor.
    @Test func swappingAFullscreenWindowAwayEndsFullscreen() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1)
        let x = fake.opens(2, on: rightMonitor)
        fake.focus(a)
        refresh()
        toggleFullscreen()
        swap(.right)
        #expect(desks["1"]!.fullscreen == nil)
        #expect(desks["1"]!.lastFocused == x)
        #expect(fake.frames == [x: whole, a: whole.applying(onRight)])
    }

    /// Apps open a window where they last had one, maybe on another monitor.
    /// Before, the window joined the desk of that monitor, not the one you were on.
    @Test func aNewWindowJoinsTheDeskYouAreOnWhereverItAppears() {
        fake.screens = [mainMonitor, rightMonitor]
        let x = fake.opens(1, on: rightMonitor)
        let a = fake.opens(2, on: mainMonitor)
        let b = fake.opens(3, at: rightMonitor)
        #expect(desks["1"]!.tiled == [a, b])
        #expect(monitorDesks[2]!.tiled == [x])
        #expect(fake.frames == [a: leftHalf, b: rightHalf, x: whole.applying(onRight)])
        // The focus goes to the other monitor: you are there now.
        fake.focused = x
        refresh()
        let y = fake.opens(4, at: mainMonitor)
        #expect(monitorDesks[2]!.tiled == [x, y])
        // Its key takes you there too, even with no window on it.
        fake.closes(x)
        fake.closes(y)
        fake.focused = a
        refresh()
        show("0")
        refresh()
        let z = fake.opens(5, at: mainMonitor)
        #expect(monitorDesks[2]!.tiled == [z])
    }

    /// A dialog stays where its app put it, so it belongs to the monitor it is on.
    @Test func aNewDialogJoinsTheMonitorItAppearsOn() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1, on: mainMonitor)
        let d = fake.opens(2, at: rightMonitor, dialog: true)
        #expect(desks["1"]!.windows == [a])
        #expect(monitorDesks[2]!.floating == [d])
    }
}
