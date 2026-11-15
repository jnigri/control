import Foundation
import CoreGraphics

// Where windows go when Control starts: back to the desk they were on.
// After a restart of Control, each window still open goes back to its own desk.
// After a reboot the windows are new, so each app goes to the desk of its oldest window.

/// Windows that show up this soon after Control starts get their saved desk. This covers apps
/// that reopen at login. Windows opened later stay on the desk you are on.
private let restoreTime: TimeInterval = 30

private var started = Date()
private var oldWindows: [String: String] = [:]   // window number → desk name, from the last run
private var oldApps: [String: String] = [:]      // bundle identifier → desk name, from the last run
private var apps: [String: String] = [:]         // kept for apps that are not running now

/// Read what the last run saved. Call once, before the first refresh.
func loadSavedDesks() {
    started = mac.now
    // Window numbers start over at each boot, so saved ones only count within the same boot.
    let sameBoot = mac.saved("boot") as? Int == mac.bootTime
    oldWindows = sameBoot ? mac.saved("windows") as? [String: String] ?? [:] : [:]
    oldApps = mac.saved("apps") as? [String: String] ?? [:]
    apps = oldApps
}

/// The desk a window had before Control started, if it is one of the first windows seen.
func savedDesk(for window: Window) -> Desk? {
    guard mac.now.timeIntervalSince(started) < restoreTime else { return nil }
    let name = mac.number(of: window).flatMap { oldWindows[String($0)] } ?? mac.app(of: window).flatMap { oldApps[$0] }
    return allDesks.first { $0.name == name }
}

/// Note the desk of every window, and of each app's oldest window (the lowest number).
/// Runs after every change, so it also holds after a crash.
func saveDesks() {
    var windows: [String: String] = [:]
    var oldest: [String: CGWindowID] = [:]
    for desk in allDesks {
        for window in desk.windows {
            guard let number = mac.number(of: window) else { continue }
            windows[String(number)] = desk.name
            if let app = mac.app(of: window), number < oldest[app] ?? .max {
                oldest[app] = number
                apps[app] = desk.name
            }
        }
    }
    guard windows != mac.saved("windows") as? [String: String]
          || apps != mac.saved("apps") as? [String: String]
          || mac.bootTime != mac.saved("boot") as? Int else { return }
    mac.save(windows, as: "windows")
    mac.save(apps, as: "apps")
    mac.save(mac.bootTime, as: "boot")
}
