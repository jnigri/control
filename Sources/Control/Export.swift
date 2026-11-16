import Foundation

// The debug log, packed into one zip to send with a bug report. Nothing is sent from here:
// the zip lands in a folder and the user does the rest.
//
// Inside: the two log files, `snapshot.json` (where everything is right now), `info.txt`
// (which Control, which macOS, which Mac, which monitors) and `config.json`.
// Like the log, none of them holds a window title.

/// The name of an export made now: `Control-log-2026-11-16-0914`.
func exportName(at date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd-HHmm"
    return "Control-log-" + formatter.string(from: date)
}

/// Make the zip in a folder (the Desktop when nil) and say where it is.
@discardableResult
func exportLog(into folder: URL? = nil, logFolder: URL = config.logFolderURL, configFile: String = configPath) throws -> URL {
    let files = FileManager.default
    let folder = folder ?? files.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    let name = exportName(at: mac.now)
    let zip = folder.appendingPathComponent(name + ".zip")
    // The files are gathered in a folder of the same name, which the zip then holds.
    let staging = files.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
    try files.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: staging.deletingLastPathComponent()) }

    logSnapshot("export")
    for file in ["control.1.log", "control.log"] {
        let from = logFolder.appendingPathComponent(file)
        if files.fileExists(atPath: from.path) { try files.copyItem(at: from, to: staging.appendingPathComponent(file)) }
    }
    if files.fileExists(atPath: configFile) {
        try files.copyItem(atPath: configFile, toPath: staging.appendingPathComponent("config.json").path)
    }
    let picture = try JSONSerialization.data(withJSONObject: snapshot("export"),
                                             options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try picture.write(to: staging.appendingPathComponent("snapshot.json"))
    try Data(exportInfo(logFolder: logFolder).utf8).write(to: staging.appendingPathComponent("info.txt"))

    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    try? files.removeItem(at: zip)
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", "--keepParent", staging.path, zip.path]
    try ditto.run()
    ditto.waitUntilExit()
    guard ditto.terminationStatus == 0 else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "the zip could not be written in \(folder.path)"])
    }
    return zip
}

/// What a developer needs to know about the Mac to read the log.
func exportInfo(logFolder: URL) -> String {
    var model = [CChar](repeating: 0, count: 256)
    var size = model.count
    sysctlbyname("hw.model", &model, &size, nil, 0)

    // The time of the oldest line still in the log.
    let oldest = ["control.1.log", "control.log"].lazy
        .compactMap { try? FileHandle(forReadingFrom: logFolder.appendingPathComponent($0)) }
        .compactMap { handle -> String? in
            defer { try? handle.close() }
            let start = String(decoding: (try? handle.read(upToCount: 64)) ?? Data(), as: UTF8.self)
            let parts = start.components(separatedBy: "\"")
            return parts.count > 3 && parts[1] == "t" ? parts[3] : nil
        }.first

    var lines = [
        "Control: \(version)",
        "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
        "Mac: \(String(cString: model))",
        "Exported: \(ISO8601DateFormatter().string(from: mac.now))",
        "Debug log: \(logSink == nil ? "off" : "on")" + (oldest.map { ", oldest line \($0)" } ?? ""),
        "Displays have separate Spaces: \(mac.separateSpaces ? "yes" : "no")",
        "Monitors, main one first (x, y, width, height; y goes down from the top of the main one):",
    ]
    for screen in mac.screens {
        lines.append("  \(screen.id): whole \(box(screen.frame)), usable \(box(screen.area))")
    }
    lines += ["", "These files hold window numbers, positions and the bundle identifiers of the apps in use.",
              "They hold no window titles."]
    return lines.joined(separator: "\n") + "\n"
}
