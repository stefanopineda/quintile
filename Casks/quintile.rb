# Homebrew cask for Quintile.
#
# Lives in this repo as the source of truth; published via the
# stefanopineda/homebrew-quintile tap (copy on release). The sha256 is the
# digest of the release's Quintile.app.zip; bump version + sha256 together
# on each release and run `brew audit --cask quintile` from the tap.
#
# The artifact is an unsigned, ad-hoc-signed build (no Developer ID yet).
# Homebrew applies the Gatekeeper quarantine flag on install by default, so
# macOS blocks the first launch ("could not verify free of malware"). Users
# clear it once: install with `--no-quarantine`, or run
# `xattr -dr com.apple.quarantine "$(brew --caskroom)/../../Applications/Quintile.app"`,
# or use System Settings > Privacy & Security > Open Anyway. See caveats.
cask "quintile" do
  version "0.1.0"
  sha256 "2df0c5f74c5830809fee1cd921f22d10a5e4cc22691f8ce73ecc68c0ec61fd24"

  url "https://github.com/stefanopineda/quintile/releases/download/v#{version}/Quintile.app.zip"
  name "Quintile"
  desc "Keyboard-only N×M grid window tiling"
  homepage "https://github.com/stefanopineda/quintile"

  depends_on macos: :sonoma

  app "Quintile.app"

  caveats <<~EOS
    Quintile is not yet notarized, so macOS Gatekeeper blocks the first launch
    ("Apple could not verify Quintile is free of malware"). Clear it once with:

      xattr -dr com.apple.quarantine /Applications/Quintile.app

    (or reinstall with `--no-quarantine`, or use System Settings →
    Privacy & Security → Open Anyway). Then grant Accessibility:

      System Settings → Privacy & Security → Accessibility → enable Quintile
  EOS
end
