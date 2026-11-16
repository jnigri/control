import Foundation
import CoreGraphics

// The debug log: what macOS told Control, what Control decided, and where every window is.
// Off unless the settings switch it on. One JSON object per line, in a file on this Mac only.
//
// Written: times, event names, monitors, window numbers, process numbers, bundle identifiers,
// window frames, desk keys, the names of Control's own commands.
// Never written: window titles, app display names, text typed into a command, file paths.
// `tag` and `snapshot` are the only places that turn a window into log data: the rule lives there.

/// Where the lines go. Nil when the log is off: then nothing is built and no app is asked anything.
var logSink: ((String) -> Void)?

/// What the log last said about things that are only worth a line when they change.
struct LogMemory {
    var screens: [[Double]] = []
    var skip = ""
    var catchingUp = false
    var silent: Set<pid_t> = []
    var covered: Set<CGDirectDisplayID> = []
    var kept: [Window: String] = [:]
    var layout = Layout()
    /// Something was written since the last full snapshot.
    var dirty = false
}

var logMemory = LogMemory()

/// Which window is on which desk, without the frames.
struct Layout: Equatable {
    var current = ""
    var previous = ""
    var active = ""
    var monitors: [CGDirectDisplayID: String] = [:]
    var desks: [String: [Window]] = [:]
    var floating: Set<Window> = []
    var covering: Set<Window> = []
    var hidden = 0
}

private let stamp: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = .current
    return formatter
}()

/// Write one line: the time, the event, then the details.
func log(_ event: String, _ details: @autoclosure () -> [String: Any] = [:]) {
    guard let logSink else { return }
    var line = "{\"t\":\"\(stamp.string(from: mac.now))\",\"e\":\"\(event)\""
    let more = details()
    if !more.isEmpty {
        if JSONSerialization.isValidJSONObject(more),
           let data = try? JSONSerialization.data(withJSONObject: more, options: [.sortedKeys, .withoutEscapingSlashes]),
           let text = String(data: data, encoding: .utf8) {
            line += "," + text.dropFirst().dropLast()
        } else {
            line += ",\"error\":\"details could not be written\""
        }
    }
    logMemory.dirty = true
    logSink(line + "}")
}

/// Write a line only when a value is not what the log last said.
func logChange<Value: Equatable>(_ event: String, _ last: WritableKeyPath<LogMemory, Value>,
                                 _ value: @autoclosure () -> Value, _ details: (Value) -> [String: Any]) {
    guard logSink != nil else { return }
    let new = value()
    guard new != logMemory[keyPath: last] else { return }
    logMemory[keyPath: last] = new
    log(event, details(new))
}

/// A window, for the log: its number, its app's bundle identifier and process number. Never its title.
func tag(_ window: Window, _ more: [String: Any] = [:]) -> [String: Any] {
    var line = more
    line["w"] = mac.number(of: window).map { Int($0) as Any } ?? NSNull()
    line["app"] = mac.app(of: window) ?? "?"
    line["pid"] = Int(pid(of: window))
    return line
}

/// A frame as [x, y, width, height], to a tenth of a point.
func box(_ rect: CGRect) -> [Double] {
    [rect.minX, rect.minY, rect.width, rect.height].map { value in
        value.isFinite ? (Double(value) * 10).rounded() / 10 : 0
    }
}

func spot(_ point: CGPoint) -> [Double] { Array(box(CGRect(origin: point, size: .zero)).prefix(2)) }

func screensLog() -> [[String: Any]] {
    mac.screens.map { ["id": Int($0.id), "frame": box($0.frame), "area": box($0.area)] }
}

/// The monitors, when they are not the ones last written.
func logMonitors() {
    logChange("monitors", \.screens, mac.screens.map { [Double($0.id)] + box($0.frame) + box($0.area) }) { _ in
        ["screens": screensLog()]
    }
}

