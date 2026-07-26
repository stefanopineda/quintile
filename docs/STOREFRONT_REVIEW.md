# Storefront staging — review notes

Branch: `docs/storefront-readme`  
Private remote: `stefanopineda/quintile_test`  
Public target after approval: `stefanopineda/quintile` `main`

## What changed vs public main README

1. **Lead with differentiator** — span / N×M placement, not generic “tiling”
2. **for / not for table** — Rectangle, yabai, mouse-snap, SIP boundaries; laptop line
3. **Embed all three existing demos** — grid-select, presets-move, profiles (were unused)
4. **Homebrew metric made explicit** — 225★ path + link to closed PR
5. **Soft star CTA** after value, not above the fold
6. **Install path unchanged** — still third-party tap until official cask

App code, cask, hotkeys, onboarding: **unchanged**.

## How to review

1. Open https://github.com/stefanopineda/quintile_test (private) and read the README render
2. Watch the three GIF embeds load and tell the story without the keys table
3. Check tone: still lean, not a marketing pamphlet
4. Decide ship / tweak / scrap lines

## After you approve

```bash
# from local quintile checkout on docs/storefront-readme (after polish)
git push origin docs/storefront-readme
# open PR into public main, merge when ready
gh pr create -R stefanopineda/quintile --base main --head docs/storefront-readme \
  --title "docs: storefront README for Homebrew notability path" \
  --body "Staged and reviewed on private quintile_test. Docs only."
```

Then on **public** repo only:

```bash
gh repo edit stefanopineda/quintile \
  --add-topic macos --add-topic window-manager --add-topic tiling \
  --add-topic keyboard --add-topic swift --add-topic menu-bar --add-topic accessibility
```

Optional: set a social preview image in GitHub Settings → General → Social preview (hero still).

## Success metric reminder

README quality is intermediate. True success metric:

```text
brew install --cask quintile   # official homebrew/cask
```

requires **≥225 stars** (or 90 forks / 90 watchers) + repo age ≥30 days + resubmit.
See `docs/PATH_TO_HOMEBREW.md`.
