# Plan: Quintile → 500 stars (three high-ROI moves)

Created: 2026-07-26

**Target repo:** `stefanopineda/quintile` (public)  
**Staging:** `stefanopineda/quintile_test` (private) — README polish only  
**Success metric (north star):** 500 public GitHub stars  
**Secondary (Homebrew gate):** ≥225 stars + repo age ≥30 days (~2026-08-07) → resubmit `homebrew-cask` for `brew install --cask quintile`  
**Current baseline (2026-07-26):** ~20 stars · ~3 forks · ~3 watchers · 0 issues · Discussions off · X intro post ~77 views · HN 11 pts / ~331 unique referrers  

**What this plan is:** exact execution runbook for the three agreed moves — not new product features.  
**What this plan is not:** app code, onboarding rewrites, in-app tutorials, official Homebrew PR before threshold.

**Posting rule:** drafts live offline or in repo files. Human (Stef) hits Post / Submit. No multi-step browser automation on the daily machine.

---

## Scope (the three moves)

| # | Move | Job |
|---|------|-----|
| **A** | Public README = 5-second demo reel | Convert lookers → installers/starers |
| **B** | Second launch wave (differentiator-first) | Create attention with the right hook |
| **C** | One external amplifier | Borrow distribution you don't have yet |

**Hard sequence:** A → B → C (README must be live before traffic; amplifiers need a sharp landing page + clip).

**Out of scope:** feature work, remapping, Intel builds, Discord, in-app feedback product, Discussions (optional side door only — not a star lever).

---

## Assumptions

- Storefront README on branch `docs/storefront-readme` / private `quintile_test` is the base (already drafted).
- Demo assets already exist: `docs/demos/hero.gif`, `grid-select.gif`, `presets-move.gif`, `profiles.gif`, `hero.mp4`.
- Stef owns final post approval and sends amplifier DMs.
- No paid ads in this plan.
- 500 is aspirational; 225 unlocks official Homebrew — track both.

---

## Phase A — Public README demo reel (Day 0)

**Goal:** Anyone who lands on the repo understands the *span picker* in &lt;5 seconds and can install in one command.

### A1. Review staging copy (you)

1. Open private repo: https://github.com/stefanopineda/quintile_test  
2. Read rendered `README.md` on private `main`.  
3. Check these four beats exist and load:
   - Differentiator headline (N×M / span — not “another tiler”)
   - `docs/demos/grid-select.gif` (magic moment)
   - for / not for + laptop line
   - `brew install --cask stefanopineda/quintile/quintile` still primary
4. Mark nits (tone, length, any line that feels salesy).  
5. **Done when:** you say “ship” or paste a short edit list.

### A2. Apply polish (agent or you)

1. Edit only: `README.md` (optional: one soft CTA line under status).  
2. Do **not** change app sources, cask, or hotkeys.  
3. Keep lean: if a section doesn’t help install or star, cut it.  
4. **Done when:** local preview matches “5-second demo reel” standard (hero + grid-select visible without scrolling past the fold on a laptop browser if possible).

### A3. Merge to public `main`

1. On local `quintile`, ensure branch has the approved README.  
2. Open PR into public `stefanopineda/quintile` `main` (docs-only).  
3. Merge after green / visual check on PR preview.  
4. Confirm live: https://github.com/stefanopineda/quintile  
5. **Done when:** public README shows all three GIFs + differentiator lead.

### A4. Public storefront knobs (same day as merge)

1. Set GitHub **topics** (Settings or `gh repo edit`):  
   `macos`, `window-manager`, `tiling`, `keyboard`, `swift`, `menu-bar`, `accessibility`  
2. Set **Social preview** image: still from hero or grid-select (Settings → General → Social preview).  
3. Optional one-liner under status:  
   `First-run notes or bugs → Issues. If the span picker stuck, a star helps Homebrew notability.`  
4. **Done when:** share card on X/Slack shows product visual, not blank GH default.

### A5. Phase A verification

| Check | Pass |
|-------|------|
| Cold open public README | Grid-select story clear without reading keys table |
| Install command copy-pasteable | Tap path works |
| Mobile GH | GIFs load; not wall of text only |
| No official `brew install quintile` claimed | Only tap + “blocked on notability” note |

**Gate:** Do not start Phase B until A3 is live.

---

## Phase B — Second launch wave (Days 1–3 after A)

**Goal:** One coordinated blast with a single hook: **two-cell span**, not generic tiling.

### B1. Assets checklist (prepare before any post)

