# Homebrew cask for Quintile.
#
# Lives in this repo as the source of truth; published via the
# stefanopineda/homebrew-quintile tap (copy on release). The sha256 is the
# digest of the release's Quintile.app.zip; bump version + sha256 together
# on each release and run `brew audit --cask quintile` from the tap.
#
# The artifact is an unsigned, ad-hoc-signed build (no Developer ID yet).
# Homebrew removes the quarantine flag on cask install, so Gatekeeper does
# not block it; a direct browser download needs a one-time "Open Anyway"
# in System Settings > Privacy & Security.
cask "quintile" do
  version "0.1.0"
  sha256 "4d048cf6b18ff4e4665f28b3d271f89c127e584c84c5bc8aa83dae28cb7164be"

  url "https://github.com/stefanopineda/quintile/releases/download/v#{version}/Quintile.app.zip"
  name "Quintile"
  desc "Keyboard-only N×M grid window tiling"
  homepage "https://github.com/stefanopineda/quintile"

  depends_on macos: :sonoma

  app "Quintile.app"

  caveats <<~EOS
    Quintile needs Accessibility permission:
      System Settings → Privacy & Security → Accessibility → enable Quintile
  EOS
end
