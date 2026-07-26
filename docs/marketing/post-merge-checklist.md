# Post-merge checklist (only after you merge `growth/500-stars` → `main`)

## 1. Storefront knobs (public repo settings)

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

- [ ] Social preview image: GitHub → Settings → General → Social preview  
  Use a still from `docs/demos/grid-select.gif` or hero (upload PNG ~1280×640).

## 2. Confirm live README

- [ ] https://github.com/stefanopineda/quintile shows demos + differentiator  
- [ ] Install command still tap path  

## 3. Launch wave (you post)

Order from `docs/marketing/launch-wave-2.md`:

- [ ] X + media  
- [ ] r/MacApps  
- [ ] Optional second sub / Show HN  
- [ ] Reply window 24–48h  

## 4. Amplifiers (you send)

- [ ] Edit table in `docs/marketing/amplifier-kit.md`  
- [ ] Send warm 3 first  

## 5. Metrics (48h later)

```bash
gh api repos/stefanopineda/quintile --jq '{stars:.stargazers_count,forks:.forks_count,watchers:.subscribers_count}'
gh api repos/stefanopineda/quintile/traffic/views --jq '{count,uniques}'
gh api repos/stefanopineda/quintile/traffic/popular/referrers
```

Log into `launch-wave-2.md` metrics table.
