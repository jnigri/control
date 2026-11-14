import AppKit

// The menu bar item: the current desk key in a rounded square, in system colors.
// Click it for a panel listing the desks, in the Asimov colors. Click a desk to show it.

/// A color with one value for light mode and one for dark mode. macOS picks the right one
/// each time it draws, so the panel follows the system theme on its own.
func color(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                       blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Asimov: gun-white and hazard orange in light mode; black stock and gun-white text in dark mode.
enum Asimov {
    static let background = color(light: 0xeef0f1, dark: 0x161616)
    static let raised = color(light: 0xccd1d4, dark: 0x2c2f31)
    static let text = color(light: 0x161616, dark: 0xeef0f1)
    static let muted = color(light: 0x6c7176, dark: 0x8a9095)
    static let accent = color(light: 0xe85400, dark: 0xec6a2c)
}

final class MenuBar: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// A borderless floating window that drops down under the menu bar item.
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    /// Watches clicks in other apps, to close the panel.
    var clickOutside: Any?

    override init() {
        super.init()
        item.button!.target = self
        item.button!.action = #selector(toggle)
        panel.isOpaque = false
        panel.backgroundColor = .clear   // the Card view draws the background
        panel.hasShadow = true
        panel.level = .popUpMenu
    }

    /// Show the current desk key. If the panel is open, redraw it too.
    func update() {
        item.button?.image = keyCap(current)
        if panel.isVisible { render() }
    }

    @objc func toggle() { panel.isVisible ? close() : open() }

    func open() {
        render()
        panel.orderFrontRegardless()
        clickOutside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        panel.orderOut(nil)
        if let clickOutside { NSEvent.removeMonitor(clickOutside) }
        clickOutside = nil
    }

    /// Build the panel: a title, one row per desk in use, and Quit.
    func render() {
        var rows: [NSView] = [Row([label("DESKS", size: 10, color: Asimov.muted, mono: true)])]
        for key in deskKeys where key == current || !desks[key]!.windows.isEmpty {
            let isCurrent = key == current
            let cap = NSImageView(image: keyCap(key, size: 22, fill: isCurrent ? Asimov.accent : Asimov.raised,
                                                ink: isCurrent ? .white : Asimov.text))
            rows.append(Row([cap] + appIcons(on: desks[key]!)) { [unowned self] in
                close()
                show(key)
            })
        }
        let line = NSBox()
        line.boxType = .custom
        line.borderWidth = 0
        line.fillColor = Asimov.raised
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        rows.append(line)
        rows.append(Row([label("Quit Control", size: 13, color: Asimov.text)]) { NSApp.terminate(nil) })

        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.spacing = 2
        column.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        column.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        for row in rows { row.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -12).isActive = true }

        let card = Card()
        card.addSubview(column)
        pin(column, to: card)
        panel.contentView = card
        panel.setContentSize(card.fittingSize)

        // Drop down from the menu bar item, but stay on screen.
        let button = item.button!.window!.frame
        let screenRight = (item.button!.window!.screen ?? NSScreen.screens[0]).visibleFrame.maxX
        let x = min(button.minX, screenRight - panel.frame.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: button.minY - 4))
    }
}

/// The panel's background: a rounded card with a thin border.
final class Card: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        Asimov.background.setFill()
        shape.fill()
        Asimov.raised.setStroke()
        shape.stroke()
    }
}

/// One line of the panel. With an action, it highlights under the mouse and runs the action on click.
final class Row: NSView {
    let action: (() -> Void)?
    var hovered = false { didSet { needsDisplay = true } }

    init(_ views: [NSView], action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)
        let line = NSStackView(views: views)
        line.spacing = 6
        line.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        addSubview(line)
        pin(line, to: self)
        if action != nil {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard hovered else { return }
        Asimov.raised.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {}   // needed, or mouseUp never comes
    override func mouseUp(with event: NSEvent) { action?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Make `view` fill `container` exactly.
func pin(_ view: NSView, to container: NSView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        view.topAnchor.constraint(equalTo: container.topAnchor),
        view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
}

func label(_ text: String, size: CGFloat, color: NSColor, mono: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = mono ? .monospacedSystemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
    field.textColor = color
    return field
}

/// A rounded square with the key on it, like a keyboard key.
/// Without colors, it is a template image with the key cut out: macOS colors it to match the menu bar.
func keyCap(_ key: String, size: CGFloat = 17, fill: NSColor? = nil, ink: NSColor? = nil) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        (fill ?? .black).setFill()
        NSBezierPath(roundedRect: rect, xRadius: size / 4, yRadius: size / 4).fill()
        let font = NSFont.systemFont(ofSize: size * 0.7, weight: .bold)
        let text = NSAttributedString(string: key, attributes: [.font: font, .foregroundColor: ink ?? .black])
        let textSize = text.size()
        // No ink color: draw the text as a hole, so the square is transparent where the key is.
        if ink == nil { NSGraphicsContext.current!.cgContext.setBlendMode(.destinationOut) }
        text.draw(at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2))
        return true
    }
    image.isTemplate = fill == nil
    return image
}

/// One icon per app on the desk, in order.
func appIcons(on desk: Desk) -> [NSView] {
    var seen: Set<pid_t> = []
    var icons: [NSView] = []
    for window in desk.windows {
        let app = pid(of: window)
        guard seen.insert(app).inserted, let icon = NSRunningApplication(processIdentifier: app)?.icon else { continue }
        let view = NSImageView(image: icon)
        view.widthAnchor.constraint(equalToConstant: 20).isActive = true
        view.heightAnchor.constraint(equalToConstant: 20).isActive = true
        icons.append(view)
    }
    return icons.isEmpty ? [label("empty", size: 12, color: Asimov.muted)] : icons
}