/// Which window is on which desk, when that changed.
func logLayout() {
    guard logSink != nil else { return }
    var now = Layout(current: current, previous: previous, active: activeDesk?.name ?? "",
                     monitors: monitorDesks.mapValues(\.name), hidden: hidden.count)
    for desk in allDesks where !desk.windows.isEmpty {
        now.desks[desk.name] = desk.windows
        now.floating.formUnion(desk.floating)
        if let cover = desk.fullscreen { now.covering.insert(cover) }
    }
    logChange("layout", \.layout, now) { now in
        func numbers(_ windows: [Window]) -> [Int] { windows.map { Int(mac.number(of: $0) ?? 0) } }
        return ["current": now.current, "previous": now.previous, "active": now.active,
                "monitorDesks": Dictionary(uniqueKeysWithValues: now.monitors.map { (String($0), $1) }),
                "desks": now.desks.mapValues(numbers), "floating": numbers(Array(now.floating)).sorted(),
                "covering": numbers(Array(now.covering)).sorted(), "hidden": now.hidden]
    }
}

/// The whole picture: monitors, desks, and for every window the frame Control wants and the one
/// macOS reports. This asks every app for its frames, so it runs rarely.
func snapshot(_ why: String) -> [String: Any] {
    let shown = visibleDesks()
    var windows: [[String: Any]] = []
    for desk in orderedDesks() {
        let area = shown.first { $0.desk === desk }?.area
        let wants = area.map(desk.layout(in:)) ?? [:]
        for window in desk.windows {
            var line = tag(window, ["desk": desk.name, "kind": desk.floating.contains(window) ? "floating" : "tiled",
                                    "shown": area != nil, "has": box(mac.frame(of: window))])
            if let rect = wants[window] { line["wants"] = box(rect) }
            if let old = hidden[window] { line["hiddenFrom"] = box(old) }
            if desk.fullscreen == window { line["covers"] = true }
            if desk.lastFocused == window { line["lastFocused"] = true }
            windows.append(line)
        }
    }
    return ["why": why, "screens": screensLog(), "current": current, "previous": previous,
            "active": activeDesk?.name ?? "",
            "monitorDesks": Dictionary(uniqueKeysWithValues: monitorDesks.map { (String($0), $1.name) }),
            "locked": locked, "asleep": asleep, "catchingUp": mac.now < catchingUpUntil,
            "covered": covered.map { Int($0) }.sorted(),
            "focus": lastFocus.flatMap(mac.number(of:)).map { Int($0) as Any } ?? NSNull(),
            "windows": windows]
}

func logSnapshot(_ why: String) {
    guard logSink != nil else { return }
    log("snapshot", snapshot(why))
    logMemory.dirty = false
}

/// The log file, in a folder. Past `limit` bytes it becomes `control.1.log` and a new one starts,
/// so the two never take more than twice the limit.
final class LogFile {
    let folder: URL
    private let limit: Int
    private var handle: FileHandle?
    private var size = 0

    var current: URL { folder.appendingPathComponent("control.log") }
    var older: URL { folder.appendingPathComponent("control.1.log") }

    /// Nil when the folder cannot be written.
    init?(folder: URL, limit: Int = 2_000_000) {
        self.folder = folder
        self.limit = limit
        guard open() else { return nil }
    }

    deinit { try? handle?.close() }

    /// Only the user can read the log. A folder that is there already keeps its own permissions.
    private func open() -> Bool {
        let files = FileManager.default
        if !files.fileExists(atPath: folder.path) {
            try? files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if !files.fileExists(atPath: current.path) {
            files.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        handle = try? FileHandle(forWritingTo: current)
        size = Int((try? handle?.seekToEnd()) ?? 0)
        return handle != nil
    }

    func write(_ line: String) {
        let data = Data((line + "\n").utf8)
        if size > 0 && size + data.count > limit {
            try? handle?.close()
            try? FileManager.default.removeItem(at: older)
            try? FileManager.default.moveItem(at: current, to: older)
            _ = open()
        }
        try? handle?.write(contentsOf: data)
        size += data.count
    }
}
