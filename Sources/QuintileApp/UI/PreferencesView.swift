import AppKit
import QuintileCore

/// U8: programmatic AppKit preferences window, per the plan's IA:
/// - left sidebar: connected displays plus a grayed "Disconnected" section
///   for persisted identities not currently attached (orphaned configs are
///   editable too — they apply again the moment the display returns);
/// - right side: standard/secondary/tertiary tabs, each a rows×cols stepper
///   editor (1–10 columns, 1–4 rows — the cell-key labeling limit) with a
///   live "N×M" preview. Every edit persists immediately via
///   `GridProfileStore.updateProfile` (persist-on-change, no Apply button);
/// - a Shortcuts tab listing every current binding — the in-app shortcut
///   reference (plan requirement for a keyboard-only tool).
final class PreferencesWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    enum Tab: Int {
        case standard = 0, secondary, tertiary, shortcuts
    }

    // MARK: - Model

    private struct DisplayEntry {
        let identity: DisplayIdentity
        let name: String
        let connected: Bool
    }

    private enum Row {
        case header(String)
        case display(DisplayEntry)
    }

    private let store: GridProfileStore
    private let connectedDisplays: () -> [DisplayDescriptor]
    private let shortcutRowsProvider: () -> [(action: String, chord: String)]

    private var rows: [Row] = []
    private var shortcutRows: [(action: String, chord: String)] = []

    // MARK: - Views

    private var window: NSWindow?
    private let sidebar = NSTableView()
    private let shortcutsTable = NSTableView()
    private let tabView = NSTabView()
    private var editors: [ProfileSlot: ProfileEditorView] = [:]

    init(store: GridProfileStore,
         connectedDisplays: @escaping () -> [DisplayDescriptor],
         shortcutRows: @escaping () -> [(action: String, chord: String)]) {
        self.store = store
        self.connectedDisplays = connectedDisplays
        self.shortcutRowsProvider = shortcutRows
        super.init()
    }

    // MARK: - API

    func show(tab: Tab) {
        if window == nil { buildWindow() }
        reload()
        tabView.selectTabViewItem(at: tab.rawValue)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Data

    private func reload() {
        let connected = connectedDisplays()
        var built: [Row] = []

        if !connected.isEmpty {
            built.append(.header("Connected"))
            for display in connected {
                let name = display.info.localizedName.isEmpty
                    ? display.identity.key : display.info.localizedName
                built.append(.display(DisplayEntry(identity: display.identity,
                                                   name: name,
                                                   connected: true)))
            }
        }

        let connectedKeys = Set(connected.map { $0.identity.key })
        let orphans = store.knownIdentityKeys
            .filter { !connectedKeys.contains($0) }
            .sorted()
        if !orphans.isEmpty {
            built.append(.header("Disconnected"))
            for key in orphans {
                built.append(.display(DisplayEntry(identity: DisplayIdentity(key: key),
                                                   name: key,
                                                   connected: false)))
            }
        }

        rows = built
        sidebar.reloadData()
        if selectedEntry == nil, let first = firstSelectableRow {
            sidebar.selectRowIndexes(IndexSet(integer: first), byExtendingSelection: false)
        }

        shortcutRows = shortcutRowsProvider()
        shortcutsTable.reloadData()
        refreshEditors()
    }

    private var firstSelectableRow: Int? {
        rows.firstIndex { if case .display = $0 { return true } else { return false } }
    }

    private var selectedEntry: DisplayEntry? {
        let index = sidebar.selectedRow
        guard index >= 0, index < rows.count, case .display(let entry) = rows[index] else {
            return nil
        }
        return entry
    }

    private func refreshEditors() {
        guard let entry = selectedEntry else {
            for editor in editors.values { editor.setEnabled(false) }
            return
        }
        let config = store.config(for: entry.identity)
        for (slot, editor) in editors {
            let profile = config[slot]
            editor.set(rows: profile.rows, cols: profile.cols)
            editor.setEnabled(true)
        }
    }

    private func profileEdited(slot: ProfileSlot, rows: Int, cols: Int) {
        guard let entry = selectedEntry else { return }
        var profile = store.config(for: entry.identity)[slot]
        profile.rows = rows
        profile.cols = cols
        store.updateProfile(profile, slot: slot, for: entry.identity) // persist-on-change
    }

    // MARK: - Window construction

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Quintile Preferences"
        window.isReleasedWhenClosed = false

        // Sidebar
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.headerView = nil
        sidebar.rowHeight = 22
        sidebar.allowsEmptySelection = true
        let sidebarColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("display"))
        sidebarColumn.width = 190
        sidebar.addTableColumn(sidebarColumn)
        let sidebarScroll = NSScrollView()
        sidebarScroll.documentView = sidebar
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.borderType = .bezelBorder
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.widthAnchor.constraint(equalToConstant: 200).isActive = true

        // Profile tabs
        for slot in ProfileSlot.allCases {
            let editor = ProfileEditorView()
            editor.onChange = { [weak self] rows, cols in
                self?.profileEdited(slot: slot, rows: rows, cols: cols)
            }
            editors[slot] = editor
            let item = NSTabViewItem(identifier: slot.rawValue)
            item.label = slot.rawValue.capitalized
            item.view = editor
            tabView.addTabViewItem(item)
        }

        // Shortcuts reference tab
        shortcutsTable.dataSource = self
        shortcutsTable.delegate = self
        shortcutsTable.rowHeight = 20
        shortcutsTable.allowsEmptySelection = true
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "Action"
        actionColumn.width = 260
        let chordColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("chord"))
        chordColumn.title = "Shortcut"
        chordColumn.width = 120
        shortcutsTable.addTableColumn(actionColumn)
        shortcutsTable.addTableColumn(chordColumn)
        let shortcutsScroll = NSScrollView()
        shortcutsScroll.documentView = shortcutsTable
        shortcutsScroll.hasVerticalScroller = true
        shortcutsScroll.borderType = .bezelBorder
        let shortcutsItem = NSTabViewItem(identifier: "shortcuts")
        shortcutsItem.label = "Shortcuts"
        shortcutsItem.view = shortcutsScroll
        tabView.addTabViewItem(shortcutsItem)

        tabView.translatesAutoresizingMaskIntoConstraints = false

        // Layout: sidebar | tabs
        let content = NSView()
        content.addSubview(sidebarScroll)
        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            sidebarScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            sidebarScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            sidebarScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            tabView.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        window.contentView = content
        window.center()
        self.window = window
    }

    // MARK: - NSTableViewDataSource / Delegate (both tables)

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === sidebar ? rows.count : shortcutRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        if tableView === sidebar {
            guard row < rows.count else { return nil }
            switch rows[row] {
            case .header(let title):
                let label = NSTextField(labelWithString: title.uppercased())
                label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
                label.textColor = .secondaryLabelColor
                return label
            case .display(let entry):
                let label = NSTextField(labelWithString: entry.name)
                label.font = NSFont.systemFont(ofSize: 12)
                label.lineBreakMode = .byTruncatingMiddle
                label.textColor = entry.connected ? .labelColor : .disabledControlTextColor
                label.toolTip = entry.connected
                    ? entry.identity.key
                    : "\(entry.identity.key) (not currently connected)"
                return label
            }
        } else {
            guard row < shortcutRows.count else { return nil }
            let entry = shortcutRows[row]
            let isAction = tableColumn?.identifier.rawValue == "action"
            let label = NSTextField(labelWithString: isAction ? entry.action : entry.chord)
            label.font = isAction
                ? NSFont.systemFont(ofSize: 12)
                : NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            return label
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard tableView === sidebar else { return false } // shortcuts table: read-only list
        guard row < rows.count, case .display = rows[row] else { return false }
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === sidebar else { return }
        refreshEditors()
    }
}

