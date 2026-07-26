# Review & test this branch (`growth/500-stars`)

**Do not merge to `main` until you approve.**  
**Do not post launch content until `main` has this README.**

This branch packages Phase A + B + C of the 500-star plan as **reviewable artifacts only**. Nothing is posted or DMed yet.

---

## What’s on this branch

| Path | What |
|------|------|
| `README.md` | Storefront / demo-reel README |
| `docs/PATH_TO_HOMEBREW.md` | Path to official `brew install --cask quintile` |
| `docs/STOREFRONT_REVIEW.md` | README delta notes |
| `docs/plans/2026-07-26-001-growth-500-stars-execution-plan.md` | Full runbook |
| `docs/marketing/launch-wave-2.md` | Frozen post copy (X / Reddit / HN) |
| `docs/marketing/amplifier-kit.md` | DM packet + starter target list |
| `docs/marketing/post-merge-checklist.md` | Topics, social preview, post order (after merge) |
| `docs/demos/*` | Unchanged GIF/MP4 assets |

**Not done (on purpose):** live posts, amplifier DMs, GitHub topics on public repo, merge to `main`.

---

## How you review

### 1. README (Phase A)

1. Open the PR (or branch) on GitHub → **Files changed** → `README.md` preview.  
2. Or: https://github.com/stefanopineda/quintile/blob/growth%2F500-stars/README.md  
3. Check:
   - [ ] Differentiator clear in first screen (span / N×M, not “tiling app”)  
   - [ ] `grid-select.gif` loads and shows the magic moment  
   - [ ] for / not for + laptop line feel honest  
   - [ ] Install is still **tap** path, not fake official `brew install quintile`  
   - [ ] Soft star CTA under status is OK (not beggarly)  
   - [ ] Tone not too salesy  

**Edit path:** comment on PR or edit `README.md` on this branch.

### 2. Install still works (sanity)

This branch does **not** change the app. Optional:

```bash
brew reinstall --cask stefanopineda/quintile/quintile
# first tile: focus a window, ⌃⌥[
```

### 3. Launch drafts (Phase B)

1. Read `docs/marketing/launch-wave-2.md`.  
2. Preview media: open `docs/demos/grid-select.gif` (primary) and `hero.mp4`.  
3. Check:
   - [ ] Hook is two-cell span first  
   - [ ] Install one-liner correct  
   - [ ] You’re willing to post this text as-is (or mark edits)  

**Do not post until main is merged.**

### 4. Amplifier kit (Phase C)

1. Read `docs/marketing/amplifier-kit.md`.  
2. Fill/adjust the target table with people you actually know or want to contact.  
3. Check DM packet isn’t cringe.  

**Do not send DMs until main is merged and wave posts are ready.**

---

## After you approve

1. Merge this PR → `main` (docs only).  
2. Follow `docs/marketing/post-merge-checklist.md` (topics, social preview, then post order).  
3. You hit Post / Send — agent drafts only.

---

## Reject / revise

- Want shorter README → cut “for / not for” or demote presets GIFs.  
- Want different hook → edit `launch-wave-2.md` master copy.  
- Want zero star CTA → delete the status line in README.
