import Foundation
import CoreGraphics

// Everything you can ask Control to do. The keys and the command line both send a `Command`:
// the keys from `main.swift`, the command line in words, like `control show 3`, through `Socket.swift`.

enum Command: Equatable {
    case show(String)            // a desk key
    case showPrevious
    case send(String)            // the focused window, to a desk key
    case focus(Direction)
    case focusWindow(Target)     // wherever it is: its desk comes on screen first
    case swap(Direction)
    case grow, shrink
    case fullscreen, float
    case list                    // desks and their windows, for people
    case windows                 // every window, for scripts
    case export(String?)         // the debug log, zipped into a folder (the Desktop when nil)
}

/// A way to name a window from outside.
enum Target: Equatable {
    case number(CGWindowID)      // as `control ls` and `control windows` list it
    case app(String)             // app name or bundle identifier, any case
    case title(String)           // part of the title, any case
}

struct CommandError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

let usage = """
    usage: control <command>

      show <desk>             show a desk (0-9, or a letter but F, H, J, K, L)
      show previous           show the desk shown before
      send <desk>             send the focused window to a desk, and follow it
      focus left|down|up|right
      focus window <number>   focus a window, showing its desk first (numbers: see `control ls`)
      focus app <name>        the same, for a window of an app, by name or bundle identifier
      focus title <text>      the same, for the first window whose title contains the text
      swap left|down|up|right swap with the neighbor, or move to the monitor that way
      grow, shrink            move the split next to the focused window
      fullscreen              the focused window covers its desk, or stops covering it
      float                   float the focused window, or tile it again
      ls                      list the desks in use and their windows: number, app, title
      windows                 the same for scripts, one line per window, tab-separated:
                              number, desk, shown or hidden, app, title
      export [folder]         zip the debug log to send with a bug report, on the Desktop or
                              in a folder, and print where it is
    """

extension Command {
    /// Read a command from words, like `["focus", "app", "Safari"]`.
    init(_ words: [String]) throws {
        func desk(_ word: String) throws -> String {
            guard deskKeys.contains(word.uppercased()) else { throw CommandError("no desk \"\(word)\"") }
            return word.uppercased()
        }
        func direction(_ word: String) throws -> Direction {
            guard let direction = Direction(rawValue: word) else { throw CommandError("no direction \"\(word)\"") }
            return direction
        }
        guard let verb = words.first else { throw CommandError("no command") }
        let rest = Array(words.dropFirst())
        let unknown = CommandError("unknown command \"\(words.joined(separator: " "))\"")
        let alone: [String: Command] = ["grow": .grow, "shrink": .shrink, "fullscreen": .fullscreen, "float": .float,
                                        "ls": .list, "windows": .windows]
        switch (verb, rest.count) {
        case ("show", 1): self = rest[0] == "previous" ? .showPrevious : .show(try desk(rest[0]))
        case ("send", 1): self = .send(try desk(rest[0]))
        case ("focus", 1): self = .focus(try direction(rest[0]))
        case ("focus", 2):
            switch rest[0] {
            case "window":
                guard let number = CGWindowID(rest[1]) else { throw CommandError("no window number \"\(rest[1])\"") }
                self = .focusWindow(.number(number))
            case "app": self = .focusWindow(.app(rest[1]))
            case "title": self = .focusWindow(.title(rest[1]))
            default: throw unknown
            }
        case ("swap", 1): self = .swap(try direction(rest[0]))
        case ("export", 0): self = .export(nil)
        case ("export", 1): self = .export(rest[0])
        case (_, 0):
            guard let command = alone[verb] else { throw unknown }
            self = command
        default: throw unknown
        }
    }

    /// Do it. Lists come back as text; the other commands give back nothing.
    /// (`Control.show` and the like: inside `Command`, a bare `show` is the case of that name.)
    /// A command that does not apply (no neighbor that way, say) does nothing, like its key.
    @discardableResult
    func run() throws -> String {
        // Nothing moves for an export: it works with the screen locked too.
        if case .export(let folder) = self {
            log("command", ["name": "export"])
            do { return try exportLog(into: folder.map { URL(fileURLWithPath: $0) }).path } catch {
                throw CommandError("cannot export: \(error.localizedDescription)")
            }
        }
        // Apps report no windows while the screen is locked: moving them now would lose the layout.
        if paused {
            if let logName { log("command", ["name": logName, "rejected": locked ? "locked" : "asleep"]) }
            throw CommandError("the screen is locked")
        }
        if let logName { log("command", ["name": logName]) }
        switch self {
        case .show(let key): Control.show(key)
        case .showPrevious: Control.show(previous)
        case .send(let key): Control.send(to: key)
        case .focus(let direction): moveFocus(direction)
        case .focusWindow(let target):
            guard let window = find(target) else { throw CommandError("no window matches") }
            reveal(window)
        case .swap(let direction): Control.swap(direction)
        case .grow: resize(by: resizeStep)
        case .shrink: resize(by: -resizeStep)
        case .fullscreen: toggleFullscreen()
        case .float: toggleFloating()
        case .list: return listing()
        case .windows: return windowList()
        case .export: break
        }
        return ""
    }

