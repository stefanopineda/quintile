import CoreGraphics
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Seam over the per-display facts needed to compute a stable identity.
///
/// The real implementation (`CGDisplayInfo`) reads CoreGraphics/AppKit; tests
/// use plain `DisplayInfo` values. Keeping the seam at the *facts* level (not
/// the identity level) means `DisplayIdentity` itself is pure and fully
/// unit-testable.
public protocol DisplayInfoProviding {
    /// EDID vendor number (`CGDisplayVendorNumber`).
    var vendorNumber: UInt32 { get }
    /// EDID model number (`CGDisplayModelNumber`).
    var modelNumber: UInt32 { get }
    /// EDID serial number (`CGDisplaySerialNumber`); `0` when unavailable —
    /// some displays/adapters/KVMs don't expose one.
    var serialNumber: UInt32 { get }
    /// Human-readable display name (`NSScreen.localizedName`); may be empty.
    var localizedName: String { get }
    /// Native pixel resolution, used as a fallback disambiguator.
    var pixelSize: CGSize { get }
}

/// A plain value snapshot of display facts. Used as the test fake and as a
/// way to capture live facts once and compute identity purely from them.
public struct DisplayInfo: DisplayInfoProviding, Equatable, Sendable {
    public var vendorNumber: UInt32
    public var modelNumber: UInt32
    public var serialNumber: UInt32
    public var localizedName: String
    public var pixelSize: CGSize

    public init(vendorNumber: UInt32, modelNumber: UInt32, serialNumber: UInt32,
                localizedName: String, pixelSize: CGSize) {
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.localizedName = localizedName
        self.pixelSize = pixelSize
    }
}

/// Live display facts for a `CGDirectDisplayID`, read from CoreGraphics and
/// AppKit at access time.
public struct CGDisplayInfo: DisplayInfoProviding {
    public let displayID: CGDirectDisplayID

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    public var vendorNumber: UInt32 { CGDisplayVendorNumber(displayID) }
    public var modelNumber: UInt32 { CGDisplayModelNumber(displayID) }
    public var serialNumber: UInt32 { CGDisplaySerialNumber(displayID) }

    public var localizedName: String {
        #if canImport(AppKit)
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }
        return screen?.localizedName ?? ""
        #else
        return ""
        #endif
    }

    public var pixelSize: CGSize {
        CGSize(width: CGDisplayPixelsWide(displayID), height: CGDisplayPixelsHigh(displayID))
    }
}

/// A stable per-display identity key that survives reboots and cable/dock
/// changes.
///
/// Primary key: vendor + model + EDID serial. When the serial is `0`
/// (unavailable), falls back to vendor + model + `localizedName` + pixel
/// resolution. `CGDirectDisplayID` and the CGDisplay UUID are deliberately
/// *not* used: neither is stable across reboots/port changes on modern macOS.
///
/// Resolution is only a disambiguator in the fallback path — a serial-bearing
/// display keeps the same identity across resolution changes.
public struct DisplayIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    /// The stable string key used to index persisted per-display config.
    public let key: String

    /// Computes identity purely from a snapshot of display facts.
    public init(info: some DisplayInfoProviding) {
        if info.serialNumber != 0 {
            key = "v\(info.vendorNumber)-m\(info.modelNumber)-s\(info.serialNumber)"
        } else {
            let width = Int(info.pixelSize.width)
            let height = Int(info.pixelSize.height)
            key = "v\(info.vendorNumber)-m\(info.modelNumber)-n[\(info.localizedName)]-r\(width)x\(height)"
        }
    }

    /// Rehydrates an identity from a previously persisted key.
    public init(key: String) {
        self.key = key
    }

    public var description: String { key }
}
