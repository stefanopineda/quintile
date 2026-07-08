# Homebrew cask for Quintile.
#
# Lives in this repo as the source of truth; published via the
# stefanopineda/homebrew-quintile tap (copy on release). The sha256 below is
# updated by the release process for each versioned artifact — run
# `brew audit --cask quintile` from the tap after updating.
cask "quintile" do
  version "0.1.0"
  sha256 :no_check # replaced with the artifact digest on first tagged release

  url "https://github.com/stefanopineda/quintile/releases/download/v#{version}/Quintile.app.zip"
  name "Quintile"
  desc "Keyboard-only N×M grid window tiling"
  homepage "https://github.com/stefanopineda/quintile"

  depends_on macos: ">= :sonoma"

  app "Quintile.app"

  caveats <<~EOS
    Quintile needs Accessibility permission:
      System Settings → Privacy & Security → Accessibility → enable Quintile
  EOS
end
