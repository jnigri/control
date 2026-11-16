import Foundation
import Testing
@testable import Control

// The settings file: `~/.config/control/config.json` in the app, a temporary one here.

@Suite struct ConfigTests {
    let path = temporaryFolder().appendingPathComponent("control/config.json").path

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test func withoutAFileThereIsNothingToLoad() throws {
        #expect(try loadConfig(from: path) == nil)
        #expect(Config().log == false)
        #expect(Config().logFolder == "~/Library/Logs/Control")
    }

    @Test func savingThenLoadingGivesTheSameSettings() throws {
        var config = Config()
        config.log = true
        config.logFolder = "~/Desktop/logs"
        try saveConfig(config, to: path)
        #expect(try loadConfig(from: path) == config)
        // Written for people too: one setting per line, paths as they are.
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text == "{\n  \"log\" : true,\n  \"logFolder\" : \"~/Desktop/logs\"\n}\n")
    }

    @Test func aMissingKeyKeepsItsDefault() throws {
        try write(#"{"log": true}"#)
        let config = try #require(try loadConfig(from: path))
        #expect(config.log)
        #expect(config.logFolder == Config().logFolder)
        try write("{}")
        #expect(try loadConfig(from: path) == Config())
    }

    @Test func aBrokenFileIsLeftAlone() throws {
        for broken in ["{ not json", #"{"log": "yes"}"#] {
            try write(broken)
            #expect(throws: (any Error).self) { try loadConfig(from: path) }
            #expect(throws: (any Error).self) { try editConfig(at: path) { $0.log = true } }
            #expect(try String(contentsOfFile: path, encoding: .utf8) == broken)
        }
    }

    @Test func anEditKeepsWhatWasChangedByHand() throws {
        try write(#"{"logFolder": "/tmp/by-hand"}"#)
        let config = try editConfig(at: path) { $0.log = true }
        #expect(config.log && config.logFolder == "/tmp/by-hand")
        #expect(try loadConfig(from: path) == config)
    }

    @Test func anEditWithoutAFileStartsFromTheSettingsInUse() throws {
        var inUse = Config()
        inUse.logFolder = "/tmp/in-use"
        let config = try editConfig(at: path, or: inUse) { $0.log = true }
        #expect(config.log && config.logFolder == "/tmp/in-use")
    }

    @Test func theHomeFolderIsWrittenAsATilde() {
        var config = Config()
        #expect(config.logFolderURL.path == NSHomeDirectory() + "/Library/Logs/Control")
        config.logFolder = "/tmp/logs"
        #expect(config.logFolderURL.path == "/tmp/logs")
    }
}

@Suite struct ExportWordTests {
    @Test func exportIsACommand() throws {
        #expect(try Command(["export"]) == .export(nil))
        #expect(try Command(["export", "/tmp/out"]) == .export("/tmp/out"))
        #expect(throws: CommandError.self) { try Command(["export", "a", "b"]) }
    }
}
