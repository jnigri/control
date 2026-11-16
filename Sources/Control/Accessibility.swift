import AppKit

// Everything Control asks of macOS goes through `mac`. The app talks to the real thing, mostly
// with the Accessibility API, which moves and reads other apps' windows. The tests swap in a fake.
// Coordinates start at the top-left of the main monitor, y going down.

typealias Window = AXUIElement

struct Screen {
    let id: CGDirectDisplayID
    let frame: CGRect   // the whole monitor
    let area: CGRect    // the usable part: no menu bar, no Dock
}

protocol System: AnyObject {
    /// The monitors, main one first.
    var screens: [Screen] { get }
    /// Whether each monitor switches macOS Spaces on its own (the macOS default).
    var separateSpaces: Bool { get }
    var now: Date { get }
    /// When the Mac started, in seconds. Window numbers start over at each boot.
    var bootTime: Int { get }

    /// The windows we care about, of every app.
    func windows() -> [Window]
    /// The apps that gave no answer the last time `windows()` asked. Their windows may still be open.
    var silentApps: Set<pid_t> { get }
    func focusedWindow() -> Window?
    func focus(_ window: Window)
    /// Take the focus away from every window.
    func unfocus()
    func frame(of window: Window) -> CGRect
    func setFrame(_ window: Window, _ rect: CGRect)
    func setPosition(_ window: Window, _ point: CGPoint)
    /// Dialogs, popups and fixed-size windows float. Normal windows tile.
    func shouldFloat(_ window: Window) -> Bool
    /// Whether a window is in macOS's own full screen mode (the green button), on a Space of its own.
    func isFullScreen(_ window: Window) -> Bool
    /// The window server's number for a window. It lasts as long as the window.
    func number(of window: Window) -> CGWindowID?
    /// The bundle identifier of the app that owns a window.
    func app(of window: Window) -> String?
    /// The name of that app, as the Dock shows it.
    func appName(of window: Window) -> String?
    func title(of window: Window) -> String

    /// Where the mouse pointer is.
    var pointer: CGPoint { get }
    func movePointer(to point: CGPoint)

    /// Small values kept between runs.
    func saved(_ key: String) -> Any?
    func save(_ value: Any, as key: String)

    /// The desks changed: time to redraw the menu bar.
    func changed()
}

var mac: System = Mac()

/// Unlike the Accessibility element, the window number lasts across restarts of Control.
/// A private call, used by most tiling window managers.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ number: UnsafeMutablePointer<CGWindowID>) -> AXError

final class Mac: System {
    /// AppKit measures from the bottom-left of the main monitor, so flip y.
    var screens: [Screen] {
        guard let mainHeight = NSScreen.screens.first?.frame.maxY else { return [] }
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        return NSScreen.screens.map { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            return Screen(id: id, frame: flip(screen.frame), area: flip(screen.visibleFrame))
        }
    }

    var separateSpaces: Bool { NSScreen.screensHaveSeparateSpaces }
    var now: Date { Date() }

    let bootTime: Int = {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &time, &size, nil, 0)
        return time.tv_sec
    }()

    private(set) var silentApps: Set<pid_t> = []

    /// Not minimized, and not the Finder desktop (which has no subrole).
    /// A busy or sleeping app may not answer in time (after the Mac wakes up, say). That is not
    /// the same as an app with no windows: it goes in `silentApps`.
    func windows() -> [Window] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        watchApps(apps)
        silentApps = []
        return apps.flatMap { app -> [Window] in
            let pid = app.processIdentifier
            var list: CFTypeRef?
            let answer = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &list)
            if answer == .cannotComplete { silentApps.insert(pid) }
            return (list as? [Window] ?? []).filter { window in
                var subrole: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .cannotComplete {
                    silentApps.insert(pid)
                }
                return subrole != nil && attribute(window, kAXMinimizedAttribute) as? Bool != true
            }
        }
    }

    func focusedWindow() -> Window? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let window = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
        return (window as! Window)
    }

    /// Bring a window to the front and give it keyboard focus.
    func focus(_ window: Window) {
        // Make it the app's main window first, then bring the app forward:
        // the other way round, the app comes forward with its old window.
        setAttribute(window, kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // Setting the app's Accessibility "frontmost" attribute reports success but does nothing on recent macOS.
        NSRunningApplication(processIdentifier: pid(of: window))?.activate()
    }

    /// Control itself comes to the front. It has no window, so none has the focus.
    func unfocus() { NSRunningApplication.current.activate() }

    func frame(of window: Window) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let value = attribute(window, kAXPositionAttribute) { AXValueGetValue(value as! AXValue, .cgPoint, &origin) }
        if let value = attribute(window, kAXSizeAttribute) { AXValueGetValue(value as! AXValue, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    func setPosition(_ window: Window, _ point: CGPoint) {
        var point = point
        setAttribute(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &point)!)
    }

    /// macOS only lets a window grow as far as the monitor it is on has room. So the size is set
    /// twice: before the move, in case the window is too big for where it goes, and after it, in
    /// case it could not grow enough where it was (coming from a smaller monitor, say).
    func setFrame(_ window: Window, _ rect: CGRect) {
        var size = rect.size
        let value = AXValueCreate(.cgSize, &size)!
        setAttribute(window, kAXSizeAttribute, value)
        setPosition(window, rect.origin)
        setAttribute(window, kAXSizeAttribute, value)
    }

    func shouldFloat(_ window: Window) -> Bool {
        var resizable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable)
        return attribute(window, kAXSubroleAttribute) as? String != kAXStandardWindowSubrole || !resizable.boolValue
    }

    func isFullScreen(_ window: Window) -> Bool { attribute(window, "AXFullScreen") as? Bool == true }

    func number(of window: Window) -> CGWindowID? {
        var number: CGWindowID = 0
        return _AXUIElementGetWindow(window, &number) == .success ? number : nil
    }

    func app(of window: Window) -> String? {
        NSRunningApplication(processIdentifier: pid(of: window))?.bundleIdentifier
    }

    func appName(of window: Window) -> String? {
        NSRunningApplication(processIdentifier: pid(of: window))?.localizedName
    }

    func title(of window: Window) -> String { attribute(window, kAXTitleAttribute) as? String ?? "" }

    /// AppKit measures from the bottom-left of the main monitor, so flip y.
    var pointer: CGPoint {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }

    /// Not while a mouse button is down: that would pull a drag out of the user's hand.
    /// A posted move, unlike `CGWarpMouseCursorPosition`, does not freeze the mouse for a moment
    /// after, and the app under the pointer hears about it (hover effects, focus follows mouse).
    func movePointer(to point: CGPoint) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func saved(_ key: String) -> Any? { UserDefaults.standard.object(forKey: key) }
    func save(_ value: Any, as key: String) { UserDefaults.standard.set(value, forKey: key) }

    func changed() { menuBar.update() }
}

/// Read one attribute (title, windows, position...) of an element.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) {
    AXUIElementSetAttributeValue(element, name as CFString, value)
}

/// The process id of the app that owns a window.
func pid(of window: Window) -> pid_t {
    var pid: pid_t = 0
    AXUIElementGetPid(window, &pid)
    return pid
}
