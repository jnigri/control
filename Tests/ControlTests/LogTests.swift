import Foundation
import Testing
@testable import Control

// The debug log: what it writes, when it stays quiet, and what it must never hold.

/// The lines the log wrote, as text and read back as JSON.
final class Recorder {
    var lines: [String] = []
    var events: [[String: Any]] {
        lines.map { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] ?? [:] }
    }
    var names: [String] { events.map { $0["e"] as? String ?? "" } }
    func all(_ name: String) -> [[String: Any]] { events.filter { $0["e"] as? String == name } }
}

/// Switch the log on, as the settings would, and keep what it writes.
func recordLog() -> Recorder {
    let recorder = Recorder()
    logMemory = LogMemory()
    logSink = { recorder.lines.append($0) }
    return recorder
}

/// A new, empty folder for a test.
func temporaryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("control-tests-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

extension ControlTests {
    @Test func theLogIsOffUntilSwitchedOn() {
        var built = false
        log("anything", { built = true; return ["a": 1] }())
        fake.opens(1)
        #expect(!built)
        #expect(logMemory.layout == Layout())
    }

    @Test func everyLineIsJSONWithATimeAndAnEvent() {
        let log = recordLog()
        fake.opens(1)
        fake.opens(2)
        show("2")
        logSnapshot("test")
        #expect(log.lines.count > 5)
        for (line, event) in zip(log.lines, log.events) {
            #expect(event["t"] is String && event["e"] is String, "\(line)")
            #expect(line.hasPrefix("{\"t\":\""), "\(line)")
        }
    }

    @Test func aWindowIsFollowedFromOpeningToClosing() throws {
        let log = recordLog()
        let a = fake.opens(1)
        let adopt = try #require(log.all("adopt").first)
        #expect(adopt["w"] as? Int == 1)
        #expect(adopt["app"] as? String == "app.1")
        #expect(adopt["desk"] as? String == "1")
        #expect(adopt["rule"] as? String == "monitor under it")
        #expect(log.all("place").first?["took"] as? [Double] == box(whole))

        send(to: "2")
        let move = try #require(log.all("desk").first { $0["did"] as? String == "move" })
        #expect(move["from"] as? String == "1" && move["to"] as? String == "2")

        show("1")
        #expect(log.all("park").first?["w"] as? Int == 1)
        #expect(log.all("layout").last?["desks"] as? [String: [Int]] == ["2": [1]])
        #expect(log.all("layout").last?["current"] as? String == "1")

        fake.closes(a)
        #expect(log.all("gone").first?["desk"] as? String == "2")
        #expect(log.all("layout").last?["desks"] as? [String: [Int]] == [:])
    }

    @Test func aNewWindowOnTheActiveDeskSaysSo() {
        let log = recordLog()
        fake.screens = [mainMonitor, rightMonitor]
        fake.opens(1, on: mainMonitor)
        fake.opens(2, on: mainMonitor, at: rightMonitor)
        #expect(log.all("adopt").last?["rule"] as? String == "active desk")
        #expect(log.all("adopt").last?["desk"] as? String == "1")
        #expect(log.all("monitor-desk").first?["desk"] as? String == "0")
    }

    @Test func aWindowThatRefusesItsSizeIsNoted() throws {
        let log = recordLog()
        fake.opens(1)
        fake.minimums[window(2)] = CGSize(width: 600, height: 500)
        fake.opens(2)
        let refused = try #require(log.all("refused").first)
        #expect(refused["w"] as? Int == 2)
        // The right half is 488 wide: the window sticks out by 112 on the right.
        #expect(refused["gaps"] as? [Double] == [0, 0, -112, 0])
    }

    @Test func nothingIsWrittenWhenNothingChanges() {
        let log = recordLog()
        fake.opens(1)
        fake.opens(2)
        let count = log.lines.count
        refresh()
        refresh()
        arrange()
        #expect(log.lines.count == count, "\(log.lines.dropFirst(count))")
    }

    @Test func sleepWithAMonitorGoneIsToldInOrder() {
        fake.screens = [mainMonitor, rightMonitor]
        fake.opens(1, on: mainMonitor)
        fake.opens(2, on: rightMonitor)
        let log = recordLog()
        refresh()
        log.lines = []

        asleep = true
        refresh()
        fake.unreported = Set(fake.open)
        fake.plugs([mainMonitor])
        asleep = false
        resume()
        fake.unreported = []
        fake.now = fake.now.addingTimeInterval(catchUpTime)
        refresh()
        logSnapshot("caught up")

        let told = log.names.filter { ["skip", "resume", "monitors", "monitor-desk", "catch-up", "kept", "snapshot"].contains($0) }
        #expect(told == ["skip", "resume", "monitors", "monitor-desk", "catch-up", "kept", "catch-up", "kept", "snapshot"])
        #expect(log.all("skip").first?["why"] as? String == "asleep")
        #expect(log.all("monitor-desk").first?["did"] as? String == "lost")
        let kept = log.all("kept").first?["windows"] as? [[String: Any]] ?? []
        #expect(Set(kept.compactMap { $0["w"] as? Int }) == [1, 2])
        #expect(kept.allSatisfy { $0["why"] as? String == "catching up" })
        #expect(log.all("gone").isEmpty)
    }

    @Test func theSnapshotSaysWhereEveryWindowIs() throws {
        fake.opens(1)
        fake.opens(2)
        show("2")
        fake.opens(3, dialog: true)
        let picture = snapshot("test")
        let windows = try #require(picture["windows"] as? [[String: Any]])
        #expect(windows.count == 3)
        for line in windows {
            let one = window(try #require(line["w"] as? Int))
            #expect(line["desk"] as? String == desk(of: one)?.name)
            #expect(line["has"] as? [Double] == box(fake.frames[one]!))
            #expect(line["shown"] as? Bool == (desk(of: one)?.name == "2"))
            #expect(line["kind"] as? String == (fake.dialogs.contains(one) ? "floating" : "tiled"))
            #expect((line["hiddenFrom"] != nil) == (hidden[one] != nil))
        }
        #expect(picture["current"] as? String == "2")
        #expect(JSONSerialization.isValidJSONObject(picture))
    }

    @Test func titlesAndTypedTextNeverReachTheLog() throws {
        let log = recordLog()
        for number in 1...3 {
            let new = fake.opens(number)
            fake.titles[new] = "SECRET plans"
            fake.names[new] = "SECRET app"
        }
        show("2")
        try Command(["focus", "title", "secret"]).run()
        try Command(["focus", "app", "SECRET app"]).run()
        #expect(throws: CommandError.self) { try Command(["focus", "title", "SECRET nothing"]).run() }
        _ = try Command(["ls"]).run()
        logSnapshot("test")
        #expect(log.names.contains("command"))
        #expect(!log.lines.contains { $0.localizedCaseInsensitiveContains("secret") })
    }

    @Test func anExportHoldsTheLogAndNoTitle() throws {
        let logs = temporaryFolder(), out = temporaryFolder(), opened = temporaryFolder()
        defer { for folder in [logs, out, opened] { try? FileManager.default.removeItem(at: folder) } }
        let file = try #require(LogFile(folder: logs))
        logMemory = LogMemory()
        logSink = { file.write($0) }
        let a = fake.opens(1)
        fake.titles[a] = "SECRET plans"
        fake.names[a] = "SECRET app"
        let settings = logs.appendingPathComponent("settings.json").path
        try saveConfig(Config(), to: settings)

        let zip = try exportLog(into: out, logFolder: logs, configFile: settings)
        #expect(zip.lastPathComponent == exportName(at: fake.now) + ".zip")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, opened.path]
        try unzip.run()
        unzip.waitUntilExit()

        let inside = opened.appendingPathComponent(exportName(at: fake.now))
        let names = try FileManager.default.contentsOfDirectory(atPath: inside.path).sorted()
        #expect(names == ["config.json", "control.log", "info.txt", "snapshot.json"])
        for name in names {
            let text = try String(contentsOf: inside.appendingPathComponent(name), encoding: .utf8)
            #expect(!text.contains("SECRET"), "\(name)")
            #expect(!text.isEmpty, "\(name)")
        }
        let log = try String(contentsOf: inside.appendingPathComponent("control.log"), encoding: .utf8)
        #expect(log.contains("\"e\":\"adopt\"") && log.contains("\"why\":\"export\""))
    }

    @Test func anExportWorksWithTheLogOff() throws {
        let out = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: out) }
        fake.opens(1)
        let zip = try exportLog(into: out, logFolder: out.appendingPathComponent("none"), configFile: "/none/config.json")
        #expect(FileManager.default.fileExists(atPath: zip.path))
        #expect(try Command(["export", out.path]).run() == zip.path)
    }
}

