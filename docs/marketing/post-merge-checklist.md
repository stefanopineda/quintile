# After merge (`docs/storefront-discoverability` → `main`)

Only when you are happy with the storefront.

## 1. Discoverability knobs (optional, public repo)

```bash
gh repo edit stefanopineda/quintile \
  --add-topic macos \
  --add-topic window-manager \
  --add-topic tiling \
  --add-topic keyboard \
  --add-topic swift \
  --add-topic menu-bar \
  --add-topic accessibility
```

- [ ] Social preview: Settings → General → Social preview  
  Prefer a still of the grid span (so shares show the product, not a blank default).

## 2. Confirm live README

- [ ] https://github.com/stefanopineda/quintile shows demos + differentiator  
- [ ] Install command is the tap path  
- [ ] No vanity-metric language  

## 3. Announce only when ready (you post)

Copy: `docs/marketing/launch-wave-2.md`

- [ ] X + media (if you want)  
- [ ] r/MacApps (if you want)  
- [ ] Reply to real questions for a day or two  

## 4. Optional outreach

- [ ] Edit `docs/marketing/amplifier-kit.md`  
- [ ] Send only warm / high-fit notes  

## 5. Watch utility signals (not a scoreboard)

```bash
gh api repos/stefanopineda/quintile/traffic/views --jq '{count,uniques}'
gh api repos/stefanopineda/quintile/traffic/popular/referrers
gh api repos/stefanopineda/quintile/releases/latest --jq '.assets[] | {name,download_count}'
```

Also: Issues and real replies — can people install and get a first tile?
