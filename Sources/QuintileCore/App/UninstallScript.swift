import Foundation

/// Clean uninstall helper launched by the menu-bar "Uninstall Quintile…" action.
///
/// The running app cannot reliably delete its own bundle mid-process, so the
/// flow is: confirm → unregister login item → spawn this script detached →
/// quit. The script waits for the process to exit, then:
/// 1. `brew uninstall --cask quintile` when the cask is present
/// 2. Removes leftover `Quintile.app` under `/Applications` or `~/Applications`
/// 3. `tccutil reset Accessibility` for the app's bundle id
///
/// Grid profiles under Application Support are intentionally left alone —
/// reinstall restores a clean app without wiping user grid config.
public enum UninstallScript {
    public static let bundleIdentifier = "com.stefanopineda.quintile"
    public static let processName = "Quintile"
    public static let caskName = "quintile"
    public static let logPath = "/tmp/quintile-uninstall.log"

    /// Bash source for the post-quit uninstall helper. Pure so tests can assert
    /// the command sequence without spawning a shell.
    public static func shellSource(
        bundleIdentifier: String = bundleIdentifier,
        processName: String = processName,
        caskName: String = caskName,
        logPath: String = logPath
    ) -> String {
        // Keep this self-contained: no reliance on the user's interactive shell
        // profile. Homebrew may live under /opt/homebrew (Apple Silicon) or
        // /usr/local (Intel).
        """
        #!/bin/bash
        # Quintile clean uninstall — continues after the app quits.
        set -u
        LOG=\(shellQuote(logPath))
        BUNDLE_ID=\(shellQuote(bundleIdentifier))
        APP_NAME=\(shellQuote(processName))
        CASK=\(shellQuote(caskName))
        : > "$LOG"
        {
          echo "Quintile uninstall started $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

          # Wait for Quintile to fully exit (up to ~15s).
          for _ in $(seq 1 75); do
            if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
              break
            fi
            sleep 0.2
          done

          if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            echo "warning: $APP_NAME still running; continuing anyway"
          fi

          # 1) Homebrew: always force-uninstall + zap when brew is present.
          # A plain `brew uninstall` is not enough if the user deleted
          # /Applications/Quintile.app by hand — brew still has a receipt in
          # Caskroom and `brew install` then says "latest version already
          # installed" with a 0-byte staged version. --force --zap purges
          # the receipt + zap trash list.
          if command -v brew >/dev/null 2>&1; then
            echo "brew uninstall --cask --force --zap $CASK"
            brew uninstall --cask --force --zap "$CASK" 2>&1 \
              || echo "brew uninstall --force --zap failed (continuing)"
            # Belt: remove any leftover Caskroom staging if brew left it.
            for PREFIX in /opt/homebrew /usr/local; do
              CR="$PREFIX/Caskroom/$CASK"
              if [ -d "$CR" ]; then
                echo "rm -rf $CR"
                rm -rf "$CR" || true
              fi
            done
          else
            echo "brew not found on PATH"
          fi

          # 2) Remove leftover app bundles (manual install or incomplete brew)
          killall "$APP_NAME" 2>/dev/null || true
          for APP_PATH in "/Applications/Quintile.app" "$HOME/Applications/Quintile.app"; do
            if [ -e "$APP_PATH" ] || [ -L "$APP_PATH" ]; then
              echo "rm -rf $APP_PATH"
              rm -rf "$APP_PATH" || echo "failed to remove $APP_PATH"
            fi
          done

          # 3) Reset Accessibility grant for this bundle id
          echo "tccutil reset Accessibility $BUNDLE_ID"
          /usr/bin/tccutil reset Accessibility "$BUNDLE_ID" || echo "tccutil reset failed (continuing)"

          echo "Quintile uninstall finished $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } >>"$LOG" 2>&1

        /usr/bin/osascript -e 'display notification "Quintile has been uninstalled." with title "Quintile"' >/dev/null 2>&1 || true
        """
    }

    /// Writes `shellSource()` to a unique temp file and returns its path.
    /// Caller is responsible for launching it and then terminating the app.
    public static func writeTemporaryScript(
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("quintile-uninstall-\(UUID().uuidString).sh",
                                    isDirectory: false)
        let source = shellSource()
        try source.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func shellQuote(_ value: String) -> String {
        // Single-quote wrap with POSIX escaping of embedded single quotes.
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
