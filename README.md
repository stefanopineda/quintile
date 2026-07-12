# Quintile

**Keyboard-only grid tiling for macOS.**

https://github.com/stefanopineda/quintile/raw/main/docs/demos/hero.mp4

![hero](docs/demos/hero.gif)

Place any window on any N×M span — two keypresses, no mouse.

- **arbitrary grids** — 5×2, 4×3, whatever fits the display
- **span picker** — `⌃⌥G`, two cells, done
- **presets + profiles** — thirds, quarters, three grids per display
- **public Accessibility API only** — no SIP hacks, no private frameworks
- **free, MIT** · Developer ID signed & notarized

---

## install

```bash
brew install --cask stefanopineda/quintile/quintile
```

or:

```bash
brew tap stefanopineda/quintile
brew install --cask quintile
```

or download [Quintile.app.zip](https://github.com/stefanopineda/quintile/releases/latest) · or `git clone` + `make run`

> Official `brew install quintile` (homebrew/cask) is blocked until the GitHub repo meets Homebrew notability (~225 stars / 90 forks / 90 watchers). We submitted [PR #274471](https://github.com/Homebrew/homebrew-cask/pull/274471); maintainers asked to resubmit once thresholds are met.

### after install

Quintile is a **menu bar app** (no Dock icon).

1. Open it: Spotlight (**⌘Space**) → `Quintile` → Enter (or `/Applications/Quintile.app`)
2. Look for **⊞!** / **⊞** near the clock
3. **System Settings → Privacy & Security → Accessibility → Quintile** ON  
   (if it already looks ON after an update: OFF then ON, then **Check Again**)
4. Click a window → hold **Control+Option** → press **`[`** (left third)

Full map later: menu bar **⊞ → Quick Start…**

## keys

Start with thirds. Everything else is optional.

| chord | action |
|-------|--------|
| `⌃⌥[` `]` `\` | left / center / right third |
| `⌃⌥1…4` | quadrants |
| `⌃⌥⇧1…6` | sixths |
| `⌃⌥G` then two cells | span any rectangle on the grid |
| `⌃⌥←↑↓→` | move within grid |
| `⌃⌥P` | cycle grid profile |
| `⌃⌥N` | next display |

leader is **control + option**. hold it, hit a key.

## from source

```bash
git clone https://github.com/stefanopineda/quintile
cd quintile && make run
```

```bash
make test
make app    # dist/Quintile.app
```

## status

v0.1.8 · macOS 14+ · Apple Silicon · Developer ID signed & notarized

## license

[MIT](LICENSE)
