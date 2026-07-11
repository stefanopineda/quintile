# Quintile

**Keyboard-only grid tiling for macOS.**

https://github.com/stefanopineda/quintile/raw/main/docs/demos/hero.mp4

![hero](docs/demos/hero.gif)

Place any window on any N×M span — two keypresses, no mouse.

- **arbitrary grids** — 5×2, 4×3, whatever fits the display
- **span picker** — `⌃⌥G`, two cells, done
- **presets + profiles** — thirds, quarters, three grids per display
- **public Accessibility API only** — no SIP hacks, no private frameworks
- **free, MIT**

---

## install

```bash
brew install --cask stefanopineda/quintile/quintile
```

or download [Quintile.app.zip](https://github.com/stefanopineda/quintile/releases/latest) · or `git clone` + `make run`

then:

1. launch Quintile
2. **System Settings → Privacy & Security → Accessibility** → enable Quintile

unsigned build for now — Homebrew clears quarantine on install. manual download once:

```bash
xattr -dr com.apple.quarantine /Applications/Quintile.app
```

## keys

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
make test   # unit tests
make app    # dist/Quintile.app
```

## status

v0.1.5 · macOS 14+ · Apple Silicon · unsigned (no Developer ID / notarization yet)

## license

[MIT](LICENSE)
