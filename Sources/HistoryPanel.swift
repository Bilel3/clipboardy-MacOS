import AppKit

enum PanelVisualStyle: String {
    case blurry
    case liquidGlass
}

// MARK: - Search field that forwards arrow / enter / escape to the panel

final class HistorySearchField: NSTextField {
    var onArrowDown: (() -> Void)?
    var onArrowUp:   (() -> Void)?
    var onEnter:     (() -> Void)?
    var onEscape:    (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: onArrowDown?()
        case 126: onArrowUp?()
        case 36, 76: onEnter?()   // Return or Enter (numpad)
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

// MARK: - Row view with rounded selection highlight

final class RoundedRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 6, dy: 2)
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
    }

    // Remove the default focus ring
    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

// MARK: - History Panel

final class HistoryPanel: NSPanel {

    private let store: ClipboardHistoryStore
    private let onPaste: (ClipboardItem) -> Void

    private var filteredItems: [ClipboardItem] = []
    private var globalMonitor: Any?
    private var visualStyle: PanelVisualStyle

    private var effectView: NSVisualEffectView!
    private var styleOverlayView: NSView!

    private var searchField: HistorySearchField!
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!

    // MARK: Init

    init(
        store: ClipboardHistoryStore,
        visualStyle: PanelVisualStyle,
        onPaste: @escaping (ClipboardItem) -> Void
    ) {
        self.store = store
        self.visualStyle = visualStyle
        self.onPaste = onPaste
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        buildUI()

        store.onChange = { [weak self] in
            DispatchQueue.main.async { self?.reload() }
        }
    }

    override var canBecomeKey: Bool { true }

    func setVisualStyle(_ style: PanelVisualStyle) {
        visualStyle = style
        applyVisualStyle()
    }

    // MARK: Panel configuration

    private func configurePanel() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = true
        minSize = NSSize(width: 300, height: 200)
    }

    // MARK: UI Construction

    private func buildUI() {
        effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        contentView = effectView

        // Optional style layer used by the liquid glass mode.
        styleOverlayView = NSView()
        styleOverlayView.translatesAutoresizingMaskIntoConstraints = false
        styleOverlayView.wantsLayer = true
        styleOverlayView.layer?.cornerRadius = 14
        styleOverlayView.layer?.masksToBounds = true
        styleOverlayView.layer?.zPosition = 0
        effectView.addSubview(styleOverlayView)

        // ── Search bar ──────────────────────────────────────────────────
        let searchIcon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass",
                                                     accessibilityDescription: nil)!)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        searchField = HistorySearchField()
        searchField.placeholderString = "Search clipboard history…"
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.font = .systemFont(ofSize: 15)
        searchField.focusRingType = .none
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self

        searchField.onArrowDown = { [weak self] in self?.moveSelection(by: +1) }
        searchField.onArrowUp   = { [weak self] in self?.moveSelection(by: -1) }
        searchField.onEnter     = { [weak self] in self?.pasteSelected() }
        searchField.onEscape    = { [weak self] in self?.dismiss() }

        // ── Separator ────────────────────────────────────────────────────
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // ── Table view ───────────────────────────────────────────────────
        tableView = NSTableView()
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.rowHeight = 48
        tableView.headerView = nil
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(pasteSelected)
        tableView.focusRingType = .none
        let col = NSTableColumn(identifier: .init("item"))
        col.isEditable = false
        tableView.addTableColumn(col)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // ── Empty state label ─────────────────────────────────────────────
        emptyLabel = NSTextField(labelWithString: "No clipboard history yet.\nCopy something to get started.")
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        // ── Footer ────────────────────────────────────────────────────────
        let footer = NSTextField(labelWithString: "↑↓ Navigate   ↵ Paste   ⎋ Dismiss   ⌃⌘V Toggle")
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center
        footer.translatesAutoresizingMaskIntoConstraints = false

        // ── Layout ────────────────────────────────────────────────────────
        [searchIcon, searchField, separator, scrollView, emptyLabel, footer].forEach {
            effectView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            styleOverlayView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            styleOverlayView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            styleOverlayView.topAnchor.constraint(equalTo: effectView.topAnchor),
            styleOverlayView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            searchIcon.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 14),
            searchIcon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),

            searchField.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -14),
            searchField.heightAnchor.constraint(equalToConstant: 24),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            separator.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            footer.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            footer.heightAnchor.constraint(equalToConstant: 14),
        ])

        applyVisualStyle()
    }

    private func applyVisualStyle() {
        effectView.layer?.borderWidth = 1

        switch visualStyle {
        case .blurry:
            effectView.material = .hudWindow
            effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            // Keep blur look, but add a soft translucent wash.
            styleOverlayView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            styleOverlayView.layer?.sublayers = []

        case .liquidGlass:
            effectView.material = .underWindowBackground
            effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

            let gradient = CAGradientLayer()
            gradient.frame = styleOverlayView.bounds
            gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            gradient.colors = [
                NSColor.white.withAlphaComponent(0.22).cgColor,
                NSColor.white.withAlphaComponent(0.08).cgColor,
                NSColor.clear.cgColor
            ]
            gradient.locations = [0.0, 0.42, 1.0]
            gradient.startPoint = CGPoint(x: 0.0, y: 1.0)
            gradient.endPoint = CGPoint(x: 1.0, y: 0.0)

            styleOverlayView.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.08).cgColor
            styleOverlayView.layer?.sublayers = [gradient]
        }
    }

    // MARK: Show / Hide

    func showNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = frame.width, h = frame.height
        var x = mouse.x - w / 2
        var y = mouse.y - h / 2
        x = max(screen.minX + 8, min(x, screen.maxX - w - 8))
        y = max(screen.minY + 8, min(y, screen.maxY - h - 8))
        setFrameOrigin(NSPoint(x: x, y: y))

        searchField.stringValue = ""
        reload()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)

        // Dismiss on any click outside this panel
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        close()
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    // MARK: Data

    private func reload() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        filteredItems = query.isEmpty
            ? store.items
            : store.items.filter { $0.displayText.localizedCaseInsensitiveContains(query) }

        tableView.reloadData()
        emptyLabel.isHidden = !filteredItems.isEmpty
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: Navigation

    private func moveSelection(by delta: Int) {
        guard !filteredItems.isEmpty else { return }
        let next = max(0, min(tableView.selectedRow + delta, filteredItems.count - 1))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func pasteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredItems.count else { return }
        onPaste(filteredItems[row])
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension HistoryPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { filteredItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filteredItems[row]

        let cell = NSTableCellView()

        // Icon
        let iconName = item.image != nil ? "photo" : "doc.on.clipboard"
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        // Primary label
        let label = NSTextField(labelWithString: item.previewText)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = label

        // Time badge
        let time = NSTextField(labelWithString: item.date.relativeString)
        time.font = .systemFont(ofSize: 10)
        time.textColor = .tertiaryLabelColor
        time.alignment = .right
        time.translatesAutoresizingMaskIntoConstraints = false

        [icon, label, time].forEach { cell.addSubview($0) }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: -8),

            time.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
            time.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            time.widthAnchor.constraint(equalToConstant: 60),
        ])

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RoundedRowView()
    }

    // Double-click is bound via tableView.doubleAction above
}

// MARK: - NSTextFieldDelegate (live search)

extension HistoryPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        reload()
    }
}
