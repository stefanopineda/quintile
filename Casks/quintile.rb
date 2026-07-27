cask "quintile" do
  version "0.1.9"
  sha256 "6b008f715976c4772e500d086be123a0c3a5480bf27268566963f9db068f5577"

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

  # Kill leftover process, clear quarantine (reduces Gatekeeper “downloaded
  # from the Internet” on first open for brew installs), then launch with
  # first-run coach.
  postflight do
    system_command "/usr/bin/killall",
                   args: ["Quintile"],
                   must_succeed: false
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Quintile.app"],
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
      1. Look for ⊞! / ⊞ in the menu bar (no Dock icon). A Quintile window
         should appear — use Open System Settings there if asked.
      2. If nothing appeared: Spotlight (⌘Space) → Quintile → Enter
      3. In Accessibility, turn Quintile ON (if already ON: OFF then ON),
         then Check Again if the window still asks.
      4. Click Terminal, Finder, or Safari — not the coach window —
         hold Control+Option, press [  (left third).

    Full map later: menu bar ⊞ → Quick Start…
  EOS
end