// MARK: - Per-slot rows×cols editor

/// One profile tab's content: rows/cols steppers with a live "N×M" preview.
/// Limits match the grid-select cell-key layout (10 columns × 4 rows —
/// beyond that the overlay would have no key labels).
private final class ProfileEditorView: NSView {

    var onChange: ((_ rows: Int, _ cols: Int) -> Void)?

    private let colsStepper = NSStepper()
    private let rowsStepper = NSStepper()
    private let colsValue = NSTextField(labelWithString: "5")
    private let rowsValue = NSTextField(labelWithString: "2")
    private let preview = NSTextField(labelWithString: "5×2")

    init() {
        super.init(frame: .zero)

        colsStepper.minValue = 1
        colsStepper.maxValue = 10
        colsStepper.increment = 1
        colsStepper.valueWraps = false
        colsStepper.target = self
        colsStepper.action = #selector(stepped)

        rowsStepper.minValue = 1
        rowsStepper.maxValue = 4
        rowsStepper.increment = 1
        rowsStepper.valueWraps = false
        rowsStepper.target = self
        rowsStepper.action = #selector(stepped)

        preview.font = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium)

        let colsRow = NSStackView(views: [
            NSTextField(labelWithString: "Columns:"), colsValue, colsStepper,
        ])
        colsRow.orientation = .horizontal
        colsRow.spacing = 8

        let rowsRow = NSStackView(views: [
            NSTextField(labelWithString: "Rows:"), rowsValue, rowsStepper,
        ])
        rowsRow.orientation = .horizontal
        rowsRow.spacing = 8

        let limitLabel = NSTextField(
            wrappingLabelWithString: "Limits: 1–10 columns, 1–4 rows — the range the grid-select cell-key labels cover.")
        limitLabel.font = NSFont.systemFont(ofSize: 11)
        limitLabel.textColor = .secondaryLabelColor
        limitLabel.preferredMaxLayoutWidth = 320

        let stack = NSStackView(views: [preview, colsRow, rowsRow, limitLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func set(rows: Int, cols: Int) {
        rowsStepper.integerValue = rows
        colsStepper.integerValue = cols
        syncLabels()
    }

    func setEnabled(_ enabled: Bool) {
        rowsStepper.isEnabled = enabled
        colsStepper.isEnabled = enabled
    }

    @objc private func stepped() {
        syncLabels()
        onChange?(rowsStepper.integerValue, colsStepper.integerValue)
    }

    private func syncLabels() {
        colsValue.stringValue = "\(colsStepper.integerValue)"
        rowsValue.stringValue = "\(rowsStepper.integerValue)"
        preview.stringValue = "\(colsStepper.integerValue)×\(rowsStepper.integerValue)"
    }
}