    /// The command, for the debug log: its name, with a desk key, a direction or a window number.
    /// Never the text someone typed to find a window. The lists change nothing: no line for them.
    var logName: String? {
        switch self {
        case .show(let key): "show \(key)"
        case .showPrevious: "show previous"
        case .send(let key): "send \(key)"
        case .focus(let direction): "focus \(direction.rawValue)"
        case .focusWindow(.number(let number)): "focus window \(number)"
        case .focusWindow(.app): "focus app"
        case .focusWindow(.title): "focus title"
        case .swap(let direction): "swap \(direction.rawValue)"
        case .grow: "grow"
        case .shrink: "shrink"
        case .fullscreen: "fullscreen"
        case .float: "float"
        case .export: "export"
        case .list, .windows: nil
        }
    }
}

/// Every desk in a steady order.
func orderedDesks() -> [Desk] { deskKeys.compactMap { desks[$0] } }

/// The window a target names. The focused window comes first, then the windows on screen,
/// so a match there needs no change of desk. On each desk, the window that last had focus comes first.
/// Last, windows Control leaves alone, like one in macOS's own full screen mode.
func find(_ target: Target) -> Window? {
    let shown = visibleDesks().map(\.desk)
    let hiddenDesks = orderedDesks().filter { desk in !shown.contains { $0 === desk } }
    var candidates = mac.focusedWindow().map { [$0] } ?? []
    for desk in shown + hiddenDesks {
        candidates += [desk.lastFocused].compactMap { $0 } + desk.windows.filter { $0 != desk.lastFocused }
    }
    candidates += mac.windows()
    return candidates.first { window in
        switch target {
        case .number(let number): mac.number(of: window) == number
        case .app(let name): [mac.appName(of: window), mac.app(of: window)].contains { $0?.lowercased() == name.lowercased() }
        case .title(let text): mac.title(of: window).localizedCaseInsensitiveContains(text)
        }
    }
}

/// For people: each desk on screen or with windows, then its windows in columns: number, app, title.
func listing() -> String {
    let shown = visibleDesks().map(\.desk)
    let listed = orderedDesks().filter { desk in shown.contains { $0 === desk } || !desk.windows.isEmpty }
    let rows = listed.map { desk in
        (desk, desk.windows.compactMap { window in
            mac.number(of: window).map { (String($0), oneLine(mac.appName(of: window) ?? ""), oneLine(mac.title(of: window))) }
        })
    }
    let numberWidth = rows.flatMap { $0.1.map(\.0.count) }.max() ?? 0
    let appWidth = rows.flatMap { $0.1.map(\.1.count) }.max() ?? 0
    func pad(_ text: String, _ width: Int) -> String { text + String(repeating: " ", count: width - text.count) }
    var lines: [String] = []
    for (desk, windows) in rows {
        lines.append(shown.contains { $0 === desk } ? "\(desk.name)  shown" : desk.name)
        for (number, app, title) in windows {
            var line = "   " + pad(number, numberWidth) + "  " + pad(app, appWidth) + "  " + title
            while line.last == " " { line.removeLast() }
            lines.append(line)
        }
    }
    return lines.joined(separator: "\n")
}

/// For scripts: one line per window, tab-separated: number, desk, shown or hidden, app, title.
func windowList() -> String {
    let shown = visibleDesks().map(\.desk)
    return orderedDesks().flatMap { desk in
        desk.windows.compactMap { window -> String? in
            guard let number = mac.number(of: window) else { return nil }
            return [String(number), desk.name, shown.contains { $0 === desk } ? "shown" : "hidden",
                    mac.appName(of: window) ?? "", mac.title(of: window)].map(oneLine).joined(separator: "\t")
        }
    }.joined(separator: "\n")
}

/// Tabs and line breaks in a name or title become spaces, so each window stays on one line.
func oneLine(_ text: String) -> String {
    text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
}
