import AppKit
import ServiceManagement

// MARK: Settings

let gap: CGFloat = 8                // space around each tiled window, in points
let resizeStep: CGFloat = 0.05      // how much Option + Minus / Equal moves a split
let deskKeys = "123456789ABCDEGIMNOPQRSTUVWXYZ".map(String.init)  // every letter except F, H, J, K, L

// MARK: Start

// Ask for the Accessibility permission. The first time, macOS shows a prompt.
guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
    print("Grant Accessibility permission in System Settings, then run again.")
    exit(1)
}

// A menu bar app: no Dock icon, no main window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// The menu bar shows the current desk key. Click it to list the desks.
let menuBar = MenuBar()

// Keys. See the table in README.md.
for key in deskKeys {
    bind(key) { show(key) }
    bind(key, shift: true) { send(to: key) }
}
bind("Tab") { show(previous) }
for (key, direction) in [("H", Direction.left), ("J", .down), ("K", .up), ("L", .right)] {
    bind(key) { moveFocus(direction) }
    bind(key, shift: true) { swap(direction) }
}
bind("Minus") { resize(by: -resizeStep) }
bind("Equal") { resize(by: resizeStep) }
bind("F", shift: true) { toggleFullscreen() }
bind("Space", shift: true) { toggleFloating() }
listenForKeys()

// Tile again whenever windows, apps or monitors change.
watchEvents()

// On quit (menu, Ctrl+C or kill), bring hidden windows back so none get lost off screen.
quitCleanly()

// Start at login. This only works from Control.app, not from `swift run`.
if Bundle.main.bundleIdentifier != nil {
    try? SMAppService.mainApp.register()
}

refresh()
app.run()
