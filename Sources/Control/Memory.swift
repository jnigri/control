import AppKit

// Where windows go when Control starts: back to the desk they were on.
// After a restart of Control, each window still open goes back to its own desk.
// After a reboot the windows are new, so each app goes to the desk of its oldest window.

/// The window server's number for a window. Unlike the Accessibility element, it lasts as long
/// as the window, across restarts of Control. A private call, used by most tiling window managers.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ number: UnsafeMutablePointer<CGWindowID>) -> AXError

private func number(of window: Window) -> CGWindowID? {
    var number: CGWindowID = 0
    return _AXUIElementGetWindow(window, &number) == .success ? number : nil
}

private func app(of window: Window) -> String? {
    NSRunningApplication(processIdentifier: pid(of: window))?.bundleIdentifier
}

/// Window numbers start over at each boot, so saved ones only count within the same boot.
private func bootTime() -> Int {
    var time = timeval()
    var size = MemoryLayout<timeval>.size
    sysctlbyname("kern.boottime", &time, &size, nil, 0)
    return time.tv_sec
}

/// Windows that show up this soon after Control starts get their saved desk. This covers apps
/// that reopen at login. Windows opened later stay on the desk you are on.
private let restoreTime: TimeInterval = 30

private let defaults = UserDefaults.standard
private let boot = bootTime()
private var started = Date()
private var oldWindows: [String: String] = [:]   // window number → desk name, from the last run
private var oldApps: [String: String] = [:]      // bundle identifier → desk name, from the last run
private var apps: [String: String] = [:]         // kept for apps that are not running now

/// Read what the last run saved. Call once, before the first refresh.
func loadSavedDesks() {
    started = Date()
    if defaults.integer(forKey: "boot") == boot {
        oldWindows = defaults.dictionary(forKey: "windows") as? [String: String] ?? [:]
    }
    oldApps = defaults.dictionary(forKey: "apps") as? [String: String] ?? [:]
    apps = oldApps
}

/// The desk a window had before Control started, if it is one of the first windows seen.
func savedDesk(for window: Window) -> Desk? {
    guard Date().timeIntervalSince(started) < restoreTime else { return nil }
    let name = number(of: window).flatMap { oldWindows[String($0)] } ?? app(of: window).flatMap { oldApps[$0] }
    return allDesks.first { $0.name == name }
}

/// Note the desk of every window, and of each app's oldest window (the lowest number).
/// Runs after every change, so it also holds after a crash.
func saveDesks() {
    var windows: [String: String] = [:]
    var oldest: [String: CGWindowID] = [:]
    for desk in allDesks {
        for window in desk.windows {
            guard let number = number(of: window) else { continue }
            windows[String(number)] = desk.name
            if let app = app(of: window), number < oldest[app] ?? .max {
                oldest[app] = number
                apps[app] = desk.name
            }
        }
    }
    guard windows != defaults.dictionary(forKey: "windows") as? [String: String]
          || apps != defaults.dictionary(forKey: "apps") as? [String: String]
          || boot != defaults.integer(forKey: "boot") else { return }
    defaults.set(windows, forKey: "windows")
    defaults.set(apps, forKey: "apps")
    defaults.set(boot, forKey: "boot")
}
