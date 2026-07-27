# Polish backlog (document only — push later)

Small README copy fixes. Product is otherwise in a good place.

---

## 1. for / not for — first row (“You want…” / Quintile)

### Problem
Current row is too narrow and example-specific:

| You want… | Quintile |
|-----------|----------|
| Place a window on columns 1–3 of a 5-wide grid from the keyboard | Yes — that’s the point |

Reads like a niche edge case, not the product promise (precise grid placement, where you want it, fast, keyboard-only).

### Options (You want… → Quintile)

**A — Recommended**

| You want… | Quintile |
|-----------|----------|
| Precise keyboard control of windows on a grid — put them where you want, quickly | Yes — that’s the point |

**B — Slightly more feature-complete**

| You want… | Quintile |
|-----------|----------|
| To place windows exactly where you want on a grid, keyboard-only, without auto-tiling | Yes — that’s the point |

**C — Shortest**

| You want… | Quintile |
|-----------|----------|
| Fast, keyboard-only window placement on a grid you control | Yes — that’s the point |

**D — Emphasize “you place, nothing rearranges”**

| You want… | Quintile |
|-----------|----------|
| To snap windows to a grid yourself — any span, no auto layout takeover | Yes — that’s the point |

### Decision
- **Preferred:** **A** (clear, generic, ease + control without drowning in product jargon).  
- **If A feels soft on “exact”:** **B**.  
- Avoid reintroducing “5-wide / columns 1–3” in this row — that story already lives in demos and the span section.

### Apply later
Replace the first data row of `README.md` § for / not for with the chosen pair. Leave other rows as-is.

---

## 2. Keys table — `⌃⌥N` next display

### Problem
`next display` is unclear (virtual Spaces? next app? next monitor?).

Current:

| chord | action |
|-------|--------|
| `⌃⌥N` | next display |

### Options

**A — Recommended (concise + parenthetical)**

| chord | action |
|-------|--------|
| `⌃⌥N` | next display (send focused window to another attached monitor) |

**B — Slightly shorter**

| chord | action |
|-------|--------|
| `⌃⌥N` | send window to next attached monitor |

**C — Explicit multi-monitor only**

| chord | action |
|-------|--------|
| `⌃⌥N` | next monitor (if more than one display is connected) |

### Decision
- **Preferred:** **A** — keeps the short name `next display` and explains in parentheses.  
- **If table density is tight:** **B**.  
- Note: this action is for **physical/attached displays**, not macOS Spaces. Do not say “Space.”

### Apply later
Edit `README.md` § keys, row for `⌃⌥N` only. Optionally mirror the same phrasing in Quick Start / Shortcuts UI if that still says bare “Next display.”

---

## Status

| # | Item | Status |
|---|------|--------|
| 1 | for/not-for first-row verbiage | **Shipped** — option A on `main` |
| 2 | `⌃⌥N` multi-monitor clarity | **Shipped** — option A on `main` |

Applied: precise grid-control row; `⌃⌥N` parenthetical for attached monitors.
