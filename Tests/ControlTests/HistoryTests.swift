import Foundation
import Testing
@testable import Control

// The history of layouts, and going back to one.

extension ControlTests {
    /// Time passes: the layout on screen is one you had on purpose.
    func settle() { fake.now += settleTime }

    /// Each change keeps the layout it replaces, if it stayed long enough.
    @Test func eachChangeKeepsTheLayoutBefore() {
        fake.opens(1)
        settle()
        fake.opens(2)
        settle()
        send(to: "2")
        #expect(history.count == 2)
        #expect(history[0].shape.desks["1"]?.tree == .split(.window(1), .window(2), 0.5))
        #expect(history[1].shape.desks["1"]?.tree == .window(1))
    }

    /// The layouts on the way to another one, a moment apart, are not kept.
    @Test func layoutsReplacedRightAwayAreNotKept() {
        fake.opens(1)
        settle()
        fake.opens(2)
        fake.opens(3)
        fake.opens(4)
        settle()
        send(to: "2")
        #expect(history.map(\.shape.windowCount) == [4, 1])
    }

    /// Showing another desk changes nothing worth keeping.
    @Test func showingADeskKeepsNothing() {
        fake.opens(1)
        settle()
        show("2")
        settle()
        show("1")
        #expect(history.isEmpty)
    }

    /// Windows get packed on one desk somehow. The layout before puts each back on its desk, in its
    /// place. The desk on screen stays.
    @Test func goingBackPutsEveryWindowWhereItWas() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        fake.focus(c)
        send(to: "2")
        show("1")
        let before = fake.frames
        settle()
        show("2")
        send(to: "1")                   // c is back on desk 1, beside b
        #expect(desks["1"]!.tiled == [a, b, c])

        restore(history[0])
        #expect(desks["1"]!.tiled == [a, b])
        #expect(desks["2"]!.tiled == [c])
        #expect(current == "1")
        #expect(fake.frames[a] == before[a])
        #expect(fake.frames[b] == before[b])
        show("2")
        #expect(fake.frames[c] == whole)
    }

    @Test func goingBackKeepsTheSplitsAndTheWindowThatCoversItsDesk() {
        let a = fake.opens(1), b = fake.opens(2)
        resize(by: 0.2)
        toggleFullscreen()
        let before = fake.frames
        settle()
        toggleFullscreen()
        resize(by: -0.3)
        restore(history.last!)
        #expect(desks["1"]!.fullscreen == b)
        #expect(desks["1"]!.tiled == [a, b])
        #expect(fake.frames == before)
    }

    /// A window closed since is left out. One opened since stays on its desk, after the others.
    @Test func goingBackLeavesOutClosedWindowsAndKeepsNewOnes() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        settle()
        fake.focus(a)
        send(to: "2")
        fake.closes(b)
        show("3")
        let d = fake.opens(4)
        restore(history.last!)
        #expect(desks["1"]!.tiled == [a, c])
        #expect(desks["2"]!.tiled.isEmpty)
        #expect(desks["3"]!.tiled == [d])
        #expect(current == "3")
        #expect(fake.frames[d] == whole)
        show("1")
        #expect(fake.frames[a] == leftHalf)
        #expect(fake.frames[c] == rightHalf)
    }

    @Test func aFloatingWindowGoesBackToItsFrame() {
        fake.opens(1)
        let dialog = fake.opens(2, dialog: true)
        let frame = fake.frames[dialog]!
        settle()
        fake.frames[dialog] = rect(10, 30, 200, 100)
        send(to: "2")
        restore(history[0])
        #expect(desks["1"]!.floating == [dialog])
        show("1")
        #expect(fake.frames[dialog] == frame)
    }

    /// Going back keeps the layout just before, however short, so it can be undone.
    @Test func goingBackCanBeUndone() {
        let a = fake.opens(1), b = fake.opens(2)
        settle()
        send(to: "2")
        let before = fake.frames
        restore(history[0])
        #expect(history[0].why.hasPrefix("before going back"))
        restore(history[0])
        #expect(desks["1"]!.tiled == [a])
        #expect(desks["2"]!.tiled == [b])
        #expect(current == "2")
        #expect(fake.frames == before)
    }

    @Test func onlyTheLastTenAreKept() {
        fake.opens(1)
        for key in deskKeys.prefix(12) {
            settle()
            send(to: key)
        }
        #expect(history.count == historyLimit)
        #expect(history[0].shape.desks.keys.first == deskKeys[10])
    }

    /// The history lasts across restarts of Control, but not across a reboot.
    @Test func theHistoryLastsUntilAReboot() {
        fake.opens(1)
        settle()
        fake.opens(2)
        restart(on: fake)
        #expect(history.count == 1)
        let rebooted = FakeMac()
        rebooted.store = fake.store
        rebooted.bootTime = 2
        restart(on: rebooted)
        #expect(history.isEmpty)
    }
}
