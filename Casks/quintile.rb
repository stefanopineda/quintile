cask "quintile" do
  version "0.1.8"
  sha256 "dba940767f216f97628eb3284cf7c857fe1fa4c998f640e97cb6f7120776d682"

  url "https://github.com/stefanopineda/quintile/releases/download/v#{version}/Quintile.app.zip"
  name "Quintile"
  desc "Keyboard-only N×M grid window tiling"
  homepage "https://github.com/stefanopineda/quintile"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Quintile.app"

  # Quit before brew removes the bundle (avoids orphan process + half-uninstall).
  uninstall quit: "com.stefanopineda.quintile"

  # Kill any leftover process (common after reinstall while old binary still
  # runs), then launch so first-run coach is not skipped.
  postflight do
    system_command "/usr/bin/killall",
                   args: ["Quintile"],
                   must_succeed: false
    system_command "/bin/sleep", args: ["0.4"]
    system_command "/usr/bin/open",
                   args: ["-a", "#{appdir}/Quintile.app", "--args", "--first-run"]
  end

  zap trash: [
    "~/Library/Application Support/Quintile",
    "~/Library/Preferences/com.stefanopineda.quintile.plist",
  ]

  caveats <<~EOS
    NEXT STEPS
      1. A Quintile window should appear on screen (first-run coach or
         Accessibility prompt). Look for ⊞! / ⊞ in the menu bar — no Dock icon.
      2. If nothing appeared: Spotlight (⌘Space) → Quintile → Enter
      3. Accessibility: turn Quintile ON (if already ON: OFF then ON),
         then Check Again if the window still asks.
      4. Click a window, hold Control+Option, press [  (left third).

    Full map later: menu bar ⊞ → Quick Start…
  EOS
end
