import CoreGraphics
import Foundation
import QuintileCore

/// U3 test scenarios: display identity keys and grid-profile persistence.
/// Store tests use the REAL filesystem in a per-run temp directory.
func displayStoreTests(_ t: TestHarness) {
    func makeInfo(vendor: UInt32 = 0x10AC, model: UInt32 = 0xA0C4, serial: UInt32,
                  name: String = "DELL U3223QE",
                  pixels: CGSize = CGSize(width: 3840, height: 2160)) -> DisplayInfo {
        DisplayInfo(vendorNumber: vendor, modelNumber: model, serialNumber: serial,
                    localizedName: name, pixelSize: pixels)
    }

    func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quintile-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    t.suite("DisplayIdentity") { t in
        t.test("identical vendor/model with different serials yield distinct keys") {
            let a = DisplayIdentity(info: makeInfo(serial: 1111))
            let b = DisplayIdentity(info: makeInfo(serial: 2222))
            t.expect(a.key != b.key, "expected distinct keys, both were \(a.key)")
        }

        t.test("same serial-bearing display at two resolutions keeps the same key") {
            let native = DisplayIdentity(info: makeInfo(serial: 1111))
            let scaled = DisplayIdentity(info: makeInfo(serial: 1111,
                                                        pixels: CGSize(width: 2560, height: 1440)))
            t.expectEqual(native.key, scaled.key,
                          "resolution must not affect identity when a serial is present")
        }

        t.test("serial-less display falls back to name+resolution without crashing") {
            let identity = DisplayIdentity(info: makeInfo(serial: 0))
            t.expect(!identity.key.isEmpty)
            t.expect(identity.key.contains("DELL U3223QE"), "fallback key should embed the name: \(identity.key)")
            t.expect(identity.key.contains("3840x2160"), "fallback key should embed the resolution: \(identity.key)")
        }

        t.test("two serial-less displays with different names/resolutions yield distinct keys") {
            let a = DisplayIdentity(info: makeInfo(serial: 0, name: "LG HDR 4K"))
            let b = DisplayIdentity(info: makeInfo(serial: 0, name: "Sidecar Display",
                                                   pixels: CGSize(width: 2732, height: 2048)))
            t.expect(a.key != b.key, "expected distinct fallback keys, both were \(a.key)")
        }
    }

    t.suite("GridProfileStore") { t in
        t.test("unknown identity is auto-assigned defaults with 5×2 standard active") {
            let dir = try makeTempDir()
            let store = try GridProfileStore(directory: dir)
            let identity = DisplayIdentity(info: makeInfo(serial: 1111))

            let config = store.config(for: identity)
            t.expectEqual(config.activeSlot, .standard)
            t.expectEqual(config.activeProfile, GridProfile(name: "standard", rows: 2, cols: 5))
            t.expectEqual(config.secondary, GridProfile.defaultProfile(for: .secondary))
            t.expectEqual(config.tertiary, GridProfile.defaultProfile(for: .tertiary))
        }

        t.test("auto-assignment is on disk before any explicit save call") {
            let dir = try makeTempDir()
            let identity = DisplayIdentity(info: makeInfo(serial: 1111))
            do {
                let store = try GridProfileStore(directory: dir)
                _ = store.config(for: identity) // first access only — no explicit save API exists
                t.expect(store.lastPersistError == nil, "persist failed: \(String(describing: store.lastPersistError))")
                t.expect(FileManager.default.fileExists(atPath: store.fileURL.path),
                         "profiles.json should exist immediately after first access")
            }
            // Fresh store on the same directory must already see the assignment.
            let reloaded = try GridProfileStore(directory: dir)
            t.expect(reloaded.knownIdentityKeys.contains(identity.key))
            t.expectEqual(reloaded.config(for: identity).activeProfile,
                          GridProfile(name: "standard", rows: 2, cols: 5))
        }

        t.test("persisted profile assignment survives store reload") {
            let dir = try makeTempDir()
            let identity = DisplayIdentity(info: makeInfo(serial: 1111))
            let custom = GridProfile(name: "wide", rows: 1, cols: 7)
            do {
                let store = try GridProfileStore(directory: dir)
                store.updateProfile(custom, slot: .secondary, for: identity)
                t.expect(store.lastPersistError == nil)
            }
            let reloaded = try GridProfileStore(directory: dir)
            let config = reloaded.config(for: identity)
            t.expectEqual(config.secondary, custom)
            t.expectEqual(config.standard, GridProfile.defaultProfile(for: .standard),
                          "untouched slots keep their defaults")
        }

        t.test("orphaned entry survives other identities being modified and a reload") {
            let dir = try makeTempDir()
            let orphan = DisplayIdentity(info: makeInfo(serial: 1111))
            let survivor = DisplayIdentity(info: makeInfo(serial: 2222))
            let orphanProfile = GridProfile(name: "orphan-grid", rows: 3, cols: 3)
            do {
                let store = try GridProfileStore(directory: dir)
                store.updateProfile(orphanProfile, slot: .standard, for: orphan)
            }
            do {
                // Orphan is never asked for again; other identities churn.
                let store = try GridProfileStore(directory: dir)
                store.updateProfile(GridProfile(name: "other", rows: 4, cols: 4),
                                    slot: .tertiary, for: survivor)
                store.cycleActiveSlot(for: survivor)
            }
            let reloaded = try GridProfileStore(directory: dir)
            t.expect(reloaded.knownIdentityKeys.contains(orphan.key), "orphan entry was purged")
            t.expectEqual(reloaded.config(for: orphan).standard, orphanProfile)
        }

        t.test("cycleActiveSlot cycles standard → secondary → tertiary → standard and persists") {
            let dir = try makeTempDir()
            let identity = DisplayIdentity(info: makeInfo(serial: 1111))
            do {
                let store = try GridProfileStore(directory: dir)
                t.expectEqual(store.config(for: identity).activeSlot, .standard)
                t.expectEqual(store.cycleActiveSlot(for: identity), .secondary)
                t.expectEqual(store.cycleActiveSlot(for: identity), .tertiary)
            }
            // Persisted across reload: continue the cycle in a fresh store.
            let reloaded = try GridProfileStore(directory: dir)
            t.expectEqual(reloaded.config(for: identity).activeSlot, .tertiary)
            t.expectEqual(reloaded.activeProfile(for: identity),
                          GridProfile.defaultProfile(for: .tertiary))
            t.expectEqual(reloaded.cycleActiveSlot(for: identity), .standard)
        }

        t.test("activeProfile reflects updates to the active slot") {
            let dir = try makeTempDir()
            let store = try GridProfileStore(directory: dir)
            let identity = DisplayIdentity(info: makeInfo(serial: 3333))
            let custom = GridProfile(name: "custom-standard", rows: 2, cols: 6)
            store.updateProfile(custom, slot: .standard, for: identity)
            t.expectEqual(store.activeProfile(for: identity), custom)
        }
    }
}
