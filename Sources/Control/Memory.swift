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
private var startWindows: Set<Window> = []       // the windows open when Control started
private var startApps: Set<String> = []          // the apps those windows belong to

/// Windows that left their desk without being minimized, by window number: the desk and when.
/// Most really closed. But an app slow to wake up may answer that it has no windows at all, long
/// after the others caught up. Before, its windows then came back as new ones, all on the desk you
/// were on. Window numbers are not reused within a boot, so the same number is the same window.
private var gone: [CGWindowID: (desk: String, at: Date)] = [:]
private let goneTime: TimeInterval = 3600

/// Read what the last run saved. Call once, before the first refresh.
func loadSavedDesks() {
    started = mac.now
    // Window numbers start over at each boot, so saved ones only count within the same boot.
    let sameBoot = mac.saved("boot") as? Int == mac.bootTime
    oldWindows = sameBoot ? mac.saved("windows") as? [String: String] ?? [:] : [:]
    oldApps = mac.saved("apps") as? [String: String] ?? [:]
    apps = oldApps
    let monitors = mac.saved("monitors") as? [String: String] ?? [:]
    monitorKeys = Dictionary(uniqueKeysWithValues: monitors.compactMap { id, key in CGDirectDisplayID(id).map { ($0, key) } })
    gone = [:]
    loadHistory()
    startWindows = Set(mac.windows())
    startApps = Set(startWindows.compactMap(mac.app(of:)))
}

func wasOpenAtStart(_ window: Window) -> Bool { startWindows.contains(window) }

/// The desk a window had before Control started, if it is one of the first windows seen.
/// The app's desk is only a guess for windows coming back: those open at the start, or from an
/// app that had none then (it reopens at login). A new window of an app already open is one
/// you just made, so it stays on the desk you are on.
func savedDesk(for window: Window) -> Desk? {
    guard mac.now.timeIntervalSince(started) < restoreTime else { return nil }
    var name = mac.number(of: window).flatMap { oldWindows[String($0)] }
    if name == nil, let app = mac.app(of: window), startWindows.contains(window) || !startApps.contains(app) {
        name = oldApps[app]
    }
    return name.flatMap { desks[$0] }
}

/// A window left its desk, maybe for a moment only.
func rememberGone(_ window: Window, from desk: Desk) {
    gone = gone.filter { mac.now.timeIntervalSince($0.value.at) < goneTime }
    guard let number = mac.number(of: window) else { return }
    gone[number] = (desk.name, mac.now)
}

/// The desk a window was on when it went missing, if it is one of those coming back.
func goneDesk(for window: Window) -> Desk? {
    guard let number = mac.number(of: window), let was = gone.removeValue(forKey: number),
          mac.now.timeIntervalSince(was.at) < goneTime else { return nil }
    return desks[was.desk]
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
