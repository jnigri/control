import AppKit

// Events that may change the windows on screen. Almost every one just calls `refresh()`.

/// One Accessibility observer per app, by process id.
private var observers: [pid_t: AXObserver] = [:]

/// The window the user is dragging or resizing with the mouse right now.
private var dragged: Window?

/// Something changed. In the middle of a mouse drag, wait: tiling now would pull the window
/// out of the user's hand. The end of the drag catches up.
private func changed() {
    if dragged != nil && NSEvent.pressedMouseButtons & 1 == 1 {
        logChange("skip", \.skip, "drag in progress") { ["why": $0] }
        return
    }
    refresh()
}

/// The app a workspace notification is about, for the debug log.
private func appLog(_ note: Notification) -> [String: Any] {
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return [:] }
    return ["app": app.bundleIdentifier ?? "?", "pid": Int(app.processIdentifier)]
}

/// How often the debug log gets the whole picture, when something happened since the last one.
private let snapshotTime: TimeInterval = 600

/// Apps starting, quitting or coming to the front, and monitors changing.
func watchEvents() {
    let workspace = NSWorkspace.shared.notificationCenter
    // A Space change comes with a window entering or leaving macOS's own full screen mode.
    for (name, event) in [(NSWorkspace.didLaunchApplicationNotification, "app-launch"),
                          (NSWorkspace.didTerminateApplicationNotification, "app-quit"),
                          (NSWorkspace.didActivateApplicationNotification, "app-front"),
                          (NSWorkspace.activeSpaceDidChangeNotification, "space")] {
        workspace.addObserver(forName: name, object: nil, queue: .main) { note in
            log(event, appLog(note))
            changed()
        }
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in
        log("monitors-changed")
        logMonitors()
        changed()
        // macOS moves windows about for a moment after: see where they ended up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { logSnapshot("monitors changed") }
    }
    // Pause while the Mac sleeps or the screen is locked, and catch up after.
    for (name, heard) in [(NSWorkspace.willSleepNotification, "willSleep"),
                          (NSWorkspace.screensDidSleepNotification, "screensDidSleep")] {
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
            asleep = true
            log("sleep", ["heard": heard, "locked": locked])
        }
    }
    for (name, heard) in [(NSWorkspace.didWakeNotification, "didWake"),
                          (NSWorkspace.screensDidWakeNotification, "screensDidWake")] {
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
            asleep = false
            log("wake", ["heard": heard, "locked": locked])
            catchUp()
        }
    }
    let distributed = DistributedNotificationCenter.default()
    distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
        locked = true
        log("lock", ["asleep": asleep])
    }
    distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
        locked = false
        log("unlock", ["asleep": asleep])
        catchUp()
    }
    Timer.scheduledTimer(withTimeInterval: snapshotTime, repeats: true) { _ in
        if logMemory.dirty && !paused { logSnapshot("a while since the last one") }
    }
    // A click gives the focus to the window under the pointer: the pointer stays there.
    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
        clickedAt = mac.now
    }
    // The end of a mouse drag: see what the user did with the window.
    NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
        guard let window = dragged else { return }
        dragged = nil
        // AppKit measures from the bottom-left of the main monitor, so flip y.
        let pointer = NSEvent.mouseLocation
        dropped(window, at: CGPoint(x: pointer.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - pointer.y))
    }
}

/// The Mac woke up or the screen unlocked. Once apps have had time to report their windows again,
/// look once more: the windows still missing then really closed meanwhile.
private func catchUp() {
    resume()
    DispatchQueue.main.asyncAfter(deadline: .now() + catchUpTime + 1) {
        changed()
        if !paused { logSnapshot("caught up") }
    }
}

/// What apps said since the last line about it, for the debug log. Apps say a lot: every move and
/// resize, ours included, and every button or menu that goes away. Those are counted and written
/// together, at most twice a second.
private struct Heard: Hashable {
    let what: String
    let pid: pid_t
    let window: CGWindowID?
}
private var heardCounts: [Heard: Int] = [:]

private func logHeard(_ element: AXUIElement, _ name: String) {
    guard logSink != nil else { return }
    let heard = Heard(what: name, pid: pid(of: element), window: mac.number(of: element))
    let app = mac.app(of: element) ?? "?"
    // Something about a window, and not a move: worth a line of its own, at its own time.
    if let window = heard.window, name != kAXWindowMovedNotification, name != kAXWindowResizedNotification {
        return log("heard", ["what": name, "w": Int(window), "app": app, "pid": Int(heard.pid)])
    }
    if heardCounts.isEmpty {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let counts = heardCounts
            heardCounts = [:]
            log("heard-many", ["counts": counts.map { heard, count in
                ["what": heard.what, "w": heard.window.map { Int($0) as Any } ?? NSNull(), "pid": Int(heard.pid),
                 "app": NSRunningApplication(processIdentifier: heard.pid)?.bundleIdentifier ?? "?", "times": count]
            }])
        }
    }
    heardCounts[heard, default: 0] += 1
}

/// An app says something happened to one of its windows.
private func heard(_ element: AXUIElement, _ name: String) {
    logHeard(element, name)
    guard name == kAXWindowMovedNotification || name == kAXWindowResizedNotification else { return changed() }
    // A window moves or changes size. With the mouse button down, the user is doing it: wait until
    // they let go. Otherwise it is us, or the app itself, and there is nothing to do.
    if NSEvent.pressedMouseButtons & 1 == 1 {
        if dragged != element { log("drag", tag(element, ["frame": box(mac.frame(of: element))])) }
        dragged = element
    }
}

/// Windows opening, closing, minimizing, getting focus, moving or changing size, inside each app.
func watchApps(_ apps: [NSRunningApplication]) {
    let pids = apps.map(\.processIdentifier)
    for (pid, observer) in observers where !pids.contains(pid) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = nil
    }
    for pid in pids where observers[pid] == nil {
        var observer: AXObserver?
        AXObserverCreate(pid, { _, element, name, _ in heard(element, name as String) }, &observer)
        guard let observer else { continue }
        let app = AXUIElementCreateApplication(pid)
        // An app that just launched may not answer yet. Try again on the next refresh.
        guard AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, nil) == .success
        else { continue }
        for name in [kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                     kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }
}

/// Signal handlers must stay alive, so keep them here.
private var signalSources: [DispatchSourceSignal] = []

/// Before quitting, put hidden windows back where they were.
func quitCleanly() {
    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                           object: nil, queue: .main) { _ in
        logSnapshot("quit")
        log("quit")
        for (window, old) in hidden { mac.setFrame(window, old) }
        unlink(socketPath)
    }
    // Ctrl+C and `kill` send signals. Turn them into a normal quit.
    for signal in [SIGINT, SIGTERM] {
        Darwin.signal(signal, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
        source.setEventHandler { NSApplication.shared.terminate(nil) }
        source.resume()
        signalSources.append(source)
    }
}