@Suite struct LogFileTests {
    @Test func theLogFileStartsOverWhenItIsFull() throws {
        let folder = temporaryFolder().appendingPathComponent("made/on/the/way")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try #require(LogFile(folder: folder, limit: 500))
        for number in 0..<40 { file.write("line \(number) " + String(repeating: "x", count: 40)) }

        let now = try String(contentsOf: file.current, encoding: .utf8)
        let before = try String(contentsOf: file.older, encoding: .utf8)
        #expect(now.utf8.count <= 500 && before.utf8.count <= 500)
        #expect(now.hasSuffix("line 39 " + String(repeating: "x", count: 40) + "\n"))
        // The older file ends right where the new one starts.
        let first = try #require(now.split(separator: "\n").first.flatMap { Int($0.split(separator: " ")[1]) })
        #expect(before.contains("line \(first - 1) "))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["control.1.log", "control.log"])
    }

    @Test func onlyTheUserCanReadTheLog() throws {
        let folder = temporaryFolder().appendingPathComponent("logs")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try #require(LogFile(folder: folder))
        file.write("a line")
        #expect(try FileManager.default.attributesOfItem(atPath: file.current.path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int == 0o700)
    }

    @Test func aLogKeepsGoingAfterARestart() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        LogFile(folder: folder)?.write("first")
        LogFile(folder: folder)?.write("second")
        #expect(try String(contentsOf: folder.appendingPathComponent("control.log"), encoding: .utf8) == "first\nsecond\n")
    }

    @Test func aFolderThatCannotBeWrittenGivesNoLog() {
        #expect(LogFile(folder: URL(fileURLWithPath: "/dev/null/logs")) == nil)
    }
}
