import CoreGraphics
import QuintileCore

// MARK: - Shared AX fakes
//
// The single fake AX backend/window used by AXControllerTests and
// ActionsTests (they previously carried near-duplicate copies). Union of
// both suites' capabilities: write counting, per-window accessError /
// setFrameError / ignoresSizeWrites, and display fixtures with configurable
// usableBounds. Real AX cannot run here: the test runner is not
// Accessibility-trusted, by design — live behavior is covered by the manual
// checklist in `LiveAXBackend.swift`.
//
// The WrapperFakeBackend fixture in ActionsTests intentionally stays
// separate: it exists to model DISTINCT wrapper objects per enumeration
// (the live backend's handle shape), which this fake deliberately does not.

/// A fake window: a mutable frame plus configurable misbehavior.
final class FakeWindow: AXWindowHandle {
    var frame: CGRect
    /// Simulates an Electron/Java-style app that silently ignores size writes
    /// (position writes still apply).
    var ignoresSizeWrites = false
    /// Thrown by every frame read/write — simulates a hung or dead app.
    var accessError: AXWindowError?
    /// Thrown by `setFrame` only — reads still succeed. Simulates a window
    /// that enumerates fine but whose writes fail (partial-failure paths).
    var setFrameError: AXWindowError?

    init(frame: CGRect) {
        self.frame = frame
    }
}

final class FakeAXBackend: AXBackend {
    var allWindows: [FakeWindow] = []
    var focused: FakeWindow?
    var displayList: [DisplayDescriptor] = []
    /// Number of raw setFrame writes issued through the backend (including
    /// ones that threw), so boundary/no-focus tests can assert ZERO writes.
    private(set) var setFrameCallCount = 0

    func focusedWindow() throws -> AXWindowHandle? { focused }

    func windows() throws -> [AXWindowHandle] { allWindows }

    func frame(of window: AXWindowHandle) throws -> CGRect {
        let fake = window as! FakeWindow
        if let error = fake.accessError { throw error }
        return fake.frame
    }

    func setFrame(_ frame: CGRect, of window: AXWindowHandle) throws {
        setFrameCallCount += 1
        let fake = window as! FakeWindow
        if let error = fake.accessError { throw error }
        if let error = fake.setFrameError { throw error }
        if fake.ignoresSizeWrites {
            fake.frame.origin = frame.origin // size write silently dropped
        } else {
            fake.frame = frame
        }
    }

    func displays() -> [DisplayDescriptor] { displayList }
}

/// Display fixture in Quartz top-left global coordinates. `menuBarInset`
/// shrinks `usableBounds` from the top (menu-bar stand-in); the default 0
/// makes usableBounds == quartzBounds so expected frames are exact grid
/// fractions.
func makeFakeDisplay(id: CGDirectDisplayID, quartzBounds: CGRect,
                     menuBarInset: CGFloat = 0) -> DisplayDescriptor {
    DisplayDescriptor(
        id: id,
        quartzBounds: quartzBounds,
        usableBounds: CGRect(x: quartzBounds.minX, y: quartzBounds.minY + menuBarInset,
                             width: quartzBounds.width, height: quartzBounds.height - menuBarInset),
        info: DisplayInfo(vendorNumber: 100 + id, modelNumber: 200, serialNumber: 300 + id,
                          localizedName: "Fake \(id)", pixelSize: quartzBounds.size)
    )
}
