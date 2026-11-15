import Foundation
import Testing
@testable import Control

// Windows going back to their desks when Control starts.

extension ControlTests {
    @Test func afterARestartOfControlEachWindowGoesBackToItsDesk() {
        let a = fake.opens(1, app: "editor"), b = fake.opens(2, app: "editor"), c = fake.opens(3, app: "browser")
        send(to: "W")   // c
        show("1")
        fake.focus(b)
        send(to: "2")

        restart(on: fake)
        #expect(desks["1"]!.tiled == [a])
        #expect(desks["2"]!.tiled == [b])
        #expect(desks["W"]!.tiled == [c])
        #expect(fake.frames[a] == whole)
    }

    /// After a reboot every window is new. Each app goes to the desk of its oldest window.
    @Test func afterARebootEachAppGoesToTheDeskOfItsOldestWindow() {
        fake.opens(1, app: "editor")
        send(to: "E")
        show("1")
        fake.opens(2, app: "browser")
        fake.opens(3, app: "editor")   // a second editor window, on desk 1

        let rebooted = FakeMac()
        rebooted.store = fake.store
        rebooted.bootTime = 2
        restart(on: rebooted)
        let editor = rebooted.opens(11, app: "editor"), browser = rebooted.opens(12, app: "browser")
        let other = rebooted.opens(13, app: "other")
        #expect(desks["E"]!.tiled == [editor])
        #expect(desks["1"]!.tiled == [browser, other])
    }

    /// Window numbers start over at each boot: a new window must not take the desk of an old one
    /// that happened to have the same number.
    @Test func afterARebootOldWindowNumbersMeanNothing() {
        fake.opens(1, app: "editor")
        send(to: "E")
        let rebooted = FakeMac()
        rebooted.store = fake.store
        rebooted.bootTime = 2
        restart(on: rebooted)
        let unrelated = rebooted.opens(1, app: "other")
        #expect(desks["1"]!.tiled == [unrelated])
    }

    @Test func windowsOpenedLongAfterTheStartStayOnTheCurrentDesk() {
        let editor = fake.opens(1, app: "editor")
        send(to: "E")
        fake.closes(editor)
        show("1")
        restart(on: fake)
        fake.now += 29
        let early = fake.opens(2, app: "editor")
        fake.now += 2
        let late = fake.opens(3, app: "editor")
        #expect(desks["E"]!.tiled.contains(early))
        #expect(desks["1"]!.tiled == [late])
    }

    /// Right after a restart of Control, a new window of an app that is already open is one you
    /// just made: it opens on the desk you are on, not on the desk of the app's other windows.
    @Test func aNewWindowOfAnAppAlreadyOpenStaysOnTheCurrentDesk() {
        let old = fake.opens(1, app: "browser")
        send(to: "B")
        show("1")
        restart(on: fake)
        fake.now += 5
        let new = fake.opens(2, app: "browser")
        #expect(desks["B"]!.tiled == [old])
        #expect(desks["1"]!.tiled == [new])
    }

    @Test func anAppThatIsNotRunningKeepsItsDeskForNextTime() {
        let editor = fake.opens(1, app: "editor")
        send(to: "E")
        fake.closes(editor)
        show("1")
        fake.opens(2, app: "browser")
        restart(on: fake)
        let again = fake.opens(3, app: "editor")
        #expect(desks["E"]!.tiled == [again])
    }

    @Test func windowsGoBackToTheirMonitorAfterARestart() {
        fake.screens = [mainMonitor, rightMonitor]
        let a = fake.opens(1), x = fake.opens(2, on: rightMonitor)
        fake.focus(a)
        swap(.right)   // now a is on the right monitor and x on the main one
        // A crash: the windows stay where they were, and Control starts again.
        restart(on: fake)
        #expect(desks["1"]!.tiled == [x])
        #expect(monitorDesks[2]!.tiled == [a])
    }

    /// The saved monitor is gone: the window just stays where it shows up.
    @Test func aSavedMonitorThatIsGoneFallsBackToTheCurrentDesk() {
        fake.screens = [mainMonitor, rightMonitor]
        let x = fake.opens(1, on: rightMonitor)
        fake.screens = [mainMonitor]
        fake.frames[x] = rect(100, 100, 400, 300)
        restart(on: fake)
        #expect(desks["1"]!.tiled == [x])
    }

    /// Control crashed while a dialog was parked out of sight. Its real place is lost,
    /// but it must come back somewhere you can see it.
    @Test func afterACrashAHiddenFloatingWindowComesBackInSight() {
        let dialog = fake.opens(1, dialog: true)
        show("2")
        restart(on: fake)   // Control starts on desk 1
        #expect(desks["1"]!.floating == [dialog])
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))   // the middle of the monitor
    }

    @Test func afterACrashAFloatingWindowOnAHiddenDeskComesBackInSightToo() {
        fake.opens(1, dialog: true)
        send(to: "2")
        let dialog = fake.focused!
        show("1")
        restart(on: fake)
        #expect(visibleArea(of: dialog, on: fake) == 1)
        show("2")
        #expect(fake.frames[dialog] == rect(300, 270, 400, 300))
    }

    @Test func nothingIsWrittenWhenNothingChanged() {
        fake.opens(1)
        restart(on: fake)
        let writes = fake.writes
        for _ in 0..<5 { refresh() }
        #expect(fake.writes == writes)
    }
}