| Asset | Source | Use |
|-------|--------|-----|
| Primary clip | `docs/demos/grid-select.gif` or re-export short MP4 of G + two cells | X / Reddit |
| Backup | `docs/demos/hero.mp4` (~15s) | If grid-select too long/heavy |
| Install line | `brew install --cask stefanopineda/quintile/quintile` | Every post |
| Repo URL | `https://github.com/stefanopineda/quintile` | Every post |
| Drafts folder (optional) | e.g. `docs/marketing/launch-wave-2.md` | Offline drafts only |

### B2. Final post copy (freeze before Day 1)

Use **one** master message; adapt length per channel. Differentiator first.

**Master (short):**

```text
Most Mac tilers stop at halves and thirds.

Quintile: keyboard-only N×M grid placement.
⌃⌥G → two cells → window spans that rectangle.

No auto-tiling. No SIP. Accessibility only.
MIT · signed & notarized

brew install --cask stefanopineda/quintile/quintile
https://github.com/stefanopineda/quintile
```

**Reddit / longer (add):**

```text
Laptop users: start with thirds (⌃⌥[ ] \). 5×2 shines with width (external/ultrawide).
Not a yabai/AeroSpace replacement — you place windows; nothing auto-rearranges.
```

**HN comment body (if Show HN):** same longer form + honest “not Spaces/yabai stack substitute on 16" laptop alone.”

### B3. Channel sequence (fixed order)

Do **not** post everywhere at once before README is live. After A:

| Step | When | Where | Action |
|------|------|-------|--------|
| B3.1 | Day 1 morning | **X** | Human posts master + grid-select media. Reply to own thread with install one-liner if needed. |
| B3.2 | Day 1 midday | **Reddit r/MacApps** | Title: keyboard N×M grid placement (not auto-tiling). Body = longer copy + GIF. Follow sub rules (no spam, flair if required). |
| B3.3 | Day 1 afternoon | **Reddit r/MacOS** or **r/macapps** only if first post is clean | Same asset; do not crosspost-spam three subs same hour. Prefer quality + replies. |
| B3.4 | Day 2–3 | **Show HN** (optional second chance) | Title: `Show HN: Place any Mac window on any grid span in two keypresses`. Link repo. Stay for comments 1–2h. Answer laptop pushback with thirds + when 5×2 helps. |
| B3.5 | Same week | **Mastodon / Bluesky** (if accounts exist) | Cross-post short master once. Low effort. |

**Explicitly skip for wave 2:** Product Hunt (prep cost), paid boost, unsolicited mass DMs.

### B4. Engagement protocol (during wave)

For each channel, for 24–48h after post:

1. Reply to every serious comment within a few hours.  
2. Laptop skepticism → thirds first + external display pitch (do not argue).  
3. “How vs Rectangle?” → complement for arbitrary spans; Rectangle fine for halves.  
4. Install fails → Accessibility OFF→ON + Check Again; link README after-install.  
5. Do **not** beg for stars in replies; soft CTA only in README.

### B5. Measure (end of Day 3)

```bash
gh api repos/stefanopineda/quintile --jq '{stars:.stargazers_count,forks:.forks_count,watchers:.subscribers_count}'
gh api repos/stefanopineda/quintile/traffic/views --jq '{count,uniques}'
gh api repos/stefanopineda/quintile/traffic/popular/referrers
gh api repos/stefanopineda/quintile/releases/latest --jq '.assets[] | {name,download_count}'
```

| Metric | Log |
|--------|-----|
| Stars (start / end wave) | |
| Unique views (2–3d) | |
| Top referrers | |
| Latest zip downloads | |
| Which channel produced comments | |

**Gate:** Start Phase C outreach during B if possible (parallel), but personalized links must point at **post-A** README.

---

## Phase C — External amplifiers (Days 1–14, overlapping B)

**Goal:** One share from an account with reach &gt; your own. One good amp beats ten solo posts.

### C1. Build a target list (10 names max)

Pick people who already talk about **Mac window management / Rectangle / yabai / AeroSpace / Hammerspoon / keyboard-driven Mac workflow**. Not random big tech accounts.

| # | Handle / site | Why them | Warm? (Y/N) | Status |
|---|---------------|----------|-------------|--------|
| 1 | | | | |
| 2 | | | | |
| … | | | | |
| 10 | | | | |

Sources to mine (manual): Twitter/X lists, Mac Power Users guests, authors of Rectangle/yabai comparison posts, newsletter writers (MacStories-adjacent indie, not only corporate).

