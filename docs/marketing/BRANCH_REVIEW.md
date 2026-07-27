# Review & test this branch (`docs/storefront-discoverability`)

**Do not merge to `main` until you approve.**  
**Do not announce until `main` has this README.**

This branch is docs-only: storefront README + announce/outreach *drafts*. Nothing is posted yet.

---

## What’s on this branch

| Path | What |
|------|------|
| `README.md` | Storefront / demo-reel README |
| `docs/PATH_TO_HOMEBREW.md` | Official cask as install ease — packaging notes |
| `docs/STOREFRONT_REVIEW.md` | README delta notes |
| `docs/plans/2026-07-26-001-storefront-and-discoverability-plan.md` | Plan (utility / ease / discoverability) |
| `docs/marketing/launch-wave-2.md` | Announce copy drafts |
| `docs/marketing/amplifier-kit.md` | Optional outreach packet |
| `docs/marketing/post-merge-checklist.md` | After merge only |
| `docs/demos/*` | Unchanged GIF/MP4 assets |

---

## Discrete pre-merge tests

Do these in order. Check boxes as you go.

### Test 1 — README cold read (5 minutes)

1. Open the PR **Files changed** → `README.md`, or:  
   https://github.com/stefanopineda/quintile/blob/docs%2Fstorefront-discoverability/README.md  
2. Without scrolling for a “tutorial,” answer out loud:
   - [ ] What does this do that Rectangle doesn’t?  
   - [ ] How do I install in one copy-paste?  
   - [ ] What do I press first after Accessibility?  
3. Confirm:
   - [ ] No scoreboard / vanity-metric language  
   - [ ] Official cask note is factual, not a campaign  
   - [ ] Tone is lean, not salesy  

**Fail if:** a stranger only gets “another tiler.” **Fix:** tighten lead / demos before merge.

### Test 2 — Demo assets load (2 minutes)

On the branch README render:

- [ ] Hero GIF or MP4 plays / loads  
- [ ] `grid-select.gif` shows two-cell span  
- [ ] presets-move and profiles GIFs load  

Local check if GH is flaky:

```bash
cd /path/to/quintile   # this branch checked out
open docs/demos/grid-select.gif
open docs/demos/hero.gif
ls -lh docs/demos/
```

**Fail if:** broken image links. **Fix:** paths must stay `docs/demos/...` relative to repo root.

### Test 3 — Diff is expected (1 minute)

```bash
git fetch origin
git diff origin/main...docs/storefront-discoverability --stat
```

Expected: `README.md`, `docs/**`, and a small onboarding fix in `Sources/QuintileApp/AppCoordinator.swift` (`--first-run` resets coach after reinstall).

- [ ] No unrelated product/feature churn  
- [ ] No surprise binary or cask breakage  

### Test 4 — Clean install + first-tile coach (10 minutes)

**Always use the fully-qualified cask** (bare `brew install --cask quintile` fails when multiple taps define `quintile`):

```bash
brew install --cask stefanopineda/quintile/quintile
```

If you already used Quintile on this Mac, wipe coach state first (otherwise you only get Quick Start — coach was `"completed"` under Application Support):

```bash
pkill -x Quintile 2>/dev/null; true
brew uninstall --cask --force --zap stefanopineda/quintile/quintile
rm -rf ~/Library/Application\ Support/Quintile
tccutil reset Accessibility com.stefanopineda.quintile
brew install --cask stefanopineda/quintile/quintile
```

Then:

- [ ] Menu bar shows ⊞! or ⊞  
- [ ] Window is **first-run**: Accessibility and/or **“Try your first tile”** with **Skip for now** — not only the full Quick Start map  
- [ ] After Accessibility ON: focus Safari/Notes → **⌃⌥[** → left third → coach “Nice”  
- [ ] **⌃⌥G** → two cells → custom span  

**Fail if:** only Quick Start after a clean wipe.  
**Fail if:** README primary install is bare `brew install --cask quintile`.

**Note:** Release zip on GitHub is still the last tagged app until you cut a new release with the `--first-run` fix. A full Application Support wipe is enough for first-tile coach with the current release.

### Test 5 — Marketing drafts are drafts (2 minutes)

- [ ] `docs/marketing/launch-wave-2.md` hook is span-first  
- [ ] Install line matches README tap command  
- [ ] No “please star” / scoreboard language in drafts  
- [ ] You did **not** post or DM yet (correct until after merge)  

### Test 6 — Optional: PR preview as a stranger

- [ ] Open PR in a private/incognito window (logged out if possible)  
- [ ] First screen of README still makes sense  

---

## Pass criteria to merge

All of Test 1–5 pass (Test 6 optional). Then:

1. Merge this PR → `main`  
2. Follow `docs/marketing/post-merge-checklist.md` only if you want topics / announce  

## Reject / revise

| Symptom | Action |
|---------|--------|
| README too long / salesy | Cut for/not-for or demote secondary GIFs |
| Hook wrong | Edit lead sentence + `launch-wave-2.md` |
| Install steps wrong | Fix README after Test 4 |
