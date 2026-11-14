import AppKit

// Small wrappers around the Accessibility API, which moves and reads other apps' windows.
// Coordinates start at the top-left of the main monitor, y going down.

typealias Window = AXUIElement

/// Read one attribute (title, windows, position...) of an element.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) {
    AXUIElementSetAttributeValue(element, name as CFString, value)
}

/// An app's windows we care about: not minimized, and not the Finder desktop (which has no subrole).
func windows(of pid: pid_t) -> [Window] {
    let all = attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [Window] ?? []
    return all.filter { window in
        attribute(window, kAXSubroleAttribute) != nil && attribute(window, kAXMinimizedAttribute) as? Bool != true
    }
}

/// Dialogs, popups and fixed-size windows float. Normal windows tile.
func shouldFloat(_ window: Window) -> Bool {
    var resizable: DarwinBoolean = false
    AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable)
    return attribute(window, kAXSubroleAttribute) as? String != kAXStandardWindowSubrole || !resizable.boolValue
}

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

func setFrame(_ window: Window, _ rect: CGRect) {
    var size = rect.size
    setPosition(window, rect.origin)
    setAttribute(window, kAXSizeAttribute, AXValueCreate(.cgSize, &size)!)
}

/// The window that has keyboard focus.
func focusedWindow() -> Window? {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
          let window = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
    return (window as! Window)
}

/// The process id of the app that owns a window.
func pid(of window: Window) -> pid_t {
    var pid: pid_t = 0
    AXUIElementGetPid(window, &pid)
    return pid
}

/// Bring a window to the front and give it keyboard focus.
func focus(_ window: Window) {
    // Make it the app's main window first, then bring the app forward:
    // the other way round, the app comes forward with its old window.
    setAttribute(window, kAXMainAttribute, kCFBooleanTrue)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    setAttribute(AXUIElementCreateApplication(pid(of: window)), kAXFrontmostAttribute, kCFBooleanTrue)
}

/// A monitor's usable area (no menu bar, no Dock), in Accessibility coordinates.
/// AppKit measures from the bottom-left of the main monitor, so flip y.
func usableArea(of screen: NSScreen) -> CGRect {
    let visible = screen.visibleFrame
    let mainHeight = NSScreen.screens[0].frame.maxY
    return CGRect(x: visible.minX, y: mainHeight - visible.maxY, width: visible.width, height: visible.height)
}

func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
}
