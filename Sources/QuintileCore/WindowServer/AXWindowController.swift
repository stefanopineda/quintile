import CoreGraphics
import Foundation

/// Façade over the AX backend that the rest of the app talks to (U2).
///
/// Adds the policy layer on top of raw AX plumbing:
/// - write-then-verify on `setFrame` (→ `.writeRejected`, never a silent no-op),
/// - window→display partitioning by the majority-area rule,
/// - nil (never a crash) when nothing is focused.
///
/// All rects are in the canonical Quartz top-left-origin global space; grid
/// math (U4) consumes `DisplayDescriptor.usableBounds` from here.
public final class AXWindowController {

    /// How far the read-back frame may drift from the requested frame before
    /// the write counts as rejected. Some apps legitimately round to integral
    /// pixels; ~1.5 pt absorbs that while still catching real rejections
    /// (Electron/Java apps that clamp to a minimum size, ignore writes, etc).
    public static let frameWriteTolerance: CGFloat = 1.5

    private let backend: AXBackend

    public init(backend: AXBackend) {
        self.backend = backend
    }

    // MARK: - Focus & frames

    /// The focused window, or nil when no app has one (e.g. Finder desktop
    /// focus). Callers treat nil as "nothing to place", not an error.
    public func focusedWindow() throws -> AXWindowHandle? {
        try backend.focusedWindow()
    }

    public func frame(of window: AXWindowHandle) throws -> CGRect {
        try backend.frame(of: window)
    }

    /// Writes the frame, reads it back, and throws
    /// `AXWindowError.writeRejected` when the result is grossly off
    /// (beyond `frameWriteTolerance`) — so a window that ignores or clamps
    /// AX writes surfaces a typed error instead of silently staying put.
    public func setFrame(_ frame: CGRect, of window: AXWindowHandle) throws {
        try backend.setFrame(frame, of: window)
        let actual = try backend.frame(of: window)

        let tolerance = Self.frameWriteTolerance
        if abs(actual.minX - frame.minX) > tolerance || abs(actual.minY - frame.minY) > tolerance {
            throw AXWindowError.writeRejected(attribute: "position")
        }
        if abs(actual.width - frame.width) > tolerance || abs(actual.height - frame.height) > tolerance {
            throw AXWindowError.writeRejected(attribute: "size")
        }
    }

    // MARK: - Displays & partitioning

    public func displays() -> [DisplayDescriptor] {
        backend.displays()
    }

    /// All standard windows assigned to `display` under the majority-area
    /// rule: a window belongs to the display containing the majority of its
    /// frame's area; ties break to the display containing the frame's center.
    ///
    /// Windows whose frame cannot be read (hung app, just-closed window) are
    /// skipped — one bad window must not fail enumeration for the rest; the
    /// per-window `frame(of:)`/`setFrame` paths still surface those errors.
    public func windows(onDisplay display: DisplayDescriptor) throws -> [AXWindowHandle] {
        let displays = backend.displays()
        return try backend.windows().filter { window in
            guard let frame = try? backend.frame(of: window) else { return false }
            return Self.assignedDisplay(for: frame, among: displays)?.id == display.id
        }
    }

    /// The display a window is assigned to (majority-area rule, center
    /// tie-break); nil when the window overlaps no display at all.
    public func display(containing window: AXWindowHandle) throws -> DisplayDescriptor? {
        let frame = try backend.frame(of: window)
        return Self.assignedDisplay(for: frame, among: backend.displays())
    }

    /// Majority-area partition rule (plan, U2): the display containing the
    /// largest share of `frame`'s area wins; when the top shares tie, the
    /// display containing the frame's center wins. Pure and unit-tested.
    static func assignedDisplay(for frame: CGRect, among displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        guard !displays.isEmpty, frame.width > 0, frame.height > 0 else { return nil }

        let overlaps: [(display: DisplayDescriptor, area: CGFloat)] = displays.map { display in
            let intersection = display.quartzBounds.intersection(frame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (display, area)
        }

        guard let maxArea = overlaps.map(\.area).max(), maxArea > 0 else {
            return nil // off-screen window: no display contains any of it
        }

        // Candidates within epsilon of the max share (exact ties in practice).
        let epsilon: CGFloat = 0.5
        let candidates = overlaps.filter { $0.area >= maxArea - epsilon }.map(\.display)
        if candidates.count == 1 { return candidates[0] }

        // Tie-break: the display containing the frame's center. Quartz rect
        // containment is min-edge-inclusive, so a center sitting exactly on a
        // shared edge deterministically belongs to the display starting there.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return candidates.first { $0.quartzBounds.contains(center) } ?? candidates[0]
    }
}
