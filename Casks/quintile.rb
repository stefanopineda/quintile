cask "quintile" do
  version "0.1.7"
  sha256 "844d252457d784c2f60bd40ea4cedeae5b9f69c75afe92f8bc43a40fd736355d"

  url "https://github.com/stefanopineda/quintile/releases/download/v#{version}/Quintile.app.zip"
  name "Quintile"
  desc "Keyboard-only N×M grid window tiling"
  homepage "https://github.com/stefanopineda/quintile"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Quintile.app"

  # Launch so first-run onboarding + Accessibility deep link appear without
  # hunting Spotlight. Menu bar only (no Dock icon).
  postflight do
    system_command "/usr/bin/open",
                   args: ["-a", "#{appdir}/Quintile.app"]
  end

  zap trash: [
    "~/Library/Application Support/Quintile",
    "~/Library/Preferences/com.stefanopineda.quintile.plist",
  ]

  caveats <<~EOS
    NEXT STEPS
      1. Quintile should have launched. Look for ⊞! / ⊞ in the menu bar
         (near the clock) — there is no Dock icon. That is normal.
      2. If it did not open: Spotlight (⌘Space) → type Quintile → Enter
      3. System Settings → Privacy & Security → Accessibility → turn
         Quintile ON. If it already looks ON, turn OFF then ON again,
         then click Check Again in the Quintile window.
      4. Click a window, hold Control+Option, press [  (left third).

    Full shortcut map later: menu bar ⊞ → Quick Start…
  EOS
end
