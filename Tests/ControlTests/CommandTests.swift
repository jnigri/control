import Foundation
import Testing
@testable import Control

// Commands, as the command line sends them: the words, what they do, and the trip through the socket.

@Suite struct CommandWordTests {
    @Test func wordsMakeCommands() throws {
        #expect(try Command(["show", "3"]) == .show("3"))
        #expect(try Command(["show", "m"]) == .show("M"))
        #expect(try Command(["show", "previous"]) == .showPrevious)
        #expect(try Command(["send", "2"]) == .send("2"))
        #expect(try Command(["focus", "left"]) == .focus(.left))
        #expect(try Command(["focus", "window", "42"]) == .focusWindow(.number(42)))
        #expect(try Command(["focus", "app", "Google Chrome"]) == .focusWindow(.app("Google Chrome")))
        #expect(try Command(["focus", "title", "notes"]) == .focusWindow(.title("notes")))
        #expect(try Command(["swap", "down"]) == .swap(.down))
        #expect(try Command(["grow"]) == .grow)
        #expect(try Command(["shrink"]) == .shrink)
        #expect(try Command(["fullscreen"]) == .fullscreen)
        #expect(try Command(["float"]) == .float)
        #expect(try Command(["ls"]) == .list)
        #expect(try Command(["windows"]) == .windows)
    }

    @Test func otherWordsAreNotCommands() {
        for words in [[], ["show"], ["show", "F"], ["show", "10"], ["send", "previous"], ["focus", "sideways"],
                      ["focus", "window", "x"], ["focus", "thing", "x"], ["grow", "a", "lot"], ["ls", "-l"], ["jump"]] {
            #expect(throws: CommandError.self, "\(words)") { try Command(words) }
        }
    }
}

extension ControlTests {
    @Test func focusingAWindowShowsItsDesk() throws {
        let a = fake.opens(1)
        show("2")
        let b = fake.opens(2)
        show("1")
        try Command(["focus", "window", "2"]).run()
        #expect(current == "2")
        #expect(previous == "1")
        #expect(fake.focused == b)
        #expect(fake.frames[b] == whole)
        #expect(visibleArea(of: a, on: fake) <= 1)
    }

    @Test func focusingAWindowOnScreenStaysOnTheDesk() throws {
        let a = fake.opens(1), b = fake.opens(2)
        try Command(["focus", "window", "1"]).run()
        #expect(current == "1")
        #expect(fake.focused == a)
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
    }

    @Test func focusingAWindowBehindAFullscreenOneUncoversIt() throws {
        let a = fake.opens(1), b = fake.opens(2)
        toggleFullscreen()
        #expect(fake.frames[b] == mainMonitor.area)
        try Command(["focus", "window", "1"]).run()
        #expect(fake.frames == [a: leftHalf, b: rightHalf])
        #expect(fake.focused == a)
    }

    @Test func focusingAnAppByNameOrBundle() throws {
        fake.opens(1, app: "com.apple.Safari")
        fake.names[window(1)] = "Safari"
        show("3")
        let b = fake.opens(2, app: "com.mitchellh.ghostty")
        fake.names[b] = "Ghostty"
        show("1")
        try Command(["focus", "app", "ghostty"]).run()
        #expect(current == "3")
        #expect(fake.focused == b)
        try Command(["focus", "app", "com.apple.safari"]).run()
        #expect(current == "1")
        #expect(fake.focused == window(1))
    }

    @Test func anAppWithWindowsEverywhereGetsTheOneOnScreen() throws {
        fake.opens(1, app: "term")
        show("2")
        let b = fake.opens(2, app: "term")
        fake.opens(3, app: "other")
        try Command(["focus", "app", "term"]).run()
        #expect(current == "2")
        #expect(fake.focused == b)
    }

    @Test func focusingByTitle() throws {
        let a = fake.opens(1)
        fake.titles[a] = "~/code/my-app — zsh"
        show("2")
        fake.opens(2)
        try Command(["focus", "title", "CODE/my-app"]).run()
        #expect(current == "1")
        #expect(fake.focused == a)
    }

    @Test func noMatchIsAnError() {
        fake.opens(1)
        #expect(throws: CommandError("no window matches")) { try Command(["focus", "app", "nothing"]).run() }
        #expect(throws: CommandError("no window matches")) { try Command(["focus", "window", "99"]).run() }
    }

    @Test func nothingMovesWhileTheScreenIsLocked() {
        let a = fake.opens(1)
        show("2")
        locked = true
        #expect(throws: CommandError("the screen is locked")) { try Command(["focus", "window", "1"]).run() }
        #expect(current == "2")
        #expect(visibleArea(of: a, on: fake) <= 1)
    }

    @Test func theKeysCommandsWorkFromWordsToo() throws {
        let a = fake.opens(1), b = fake.opens(2)
        try Command(["focus", "left"]).run()
        #expect(fake.focused == a)
        try Command(["swap", "right"]).run()
        #expect(fake.frames == [a: rightHalf, b: leftHalf])
        try Command(["send", "4"]).run()
        #expect(current == "4")
        #expect(desks["4"]!.windows == [a])
        try Command(["show", "previous"]).run()
        #expect(current == "1")
        #expect(fake.frames[b] == whole)
    }

    @Test func windowsAndDesksAreListed() throws {
        let a = fake.opens(1, app: "com.apple.Terminal")
        fake.names[a] = "Terminal"
        fake.titles[a] = "a\ttab"
        show("3")
        let b = fake.opens(2)
        fake.names[b] = "Notes"
        fake.plugs([mainMonitor, rightMonitor])
        refresh()
        let c = fake.opens(15, on: rightMonitor)
        fake.names[c] = "Mail"
        fake.titles[c] = "Inbox"
        #expect(try Command(["windows"]).run() == """
            1\t1\thidden\tTerminal\ta tab
            2\t3\tshown\tNotes\t
            15\t0\tshown\tMail\tInbox
            """)
        #expect(try Command(["ls"]).run() == """
            1
               1   Terminal  a tab
            3  shown
               2   Notes
            0  shown
               15  Mail      Inbox
            """)
    }

    @Test func anEmptyDeskOnScreenIsListedToo() throws {
        #expect(try Command(["ls"]).run() == "1  shown")
        #expect(try Command(["windows"]).run() == "")
    }
}

@Suite struct SocketTests {
    let path = NSTemporaryDirectory() + "control-test-\(UUID().uuidString.prefix(8)).sock"

    @Test func wordsGoThroughTheSocketAndBack() throws {
        let listener = Listener(at: path, queue: DispatchQueue(label: "test")) { words in
            if words == ["fail"] { throw CommandError("no luck") }
            if words == ["long"] { return String(repeating: "x", count: 200_000) }
            return words.joined(separator: "+")
        }
        #expect(listener != nil)
        #expect(try ask(["focus", "app", "Google Chrome"], at: path) == "focus+app+Google Chrome")
        #expect(throws: CommandError("no luck")) { try ask(["fail"], at: path) }
        // A long answer does not fit the socket's buffer at once.
        #expect(try ask(["long"], at: path).count == 200_000)
        withExtendedLifetime(listener) {}
    }

    @Test func noAppNoAnswer() {
        #expect(throws: CommandError("Control is not running")) { try ask(["desks"], at: path) }
    }

    @Test func theSocketGoesAwayWithTheListener() {
        var listener = Listener(at: path, queue: DispatchQueue(label: "test")) { _ in "" }
        #expect(FileManager.default.fileExists(atPath: path))
        listener = nil
        #expect(!FileManager.default.fileExists(atPath: path))
        _ = listener
    }
}
