import Foundation

// The settings you can change while Control runs. They live in `~/.config/control/config.json`,
// and that file is the source of truth: Control reads it when it starts and on "Sync settings",
// and the settings window writes every change to it.

struct Config: Codable, Equatable {
    /// Write the debug log (see `Log.swift`). Off by default: the log says which apps you use.
    var log = false
    var logFolder = "~/Library/Logs/Control"

    init() {}

    /// A key missing from the file keeps its default.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        log = try values.decodeIfPresent(Bool.self, forKey: .log) ?? log
        logFolder = try values.decodeIfPresent(String.self, forKey: .logFolder) ?? logFolder
    }

    var logFolderURL: URL { URL(fileURLWithPath: (logFolder as NSString).expandingTildeInPath) }
}

let configPath = ("~/.config/control/config.json" as NSString).expandingTildeInPath

/// Read the file. Nil when there is none. Throws when it is there but cannot be understood.
func loadConfig(from path: String) throws -> Config? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

func saveConfig(_ config: Config, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(config)
    data.append(UInt8(ascii: "\n"))
    try data.write(to: url, options: .atomic)
}

/// Change one setting in the file. The file is read first, so what was edited there by hand
/// stays. A file that cannot be understood is left alone: this throws instead.
func editConfig(at path: String, or fallback: Config = Config(), _ edit: (inout Config) -> Void) throws -> Config {
    var config = try loadConfig(from: path) ?? fallback
    edit(&config)
    try saveConfig(config, to: path)
    return config
}

// The settings in use, in the running app.

var config = Config()

/// Why the file or the log folder could not be used, for the settings window.
var configError: String?

private var logFile: LogFile?

/// Take the settings from the file. Without a file, write one with the settings in use.
/// A file that cannot be understood changes nothing.
func syncConfig() {
    do {
        if let fromFile = try loadConfig(from: configPath) {
            config = fromFile
        } else {
            try saveConfig(config, to: configPath)
        }
        configError = nil
    } catch {
        configError = "config.json could not be read: \(describe(error))"
    }
    applyConfig()
}

/// Change a setting from the settings window.
func changeConfig(_ edit: (inout Config) -> Void) {
    do {
        config = try editConfig(at: configPath, or: config, edit)
        configError = nil
    } catch {
        configError = "config.json could not be changed: \(describe(error))"
    }
    applyConfig()
}

/// Start, stop or move the log to match the settings.
func applyConfig() {
    guard config.log else {
        if logSink != nil { log("log-off") }
        logSink = nil
        logFile = nil
        return
    }
    if logFile?.folder == config.logFolderURL && logSink != nil { return }
    guard let file = LogFile(folder: config.logFolderURL) else {
        logSink = nil
        logFile = nil
        configError = "The log cannot be written in \(config.logFolder)."
        return
    }
    logFile = file
    logSink = { [weak file] in file?.write($0) }
    // A new log starts with everything it needs to be read on its own.
    logMemory = LogMemory()
    log("start", ["control": version, "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                  "separateSpaces": mac.separateSpaces, "gap": Double(gap), "screens": screensLog(),
                  "monitorKeys": Dictionary(uniqueKeysWithValues: monitorKeys.map { (String($0), $1) })])
    logSnapshot("log on")
}

/// The build, as `bundle.sh` wrote it into the app: the date and commit of the code.
let version: String = {
    let info = Bundle.main.infoDictionary
    guard let date = info?["CFBundleShortVersionString"] as? String else { return "development build" }
    return "\(date) (\(info?["CFBundleVersion"] as? String ?? "?"))"
}()

private func describe(_ error: Error) -> String {
    if let error = error as? DecodingError {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context),
             .dataCorrupted(let context):
            let key = context.codingPath.map(\.stringValue).joined(separator: ".")
            return key.isEmpty ? "it is not valid JSON" : "\"\(key)\" has the wrong kind of value"
        @unknown default: break
        }
    }
    return error.localizedDescription
}
