import Foundation
import Testing
@testable import Control

// Going back to a layout from the history.

extension ControlTests {
    /// Windows get packed on one desk somehow. The layout kept before puts each back on its desk,
    /// in its place, with the splits as they were.
    @Test func goingBackPutsEveryWindowWhereItWas() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        fake.focus(c)
        send(to: "2")
        show("1")
        let before = fake.frames
        saveLayout("before the screen locked")
        show("2")
        send(to: "1")                   // c is back on desk 1, beside b
        #expect(desks["1"]!.tiled == [a, b, c])

        restore(history.last!)
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
        saveLayout("test")
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
        saveLayout("test")
        fake.focus(a)
        send(to: "2")
        fake.closes(b)
        show("3")
        let d = fake.opens(4)
        restore(history.last!)
        #expect(desks["1"]!.tiled == [a, c])
        #expect(desks["2"]!.tiled.isEmpty)
        #expect(desks["3"]!.tiled == [d])
        #expect(current == "1")
        #expect(fake.frames[a] == leftHalf)
        #expect(fake.frames[c] == rightHalf)
    }

    @Test func aFloatingWindowGoesBackToItsFrame() {
        fake.opens(1)
        let dialog = fake.opens(2, dialog: true)
        let frame = fake.frames[dialog]!
        saveLayout("test")
        fake.frames[dialog] = rect(10, 30, 200, 100)
        send(to: "2")
        restore(history.last!)
        #expect(desks["1"]!.floating == [dialog])
        #expect(fake.frames[dialog] == frame)
    }

    /// Going back keeps the layout just before, so it can be undone.
    @Test func goingBackCanBeUndone() {
        let a = fake.opens(1), b = fake.opens(2)
        saveLayout("test")
        send(to: "2")
        let before = fake.frames
        restore(history.last!)
        #expect(history.first!.why.hasPrefix("before going back"))
        restore(history.first!)
        #expect(desks["1"]!.tiled == [a])
        #expect(desks["2"]!.tiled == [b])
        #expect(current == "2")
        #expect(fake.frames == before)
    }

    @Test func theSameLayoutIsKeptOnceAndOnlyTheLastTen() {
        fake.opens(1)
        saveLayout("one")
        saveLayout("two")
        #expect(history.map(\.why) == ["one"])
        for key in deskKeys.prefix(12) {
            send(to: key)
            saveLayout(key)
        }
        #expect(history.count == historyLimit)
        #expect(history.first!.why == deskKeys[11])
    }

    @Test func nothingIsKeptWithoutWindows() {
        saveLayout("empty")
        #expect(history.isEmpty)
    }

    /// Several windows going missing at once is rarely the user closing them: the layout they
    /// leave is kept. One window closing is.
    @Test func severalWindowsGoingMissingKeepTheLayout() {
        let a = fake.opens(1), b = fake.opens(2), c = fake.opens(3)
        fake.closes(c)
        #expect(history.isEmpty)
        fake.unreported = [a, b]
        refresh()
        #expect(history.first?.why == "before 2 windows went missing")
        #expect(history.first?.shape.windowCount == 2)
    }
}
