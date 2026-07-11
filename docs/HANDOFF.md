# Quintile — Handoff

Status of the project as of the **v0.1.0** release, what was built, the
decisions behind it, and what remains. Written for whoever picks this up next
(including future-you).

- **Repo:** https://github.com/stefanopineda/quintile (public)
- **Homebrew tap:** https://github.com/stefanopineda/homebrew-quintile (public)
- **Release:** https://github.com/stefanopineda/quintile/releases/tag/v0.1.0
- **Default branch:** `main`
- **Tests:** 120 passing (`make test`)
- **Source:** ~4,000 lines of Swift across `QuintileCore` (logic) + `QuintileApp` (shell)

---

## 1. What Quintile is

A free, MIT-licensed, **keyboard-only** macOS window tiler built on the public
Accessibility API only — no SIP disable, no scripting-addition injection, no
private frameworks. It divides each display into an arbitrary N×M grid and lets
you place windows on any rectangular span of cells from the keyboard, in two
keypresses. See `README.md` for the user-facing pitch, shortcuts, and demos.

The design north star: **addition by subtraction.** No mouse-drag snap zones,
ever (that's a permanent product principle, not a v1 cut). A smaller all-keyboard
surface is what makes the shortcuts stick.

---

## 2. Scope of work completed

### Planning & review (before code)
- Reviewed and hardened the implementation plan
  (`docs/plans/2026-07-07-001-feat-quintile-window-manager-plan.md`) with a
  6-persona document review: 22 fixes applied, 4 judgment calls recorded in the
  plan's "Deferred / Open Questions" section. Notable catches: the "zero prior
  art" claim was corrected (Hammerspoon `hs.grid` exists), the unimplementable
  "preset groupings" requirement was descoped, and undefined swap/cycle
  semantics were flagged for decision.

### Implementation (9 units, built in parallel isolated worktrees)
All logic lives in **`QuintileCore`** behind protocol seams so it is unit-tested
without permissions or a display; **`QuintileApp`** is a thin AppKit shell.

| Unit | What it does | Key files |
|------|--------------|-----------|
| U4 | Grid model + placement math (edge-rounding span resolution) | `Grid/GridProfile.swift`, `Grid/GridMath.swift` |
| U3 | Stable per-display identity + JSON persistence | `Displays/DisplayIdentity.swift`, `Persistence/GridProfileStore.swift` |
| U1 | Accessibility permission state machine + granted-transition hook | `Permissions/AccessibilityPermissionManager.swift` |
| U2 | AX window wrapper (typed errors) behind a backend seam | `WindowServer/AX*.swift`, `LiveAXBackend.swift` |
| U5 | Global hotkey engine + event-tap lifecycle + Fn+Ctrl+Arrow spike | `Hotkeys/*.swift` |
| U6 | Grid-select overlay state machine (two-keypress fast path) | `UI/GridSelectionStateMachine.swift`, `App/UI/GridOverlayView.swift` |
| U7 | Presets (quadrants/thirds/sixths), move-within-grid, send-to-display | `Actions/*.swift` |
| U8 | Menu bar, preferences, onboarding, login item, profile cycling | `App/UI/*.swift`, `App/AppCoordinator.swift`, `App/LoginItemManager.swift` |
| U9 | README, LICENSE, CONTRIBUTING, Homebrew cask | repo root, `Casks/` |

### Code review (9 reviewers, all findings validated)
Ran a multi-agent code review producing 17 findings, each independently
verified, then fixed in two batches:
- **P1 (5):** live window-handle identity via `CFEqual` (the `===` default
  silently failed in production, breaking mover-exclusion); `Codable` decode
  validation to prevent a corrupt-`profiles.json` crash loop; hotkey action
  bodies moved off the event-tap callback (a hung app could stall all keyboard
  input); event-tap teardown/recreate on permission revoke→re-grant; a single
  shared coordinate-flip helper (`WindowServer/CoordinateConversion.swift`).
- **P2/P3 (12):** occupant-relocation error surfacing, hidden-app window
  filtering, corrupt-store quarantine/backup, fn-state resync, and test
  coverage + dedup.

### Verification & demos
- 120 tests green via a **custom `quintile-tests` executable runner** (the
  Command Line Tools environment ships no usable XCTest/Swift Testing harness —
  see §5).
- Live behavior verified on a real display. The four GIFs in `docs/demos/` are
  recordings of the running app (grid-select overlay, quadrant presets +
  move-within-grid, profile cycling, and a hero reel).

### Packaging, release, and icon
- `Scripts/build-app.sh` assembles `Quintile.app` (LSUIElement menu-bar agent)
  from the SPM build, ad-hoc signed. `make app` / `make run`.
- Tagged **v0.1.0**, uploaded `Quintile.app.zip`, and wired the Homebrew tap
  with a checksum-pinned cask that **auto-clears the Gatekeeper quarantine flag
  on install** (see §4).
- App icon: five terminal windows with a selected column (`Scripts/AppIcon.icns`,
  vector source in `Scripts/icon/`), wired via `CFBundleIconFile`.

---

## 3. Product decisions locked in

These were resolved during execution and are reflected in the code + tests:

- **`standard` profile = 5×2**, and it is the active profile on every newly
  connected display. (`secondary` = 2×2, `tertiary` = 3×2.)
- **Profile cycling (`⌃⌥P`) is pointer-only** — it changes which grid is active
  and briefly flashes the new grid, but never retiles existing windows.
- **Move-into-occupied = footprint translation.** The moved window's whole span
  shifts one cell; any windows overlapping the destination relocate into the
  vacated footprint, each preserving its own span size. No windows get lost
  off-grid; at a grid edge the move is a no-op with a soft feedback cue.
- **Keyboard-only, permanently.** No pointer-driven tiling. (Non-goal, not a
  deferral.)

---

## 4. Distribution reality (important context)

The build is **unsigned / ad-hoc-signed and not notarized** — there is no paid
Apple Developer Program membership yet, and Developer ID signing + notarization
cannot be done without one (they require an Apple-issued cert and interactive
Apple auth).

Consequences and how they're currently handled:
- **Homebrew 6 force-quarantines every cask** and removed the `--no-quarantine`
  opt-out. So the cask uses a `postflight` that runs
  `xattr -dr com.apple.quarantine` on the installed app. This means a plain
  `brew install --cask stefanopineda/quintile/quintile` produces a launch-ready
  app with no Gatekeeper dialog — **at the cost of the cask deliberately
  bypassing Gatekeeper for this app.** That trade-off is acceptable for a
  personal tap distributing your own app; it should be removed once notarized.
- **Direct `.zip` downloads** are quarantined by the browser and need a one-time
  `xattr -dr com.apple.quarantine /Applications/Quintile.app` or System Settings
  → Privacy & Security → Open Anyway. Documented in the README.
- **Apple Silicon only** (arm64) and **macOS 14+**. Not a universal binary.

---

## 5. Notable implementation details / gotchas

- **Tests are an executable, not `swift test`.** `Tests/QuintileTestRunner/`
  holds a tiny Swift-Testing-shaped harness (`TestHarness.swift`) because CLT
  has no runnable XCTest/Testing. `t.test {}` ↔ `@Test`, `t.expect(...)` ↔
  `#expect(...)`, so migrating to `swift test` under full Xcode is mechanical.
  Run with `make test` (`swift run quintile-tests`).
- **Coordinate space:** canonical space is Quartz top-left-origin global. The
  single Cocoa↔Quartz flip lives in `WindowServer/CoordinateConversion.swift`
  (`QuartzCocoa`); do not hand-roll flips at call sites.
- **Protocol seams** (`AXBackend`, `EventTapProviding`, the permission trust
  checker) are what make the core testable — fakes live in
  `Tests/QuintileTestRunner/SharedFakes.swift`.
- **Fn+Ctrl+Arrow takeover is experimental.** The spike outcome is documented in
  `Hotkeys/SystemShortcutBridge.swift`: interception reliability across macOS
  versions is unverifiable without a live trusted runner, so the custom
  `⌃⌥` leader keys are the always-available default.
- **Icon regeneration:** edit `Scripts/icon/gen.py`, run it, then rebuild the
  `.icns` with `iconutil` (small sizes 16/32 use a simplified variant).

---

## 6. Next steps

### Priority 1 — Proper code signing + notarization
This removes every friction in §4 and is the single highest-value follow-up.
1. Enroll in the Apple Developer Program ($99/yr).
2. Install a **Developer ID Application** cert into the keychain.
3. Store a `notarytool` credential profile (Apple ID + app-specific password, or
   an App Store Connect API key).
4. Build with the identity: `CODESIGN_IDENTITY="Developer ID Application: …" make app`
   (the build script already re-enables the hardened runtime for real identities).
5. `xcrun notarytool submit dist/Quintile.app.zip --keychain-profile <name> --wait`,
   then `xcrun stapler staple dist/Quintile.app`.
6. Re-zip, re-upload the release asset, bump the cask `sha256`, and **remove the
   `postflight` de-quarantine** from the cask (repo + tap).

### Priority 2 — Resolve the two open P1 product questions
Both are recorded in the plan's "Deferred / Open Questions" and were given
working defaults, but merit revisiting with real usage:
- Whether profile cycling should optionally re-snap grid-aligned windows.
- Whether span-vs-span move collisions want richer semantics than footprint
  translation.

### Priority 3 — Roadmap features (from the plan's deferred list)
- **Saved, hotkey-bindable cell-span presets** per profile (descoped from R3).
- **Cross-display cell-by-cell move** (only "send to next display" ships today).
- **Agent-native surface:** a CLI or `quintile://` URL scheme so tiling actions
  are scriptable, and machine-readable state (active profile per display). The
  action types are already pure primitives, so this is a thin shim.
- **Universal binary** (add arm64 + x86_64) once Intel support is wanted.
- **`homebrew-core` submission** after the tap builds an audience.

### Priority 4 — Polish
- Live-reload `GridProfileStore` on external file edits.
- ~~In-overlay static help legend for first-time users.~~ **Done in spirit (v0.1.3):** post-grant Quick Start cheat sheet + menu re-open; grid overlay already has an in-session hint bar.
- ~~Onboarding falsely reports "Permission was declined" seconds after granting.~~ **Fixed (v0.1.4):** the permission state machine flipped to `.denied` after a single untrusted follow-up check — 3s after the prompt, nowhere near enough time to actually navigate System Settings and grant it. Now requires `deniedGraceChecks` (10, ~30s at the app's 3s poll cadence) consecutive untrusted checks before concluding a real decline. See `AccessibilityPermissionManager.swift`.
- ~~Cask caveats implied the quarantine-clear command was a required manual step.~~ **Fixed (v0.1.4):** caveats now lead with "already handled automatically" and demote the `xattr` command to an explicit fallback-only note.
- ~~Install → grant Accessibility required too many manual steps (find the app, launch it, notice the OS prompt, click through to Settings).~~ **Fixed (v0.1.5):** the cask `postflight` now launches `Quintile.app` after install; on a fresh (`.notDetermined`) permission state the app itself opens `System Settings → Privacy & Security → Accessibility` directly via the `x-apple.systempreferences:` deep link — both on first launch and every time the onboarding "Grant Access" button is clicked. `brew install` now gets you to "flip one toggle" with zero extra navigation. Apple does not allow the toggle itself to be flipped programmatically (no app may grant its own — or another app's — TCC entry), so that one click remains manual by design.
- **First-run learnability (2026-07-11 plan):** progressive first-win coach (Control+Option + thirds only, detect `third.*` performed); full map demoted to Quick Start reference; wall-clock ~30s denial grace (poll can be faster while onboarding is visible without false-decline); Check Again + stale-TCC OFF→ON copy; menu-bar discoverability transient; `applicationShouldHandleReopen` re-surfaces permission/coach when stuck. See `docs/plans/2026-07-11-001-feat-first-run-onboarding-ux-plan.md`.
- Localization of onboarding/README copy.

---

## 7. Operational checklist for cutting the next release

1. Land changes on `main`, `make test` green.
2. `make app` → `dist/Quintile.app`.
3. `ditto -c -k --keepParent --sequesterRsrc dist/Quintile.app dist/Quintile.app.zip`.
4. `shasum -a 256 dist/Quintile.app.zip` → new digest.
5. Bump `version` in `Casks/quintile.rb` and set the new `sha256`; copy the cask
   into the tap repo (`stefanopineda/homebrew-quintile`).
6. `git tag vX.Y.Z && git push --tags`; `gh release create vX.Y.Z dist/Quintile.app.zip`.
7. Push repo + tap; verify with `brew fetch --cask stefanopineda/quintile/quintile`
   (fails on checksum mismatch).
