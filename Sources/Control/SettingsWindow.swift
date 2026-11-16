import AppKit

// The settings window, from the gear in the menu bar panel, in the same colors as the panel.
// Every change goes straight to `~/.config/control/config.json`, and "Sync" reads that file
// again: the file wins.

final class SettingsWindow: NSObject {
    private(set) var window: NSWindow?
    private let pointerSwitch = NSSwitch()
    private let logSwitch = NSSwitch()
    private let folder = label("", size: 12, color: Asimov.text, mono: true)
    private let problem = NSTextField(wrappingLabelWithString: "")

    /// Open the window with what the file says now.
    func show() {
        syncConfig()
        if window == nil { build() }
        update()
        // Control has no Dock icon: it comes to the front only when asked.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func build() {
        let width: CGFloat = 440
        let margin: CGFloat = 20

        pointerSwitch.target = self
        pointerSwitch.action = #selector(togglePointer)
        pointerSwitch.controlSize = .small
        logSwitch.target = self
        logSwitch.action = #selector(toggleLog)
        logSwitch.controlSize = .small
        folder.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        folder.lineBreakMode = .byTruncatingMiddle
        folder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        problem.font = .systemFont(ofSize: 12)
        problem.textColor = Asimov.accent
        problem.isSelectable = false

        func title(_ text: String) -> NSTextField { label(text, size: 10, color: Asimov.muted, mono: true) }
        func name(_ text: String) -> NSTextField { label(text, size: 13, color: Asimov.text) }
        func note(_ text: String) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: 11.5)
            field.textColor = Asimov.muted
            field.isSelectable = false
            return field
        }
        func space() -> NSView {
            let view = NSView()
            view.setContentHuggingPriority(.init(1), for: .horizontal)
            return view
        }
        /// One line of a group: things on the left, things on the right.
        func line(_ views: [NSView]) -> NSStackView {
            let line = NSStackView(views: views)
            line.spacing = 8
            line.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
            line.heightAnchor.constraint(equalToConstant: 40).isActive = true
            return line
        }

        let path = label((configPath as NSString).abbreviatingWithTildeInPath, size: 12, color: Asimov.text, mono: true)
        path.font = folder.font
        path.lineBreakMode = .byTruncatingMiddle
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pointerSwitchLine = line([name("Move the pointer to the focused window"), space(), pointerSwitch])
        pointerSwitchLine.edgeInsets.right = 12
        let pointerNote = note("Switch windows with a key, Command + Tab or the Dock, and the pointer goes to the "
                               + "middle of the window. Show an empty desk and it goes to the middle of the desk. "
                               + "A click leaves it where it is.")
        let logSwitchLine = line([name("Write a debug log"), space(), logSwitch])
        logSwitchLine.edgeInsets.right = 12
        let logNote = note("Helps find bugs: what macOS reports, what Control does, where each window is. Apps are named "
                           + "by bundle identifier (com.apple.Safari), never by window title. Stays on this Mac until you export it.")
        let exportButton = TextButton("Export log…", accent: true) { [unowned self] in export() }
        let titles = [title("POINTER"), title("DEBUG LOG"), title("SETTINGS FILE")]
        let rows: [NSView] = [
            titles[0],
            Group([pointerSwitchLine]),
            pointerNote,
            titles[1],
            Group([
                logSwitchLine,
                line([name("Folder"), folder, space(),
                      TextButton("Choose…") { [unowned self] in chooseFolder() },
                      TextButton("Show") { [unowned self] in showFolder() }]),
            ]),
            logNote,
            exportButton,
            titles[2],
            Group([
                line([path, space(),
                      TextButton("Show") { [unowned self] in showConfig() },
                      TextButton("Sync") { [unowned self] in sync() }]),
            ]),
            note("Changed the file by hand? Sync to use what it says. The file always wins."),
            problem,
        ]
        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 44, left: margin, bottom: margin, right: margin)
        column.widthAnchor.constraint(equalToConstant: width).isActive = true
        for view in rows where view is Group || view is NSTextField {
            view.widthAnchor.constraint(equalToConstant: width - 2 * margin).isActive = true
        }
        // More room above each title, and around the button that stands alone.
        for title in titles { column.setCustomSpacing(6, after: title) }
        column.setCustomSpacing(26, after: pointerNote)
        column.setCustomSpacing(14, after: logNote)
        column.setCustomSpacing(26, after: exportButton)

        // The title bar is part of the card: one surface, like the menu bar panel.
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Control Settings"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Asimov.background
        window.isReleasedWhenClosed = false
        window.contentView = column
        window.setContentSize(column.fittingSize)
        window.center()
        self.window = window
    }

    /// Show the settings in use.
    func update() {
        pointerSwitch.state = config.centerPointer ? .on : .off
        logSwitch.state = config.log ? .on : .off
        folder.stringValue = config.logFolder
        folder.toolTip = config.logFolder
        problem.stringValue = configError ?? ""
        problem.isHidden = configError == nil
        if let window, let content = window.contentView { window.setContentSize(content.fittingSize) }
    }

    @objc private func togglePointer() {
        let on = pointerSwitch.state == .on
        changeConfig { $0.centerPointer = on }
        update()
    }

    @objc private func toggleLog() {
        let on = logSwitch.state == .on
        changeConfig { $0.log = on }
        update()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "The folder for Control's debug log"
        panel.directoryURL = existing(config.logFolderURL)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // With `~` for the home folder, so the file does not hold the user's name.
        changeConfig { $0.logFolder = (url.path as NSString).abbreviatingWithTildeInPath }
        update()
    }

    private func showFolder() {
        try? FileManager.default.createDirectory(at: config.logFolderURL, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(config.logFolderURL)
    }

    private func showConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
    }

    private func sync() {
        syncConfig()
        update()
    }

    /// Ask where the zip goes, make it, and show it in Finder, ready to send.
    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "A zip of the debug log goes in this folder. It holds window positions and the bundle "
            + "identifiers of the apps you use, and no window titles. You can open it and read it before sending it."
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try exportLog(into: url)])
        } catch {
            let alert = NSAlert()
            alert.messageText = "The log could not be exported"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// The folder, or the closest one above it that is there.
    private func existing(_ url: URL) -> URL {
        var url = url
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" { url.deleteLastPathComponent() }
        return url
    }
}

/// A few lines that belong together, on a slightly raised card with a thin line between them.
final class Group: NSView {
    private let lines: [NSView]

    init(_ lines: [NSView]) {
        self.lines = lines
        super.init(frame: .zero)
        let column = NSStackView(views: lines)
        column.orientation = .vertical
        column.spacing = 1
        addSubview(column)
        pin(column, to: self)
        for line in lines { line.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Asimov.raised.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        Asimov.raised.setFill()
        for line in lines.dropLast() {
            NSRect(x: 12, y: convert(line.bounds, from: line).maxY, width: bounds.width - 12, height: 1).fill()
        }
    }
}

/// A flat button with a word on it. The one that matters most takes the accent color.
final class TextButton: NSView {
    let action: () -> Void
    let accent: Bool
    var hovered = false { didSet { needsDisplay = true } }
    var pressed = false { didSet { needsDisplay = true } }

    init(_ title: String, accent: Bool = false, action: @escaping () -> Void) {
        self.action = action
        self.accent = accent
        super.init(frame: .zero)
        let text = label(title, size: 12, color: accent ? .white : Asimov.text)
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let fill = accent ? Asimov.accent : Asimov.raised
        fill.withAlphaComponent(pressed ? 0.6 : hovered ? 0.85 : 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false; pressed = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { action() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { action(); return true }
}
