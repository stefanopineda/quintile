# Contributing to Quintile

Thanks for your interest! Quintile is a small, focused codebase — this page
tells you where things live and how to build and test.

## Layout

```
Sources/
├── QuintileCore/          # ALL testable logic lives here — no SwiftUI, no windows
│   ├── Grid/              # GridProfile, CellSpan, GridMath (pure placement math)
│   ├── Displays/          # stable display identity (vendor/model/serial + fallbacks)
│   ├── Persistence/       # GridProfileStore (JSON in Application Support)
│   ├── Permissions/       # AccessibilityPermissionManager (state machine over a seam)
│   ├── WindowServer/      # AXWindowController over the AXBackend protocol seam
│   ├── Hotkeys/           # HotkeyManager over the EventTapProviding seam + CGEventTap impl
│   ├── UI/                # GridSelectionStateMachine (pure — the overlay's brain)
│   ├── Actions/           # presets, move-within-grid, send-to-display
│   └── App/               # LoginItemManager (SMAppService behind a seam)
└── QuintileApp/           # thin AppKit shell: menu bar, overlay panel, windows, wiring
Tests/QuintileTestRunner/  # the test suite (see "Testing" below)
Scripts/                   # app-bundle assembly (build-app.sh + Info.plist)
```

**Rule of thumb:** anything with an `if` in it belongs in `QuintileCore` behind a
protocol seam, so it can be tested without Accessibility permission or a display.
`QuintileApp` stays dumb — it renders state and forwards events.

## Building

Command Line Tools are enough (full Xcode not required):

```sh
make build   # swift build
make test    # run the full test suite
make app     # assemble dist/Quintile.app (ad-hoc signed)
make run     # build + launch the app
```

## Testing

Tests are a plain executable (`swift run quintile-tests`), not `swift test`.
Why: Command Line Tools ship neither a runnable XCTest nor a discoverable
Swift Testing harness, and Quintile should build and test on a machine with
no Xcode. The harness API (`TestHarness`) mirrors Swift Testing — `t.test {}`
↔ `@Test`, `t.expect(...)` ↔ `#expect(...)` — so migrating under full Xcode
is mechanical if we ever want to.

Everything that can run without permissions is unit-tested against fakes
(`FakeAXBackend`, `FakeEventTap`, fake trust checkers). Live-AX behavior
(actually moving windows) is covered by the manual checklist in
`Sources/QuintileCore/WindowServer/LiveAXBackend.swift` — run it once on a
real machine when touching that layer.

## Conventions

- Swift 5 language mode, macOS 14+.
- The canonical coordinate space is Quartz top-left-origin global. Every
  Cocoa↔Quartz conversion goes through the shared `QuartzCocoa` helper
  (`Sources/QuintileCore/WindowServer/CoordinateConversion.swift`); do not
  hand-roll flips at call sites.
- Typed errors (`AXWindowError`) — never silently swallow an AX failure.
- Conventional commit messages (`feat(core): …`, `fix: …`).

## Pull requests

Keep them scoped to one concern, with tests for any behavior change. If a
change affects the keyboard UX, update the shortcut table in the README and
the in-app shortcuts panel data together.
