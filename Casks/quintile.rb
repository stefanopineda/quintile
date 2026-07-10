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
  version "0.1.1"
  sha256 "bfe789a4e1b72f0fa69a946a8eb90534492eb6bbc0f86088b8d6af82dc0e546d"

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
    Quintile is not yet notarized. This cask clears the Gatekeeper quarantine
    flag on install so it launches. If macOS still blocks it (or you downloaded
    the app manually), clear it yourself once:

      xattr -dr com.apple.quarantine /Applications/Quintile.app

    or use System Settings → Privacy & Security → Open Anyway.

    Then grant Accessibility:
      System Settings → Privacy & Security → Accessibility → enable Quintile
  EOS
end
