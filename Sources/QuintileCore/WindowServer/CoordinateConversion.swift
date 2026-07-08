import CoreGraphics

/// THE Cocoa↔Quartz coordinate flip (U2).
///
/// The canonical coordinate space everywhere in the core is Quartz
/// top-left-origin global. Cocoa (NSScreen/NSEvent/NSPanel) uses
/// bottom-left-origin global. The two spaces share x and flip y about the
/// PRIMARY display's height: the primary screen has Quartz origin (0,0)
/// top-left and Cocoa origin (0,0) bottom-left, so
///
///     quartzY = primaryHeight - cocoaMaxY   (rects)
///     quartzY = primaryHeight - cocoaY      (points)
///
/// and identically in the other direction (the flip is an involution).
/// EVERY conversion between the two spaces goes through this helper —
/// never hand-roll the flip at a call site.
public enum QuartzCocoa {

    /// Cocoa bottom-left global point (e.g. `NSEvent.mouseLocation`) →
    /// Quartz top-left global point.
    public static func quartzPoint(fromCocoa point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Cocoa bottom-left global rect (e.g. `NSScreen.visibleFrame`) →
    /// Quartz top-left global rect.
    public static func quartzRect(fromCocoa rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Quartz top-left global rect (e.g. `DisplayDescriptor.usableBounds`) →
    /// Cocoa bottom-left global rect (e.g. for `NSPanel.setFrame`).
    public static func cocoaRect(fromQuartz rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        // Same involution as quartzRect(fromCocoa:) — the flip is symmetric.
        quartzRect(fromCocoa: rect, primaryHeight: primaryHeight)
    }
}