**Cap:** 10. Do not spray 50.

### C2. Packet (same for everyone)

Prepare once:

1. **20s clip** (grid-select) — link or attach  
2. **One sentence differentiator:** “Keyboard N×M span picker — two keys place any rectangle; no SIP, no auto-tile.”  
3. **Install:** brew one-liner  
4. **Repo:** URL  
5. **Ask:** soft — “If this is useful to your audience, a share would mean a lot; happy to answer Qs.” Not “please star.”

### C3. Outreach cadence

| Day | Action |
|-----|--------|
| After A live | Send **3** warmest contacts first (people who know you or engaged before) |
| +2 days | Send next **3** if no reply yet on first batch |
| +2 days | Final **4** only if first 6 weren’t enough signal |
| Ongoing | If someone shares: thank publicly once; answer their audience’s questions |

**Channel order for DMs:** X DM if open → email if public → mutual friend intro. No LinkedIn spam blast.

### C4. What counts as “amplifier success”

- Any of: quote-tweet / newsletter blurb / blog mention / YouTube short / podcast aside  
- **Not required:** they star the repo  
- Track: who shared, approx follower reach, star delta 48h after share

### C5. If zero amplifiers bite (contingency)

1. Do **not** add features to “earn” shares.  
2. Run a **third wave** 2–3 weeks later with a *new* angle (e.g. multi-monitor `⌃⌥N` + profiles GIF), same README.  
3. Engage in existing threads about Rectangle limitations / yabai SIP pain — helpful answers + link only when relevant (no drive-by spam).  
4. Reassess at 30 days: stars trajectory vs 225 / 500.

---

## Weekly operating cadence (until 225, then until 500)

| Cadence | Action |
|---------|--------|
| **Weekly** | Log stars, downloads, top referrer (`gh api` traffic) |
| **Biweekly** | One small distribution action (reply wave, one amp DM, one demo post) — not a feature release |
| **When ≥225 and age ≥30d** | Resubmit homebrew-cask (full PR template; see `docs/PATH_TO_HOMEBREW.md`) |
| **When official cask merges** | Flip README primary install to `brew install --cask quintile`; keep tap as fallback one release |

---

## Execution checklist (single page)

### Day 0 — Phase A
- [ ] A1 Review private storefront README  
- [ ] A2 Polish nits  
- [ ] A3 PR + merge to public `main`  
- [ ] A4 Topics + social preview  
- [ ] A5 Verification table pass  

### Days 1–3 — Phase B
- [ ] B1 Assets ready (grid-select primary)  
- [ ] B2 Copy frozen  
- [ ] B3.1 X post (human)  
- [ ] B3.2 r/MacApps  
- [ ] B3.3 Optional second sub (not same hour)  
- [ ] B3.4 Optional Show HN  
- [ ] B4 Reply window 24–48h  
- [ ] B5 Metrics logged  

### Days 1–14 — Phase C
- [ ] C1 List of ≤10 amplifiers  
- [ ] C2 Packet ready  
- [ ] C3 Send warm 3 → next 3 → last 4  
- [ ] C4 Log any shares + star delta  
- [ ] C5 Contingency only if needed  

---

## Risks and how this plan absorbs them

| Risk | Mitigation |
|------|------------|
| Traffic without conversion | Phase A first — demos + for/not-for |
| HN laptop skepticism again | Copy owns thirds-first; don’t oversell 5×2 on 16" |
| X low reach again | Don’t rely on X alone; Reddit + amp |
| Amp silence | Cap effort at 10 DMs; third wave angle later |
| Scope creep into features | Explicit out-of-scope; stars ≠ new modes |
| Begging for stars | Soft CTA after value only; never in amp DMs |

---

## Definition of done (for *this plan*)

This execution plan is **done** when:

1. Public README is the demo-reel version (Phase A complete).  
2. Launch wave posts have been published and metrics logged (Phase B complete).  
3. ≤10 amplifier outreaches sent (or intentionally stopped after warm batch) (Phase C complete).  

**500 stars** is the *campaign goal*, not the exit criterion of a single week’s checklist. Reassess after A+B+C: if trajectory is flat, change distribution angle — not product surface.

---

## References (in-repo)

- `docs/PATH_TO_HOMEBREW.md` — official cask threshold and resubmit checklist  
- `docs/STOREFRONT_REVIEW.md` — storefront README delta vs old lean README  
- `docs/demos/*` — ship assets  
- Closed cask PR context: Homebrew self-submit ≥225★ / 90 forks / 90 watchers  
