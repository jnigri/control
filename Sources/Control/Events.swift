import AppKit

// Events that may change the windows on screen. Almost every one just calls `refresh()`.

/// One Accessibility observer per app, by process id.
private var observers: [pid_t: AXObserver] = [:]

/// The window the user is dragging or resizing with the mouse right now.
private var dragged: Window?

/// Something changed. In the middle of a mouse drag, wait: tiling now would pull the window
/// out of the user's hand. The end of the drag catches up.
private func changed() {
    if dragged != nil && NSEvent.pressedMouseButtons & 1 == 1 { return }
    refresh()
}

/// Apps starting, quitting or coming to the front, and monitors changing.
func watchEvents() {
    let workspace = NSWorkspace.shared.notificationCenter
    // A Space change comes with a window entering or leaving macOS's own full screen mode.
    for name in [NSWorkspace.didLaunchApplicationNotification,
                 NSWorkspace.didTerminateApplicationNotification,
                 NSWorkspace.didActivateApplicationNotification,
                 NSWorkspace.activeSpaceDidChangeNotification] {
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in changed() }
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in changed() }
    // Pause while the screen is locked, and catch up on unlock.
    let distributed = DistributedNotificationCenter.default()
    distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
        locked = true
    }
    distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
        locked = false
        refresh()
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

/// An app says something happened to one of its windows.
private func heard(_ element: AXUIElement, _ name: String) {
    guard name == kAXWindowMovedNotification || name == kAXWindowResizedNotification else { return changed() }
    // A window moves or changes size. With the mouse button down, the user is doing it: wait until
    // they let go. Otherwise it is us, or the app itself, and there is nothing to do.
    if NSEvent.pressedMouseButtons & 1 == 1 { dragged = element }
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
        for (window, old) in hidden { mac.setFrame(window, old) }
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
