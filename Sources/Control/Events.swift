import AppKit

// Events that may change the windows on screen. Each one just calls `refresh()`.

/// One Accessibility observer per app, by process id.
private var observers: [pid_t: AXObserver] = [:]

/// Apps starting, quitting or coming to the front, and monitors changing.
func watchEvents() {
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didLaunchApplicationNotification,
                 NSWorkspace.didTerminateApplicationNotification,
                 NSWorkspace.didActivateApplicationNotification] {
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in refresh() }
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in refresh() }
}

/// Windows opening, closing, minimizing or getting focus, inside each app.
func watchApps(_ apps: [NSRunningApplication]) {
    let pids = apps.map(\.processIdentifier)
    for (pid, observer) in observers where !pids.contains(pid) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = nil
    }
    for pid in pids where observers[pid] == nil {
        var observer: AXObserver?
        AXObserverCreate(pid, { _, _, _, _ in refresh() }, &observer)
        guard let observer else { continue }
        let app = AXUIElementCreateApplication(pid)
        // An app that just launched may not answer yet. Try again on the next refresh.
        guard AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, nil) == .success
        else { continue }
        for name in [kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
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
        for (window, old) in hidden { setFrame(window, old) }
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
