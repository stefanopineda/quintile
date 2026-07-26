# Path to `brew install --cask quintile`

**Success metric:** official Homebrew Cask so users can run:

```bash
brew install --cask quintile
```

without a third-party tap.

This file is the working plan for that metric. Product polish matters only insofar as it moves notability and keeps the cask shippable.

---

## What Homebrew actually requires

From [Package Acceptance Policy — Notability](https://docs.brew.sh/Package-Acceptance-Policy#notability) and the closed self-submission [homebrew-cask#274471](https://github.com/Homebrew/homebrew-cask/pull/274471):

| Rule | Status for Quintile |
|------|---------------------|
| Self-submission needs **≥225 stars**, **or ≥90 forks**, **or ≥90 watchers** (any one) | **20 stars · 3 forks · 3 watchers** — blocked |
| Canonical upstream is the GitHub repo (not a mirror) | Met: `stefanopineda/quintile` |
| Repo normally **≥30 days old** | Created **2026-07-08** → eligible ≈ **2026-08-07** |
| Stable version, verifiable upstream zip | Met (GitHub Releases) |
| Developer ID + notarized (no Gatekeeper disable) | Met as of v0.1.6+ |
| `brew audit --cask --new` clean once notable | Cask shape already exists in `Casks/quintile.rb` + tap |

Maintainer reply on the PR:

> You may resubmit once the project meets the requirements for inclusion.

There is no alternate “quality of README” gate that substitutes for the numbers. README quality **feeds** stars/installs; it does not replace the threshold.

**Realistic lever:** stars. 90 forks or 90 watchers is harder for a single-app menu-bar tool than 225 stars.

**Non-self-submission bar** is lower (75★ / 30 forks / 30 watchers), but if the author (or obvious author PR) submits, Homebrew applies the **self-submission** bar. Don’t plan around gaming that.

---

## Current install path (interim)

```bash
brew install --cask stefanopineda/quintile/quintile
```

Tap: https://github.com/stefanopineda/homebrew-quintile  

This is the correct product until official cask lands. Do not remove the tap early.

---

## Funnel that moves the metric

```
discover (HN / X / Reddit / search)
  → land on README (understand differentiator in <5s)
    → install from tap
      → Accessibility + first third works
        → grid span “oh damn” moment
          → star / tell a friend
            → … → 225★
              → resubmit homebrew-cask
                → brew install --cask quintile
```

**Levers ranked for the metric:**

1. **Distribution waves** that show the *span picker*, not “another tiler”
2. **README storefront** (differentiator, demos, for/not-for) — this staging branch
3. **Zero install friction** — already strong (notarized, postflight, coach)
4. **New features** — weak lever for stars unless they create a shareable moment
5. **In-app tutorial video / wizards** — high effort, low notability impact

---

## Checklist before resubmitting homebrew-cask

- [ ] Repo age ≥ 30 days
- [ ] `stargazers_count ≥ 225` **or** forks ≥ 90 **or** watchers ≥ 90  
      (`gh api repos/stefanopineda/quintile --jq '{s:.stargazers_count,f:.forks_count,w:.subscribers_count}'`)
- [ ] Latest release signed + notarized; zip sha256 matches cask
- [ ] Cask token `quintile` still free / not refused for other reasons
- [ ] `brew audit --cask --online --new quintile` clean on a PR branch
- [ ] Install / uninstall / zap verified once more
- [ ] Resubmit with full PR template (incomplete template auto-closed last time)

After merge: point README primary install at `brew install --cask quintile`, keep tap as fallback for a release or two, then deprecate tap docs.

---

## Staging workflow (this private repo)

| Repo | Role |
|------|------|
| `stefanopineda/quintile_test` (private) | Polish README / storefront; review before public |
| `stefanopineda/quintile` (public) | Canonical upstream Homebrew will measure |
| `stefanopineda/homebrew-quintile` | Interim tap |

1. Review README + demos on `quintile_test`
2. Merge accepted copy into public `quintile` `main`
3. Set public repo **topics** + social preview (only matter on public)
4. Run distribution; reassess stars weekly against 225
5. On threshold + age: open new homebrew-cask PR (don’t reopen 274471)

**Do not** expect private-repo traffic to move stars. Performance evaluation after merge is on the **public** repo’s Insights → Traffic and star count.

---

## What we are not doing for this metric

- Waiting on Intel builds, remapping, auto-tile modes
- Multi-page in-app tours
- Treating official Homebrew as a discovery channel (they explicitly are not)

The metric is a **popularity threshold + clean packaging**. Packaging is done. Popularity is the work.
