import AppKit
import ServiceManagement

// With words, like `control show 3`, this is the command line: it asks the running app. See Socket.swift.
if CommandLine.arguments.count > 1 {
    exit(commandLine(Array(CommandLine.arguments.dropFirst())))
}

// Ask for the Accessibility permission. The first time, macOS shows a prompt.
guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
    print("Grant Accessibility permission in System Settings, then run again.")
    exit(1)
}

// A menu bar app: no Dock icon, no main window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// The menu bar shows the current desk key. Click it, or press Option + Slash, to list the desks.
let menuBar = MenuBar()
let settingsWindow = SettingsWindow()

// Keys. See the table in README.md.
for key in deskKeys {
    bind(key, .show(key))
    bind(key, shift: true, .send(key))
}
bind("Tab", .showPrevious)
for (key, direction) in [("H", Direction.left), ("J", .down), ("K", .up), ("L", .right)] {
    bind(key, .focus(direction))
    bind(key, shift: true, .swap(direction))
}
bind("Minus", .shrink)
bind("Equal", .grow)
bind("F", shift: true, .fullscreen)
bind("Space", shift: true, .float)
bind("Slash", .menu)
listenForKeys()

// The same commands, from the command line.
let listener = Listener { words in try Command(words).run() }
if listener == nil { print("Cannot listen on \(socketPath): the command line will not work.") }

// Tile again whenever windows, apps or monitors change.
watchEvents()

// On quit (menu, Ctrl+C or kill), bring hidden windows back so none get lost off screen.
quitCleanly()

// Start at login. This only works from Control.app, not from `swift run`.
if Bundle.main.bundleIdentifier != nil {
    try? SMAppService.mainApp.register()
}

// Put windows back on the desks they had at the last run.
loadSavedDesks()

// The settings in `~/.config/control/config.json`. They may switch the debug log on.
syncConfig()

refresh()
app.run()
