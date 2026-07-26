# Path to official `brew install --cask quintile`

**Why this exists:** shorter install and easier discovery for people who already use Homebrew.  
**What we optimize for:** utility, ease of use, ease of discoverability — not vanity counters.

Official homebrew/cask is a *distribution* goal. It is not a scoreboard.

---

## Current install (correct and complete)

```bash
brew install --cask stefanopineda/quintile/quintile
```

Tap: https://github.com/stefanopineda/homebrew-quintile  

Same binary as a future official cask. Keep this path working until (and for a while after) official inclusion.

---

## What Homebrew requires (their policy, not our product metric)

From [Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy#notability) and the closed self-submission [homebrew-cask#274471](https://github.com/Homebrew/homebrew-cask/pull/274471):

Homebrew gates new self-submitted casks on public evidence of interest (their inclusion policy). They closed the prior PR with: resubmit when the project meets requirements.

Also relevant:

| Check | Quintile |
|-------|----------|
| Repo age (normally ≥30 days) | Created 2026-07-08 → eligible ≈ 2026-08-07 |
| Stable notarized release zip | Met (v0.1.6+) |
| Cask shape / install-uninstall | Met (`Casks/quintile.rb` + tap) |
| No SIP / Gatekeeper disable | Met |

**Implication:** official cask follows when the project is used and found. We do not chase inclusion metrics as the product goal. We ship something useful, make install and first-tile easy, make the differentiator obvious — then resubmit when Homebrew’s bar is met.

Checklist before resubmit (packaging only):

- [ ] Repo age ≥ 30 days  
- [ ] Homebrew’s inclusion bar met (see their docs / prior maintainer note)  
- [ ] Latest release signed + notarized; sha256 matches cask  
- [ ] `brew audit --cask --online --new quintile` clean  
- [ ] Install / uninstall / zap verified  
- [ ] Full PR template filled (incomplete template auto-closed last time)

After merge: README primary install becomes `brew install --cask quintile`; keep tap as fallback briefly.

---

## What actually moves install ease and discovery

1. **First tile works** — Accessibility loop + coach (already strong)  
2. **Landing page shows the differentiator** — span picker demos on README  
3. **One clear install command** — tap until official cask  
4. **Tell the right people once the above is true** — not the reverse  

Features for scoreboard reasons: out of scope.
