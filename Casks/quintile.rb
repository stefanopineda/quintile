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
  version "0.1.4"
  sha256 "040c5c064ddccf2fb658de3232b6a75b95c1fc5b3851057057a128e1c99380d6"

  url "https://github.com/stefanopineda/quintile/releases/download/v#{version}/Quintile.app.zip"
  name "Quintile"
  desc "Keyboard-only N×M grid window tiling"
  homepage "https://github.com/stefanopineda/quintile"

  depends_on macos: :sonoma

  app "Quintile.app"

  # Homebrew 6 force-quarantines every cask install and no longer offers a
  # --no-quarantine opt-out, so an unsigned (un-notarized) build is blocked on
  # first launch ("could not verify free of malware"). Since this is your own
  # app installed from your own tap, clear the quarantine flag on install so it
  # launches. A future Developer ID-signed + notarized build makes this moot.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Quintile.app"]
  end

  caveats <<~EOS
    Quintile is unsigned and not yet notarized, but this cask already cleared
    the Gatekeeper quarantine flag for you — no action needed to launch it.

    Fallback (only if macOS still blocks it, or you downloaded the .zip
    directly instead of using brew):
      xattr -dr com.apple.quarantine /Applications/Quintile.app
      (or System Settings → Privacy & Security → Open Anyway)

    One remaining manual step — grant Accessibility so hotkeys work:
      System Settings → Privacy & Security → Accessibility → enable Quintile
  EOS
end
