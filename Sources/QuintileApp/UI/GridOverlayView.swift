import AppKit
import QuintileCore

/// U6: the thin AppKit rendering layer for the grid-select overlay.
///
/// Deliberately dumb: all interaction logic lives in
/// `GridSelectionStateMachine` (QuintileCore, unit-tested); this file only
/// draws whatever it is told and is not unit-tested. Keyboard input never
/// arrives here — the event-tap modal mode (U5) feeds the state machine, and
/// the panel never becomes key, so focus stays on the target app and its
/// retained AX reference remains valid at confirm time.
final class GridOverlayController {

    /// Borderless, non-activating panel that can never steal key/main status.
    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let panel: OverlayPanel
    private let content = GridOverlayContentView()
    private var autoHide: DispatchWorkItem?

    init() {
        panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = content
    }

    // MARK: - API

    /// Shows the interactive overlay on the target display only.
    func show(profile: GridProfile, on display: DisplayDescriptor, selection: CellSpan) {
        cancelAutoHide()
        content.mode = .grid(profile: profile, selection: selection, showHint: true)
        place(on: display)
        panel.orderFrontRegardless()
        announce("Grid selection. \(describe(selection))")
    }

    /// Updates the highlighted selection while the overlay is visible.
    func update(selection: CellSpan) {
        guard case .grid(let profile, _, let showHint) = content.mode else { return }
        content.mode = .grid(profile: profile, selection: selection, showHint: showHint)
        announce(describe(selection))
    }

    /// Brief grid flash without a selection — U8's profile-cycle feedback.
    func flash(profile: GridProfile, on display: DisplayDescriptor, duration: TimeInterval = 0.6) {
        cancelAutoHide()
        content.mode = .grid(profile: profile, selection: nil, showHint: false)
        place(on: display)
        panel.orderFrontRegardless()
        announce("Grid \(profile.name): \(profile.cols) by \(profile.rows)")
        scheduleHide(after: duration)
    }

    /// Brief "No window to place" HUD (leader pressed with no focused window).
    func showNoWindowHUD(on display: DisplayDescriptor, duration: TimeInterval = 1.2) {
        cancelAutoHide()
        content.mode = .noWindowHUD
        place(on: display)
        panel.orderFrontRegardless()
        announce("No window to place")
        scheduleHide(after: duration)
    }

    /// Dismisses the overlay, optionally announcing the outcome for VoiceOver
    /// (e.g. "Placed window", "Cancelled").
    func hide(announcing message: String? = nil) {
        cancelAutoHide()
        panel.orderOut(nil)
        content.mode = .empty
        if let message { announce(message) }
    }

    // MARK: - Placement

    private func place(on display: DisplayDescriptor) {
        // `usableBounds` is in the canonical Quartz top-left-origin global
        // space (see AXBackend). NSPanel.setFrame wants Cocoa bottom-left-
        // origin global coordinates. The two spaces share x and flip y about
        // the primary display's height (the primary screen has Quartz origin
        // (0,0) top-left and Cocoa origin (0,0) bottom-left):
        //   cocoaY = primaryHeight - quartzMaxY
        let quartz = display.usableBounds
        let primaryHeight = NSScreen.screens.first?.frame.height ?? quartz.maxY
        let cocoa = NSRect(x: quartz.minX,
                           y: primaryHeight - quartz.maxY,
                           width: quartz.width,
                           height: quartz.height)
        panel.setFrame(cocoa, display: true)
    }

    // MARK: - Helpers

    private func scheduleHide(after duration: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        autoHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func cancelAutoHide() {
        autoHide?.cancel()
        autoHide = nil
    }

    private func describe(_ span: CellSpan) -> String {
        span.colSpan == 1 && span.rowSpan == 1
            ? "Cell column \(span.startCol + 1), row \(span.startRow + 1)"
            : "Span \(span.colSpan) by \(span.rowSpan) from column \(span.startCol + 1), row \(span.startRow + 1)"
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

/// Draws the backdrop, grid lines, per-cell key labels, selection highlight,
/// and hint bar — or the small "No window to place" HUD.
private final class GridOverlayContentView: NSView {

    enum Mode {
        case empty
        case grid(profile: GridProfile, selection: CellSpan?, showHint: Bool)
        case noWindowHUD
    }

    var mode: Mode = .empty {
        didSet { needsDisplay = true }
    }

    /// Flipped so y grows downward, matching the grid's top-left-origin
    /// row/col coordinates — row 0 draws at the top of the display.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        switch mode {
        case .empty:
            break
        case .grid(let profile, let selection, let showHint):
            drawBackdrop()
            drawGrid(profile: profile, selection: selection)
            if showHint { drawHintBar() }
        case .noWindowHUD:
            drawHUD(text: "No window to place")
        }
    }

    // MARK: - Grid mode

    private func drawBackdrop() {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
    }

    private func drawGrid(profile: GridProfile, selection: CellSpan?) {
        let cols = CGFloat(profile.cols)
        let rows = CGFloat(profile.rows)
        let cellW = bounds.width / cols
        let cellH = bounds.height / rows

        // Selection highlight under the lines.
        if let span = selection {
            let rect = NSRect(x: CGFloat(span.startCol) * cellW,
                              y: CGFloat(span.startRow) * cellH,
                              width: CGFloat(span.colSpan) * cellW,
                              height: CGFloat(span.rowSpan) * cellH)
                .insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 3
            path.stroke()
        }

        // Grid lines.
        NSColor.white.withAlphaComponent(0.3).setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for c in 1..<profile.cols {
            lines.move(to: NSPoint(x: CGFloat(c) * cellW, y: 0))
            lines.line(to: NSPoint(x: CGFloat(c) * cellW, y: bounds.height))
        }
        for r in 1..<profile.rows {
            lines.move(to: NSPoint(x: 0, y: CGFloat(r) * cellH))
            lines.line(to: NSPoint(x: bounds.width, y: CGFloat(r) * cellH))
        }
        lines.stroke()

        // Per-cell key labels. Empty layout (> 10×4 grid) means arrow-only
        // fallback: no labels drawn.
        let layout = GridSelectionStateMachine.cellKeyLayout(for: profile)
        guard !layout.isEmpty else { return }
        let fontSize = min(cellH * 0.3, 44)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        for (row, labels) in layout.enumerated() {
            for (col, key) in labels.enumerated() {
                let selected = selection?.contains(col: col, row: row) ?? false
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white.withAlphaComponent(selected ? 0.95 : 0.55),
                ]
                let text = String(key) as NSString
                let size = text.size(withAttributes: attrs)
                let center = NSPoint(x: (CGFloat(col) + 0.5) * cellW - size.width / 2,
                                     y: (CGFloat(row) + 0.5) * cellH - size.height / 2)
                text.draw(at: center, withAttributes: attrs)
            }
        }
    }

    private func drawHintBar() {
        let hint = "type two cell keys · arrows move · ⇧arrows extend · ⏎ confirm · esc cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let text = hint as NSString
        let size = text.size(withAttributes: attrs)
        let barHeight = size.height + 16
        let barWidth = size.width + 40
        // Flipped coordinates: maxY is the bottom edge of the display.
        let bar = NSRect(x: bounds.midX - barWidth / 2,
                         y: bounds.maxY - barHeight - 16,
                         width: barWidth,
                         height: barHeight)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        text.draw(at: NSPoint(x: bar.midX - size.width / 2, y: bar.midY - size.height / 2),
                  withAttributes: attrs)
    }

    // MARK: - HUD mode

    private func drawHUD(text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attrs)
        let box = NSRect(x: bounds.midX - (size.width + 60) / 2,
                         y: bounds.midY - (size.height + 36) / 2,
                         width: size.width + 60,
                         height: size.height + 36)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
        string.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
                    withAttributes: attrs)
    }
}
