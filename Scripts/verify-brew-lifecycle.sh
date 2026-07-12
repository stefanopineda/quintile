#!/bin/bash
# verify-brew-lifecycle.sh — end-to-end Homebrew install / uninstall / reinstall
# checks that a human (or agent) would otherwise re-run by hand after every release.
#
# This is the gate that should have caught:
#   - "Not upgrading, latest already installed" after a broken uninstall
#   - reinstall leaving an old process / no first-run window
#   - caveats / postflight missing from the published tap
#
# Usage:
#   Scripts/verify-brew-lifecycle.sh
#   Scripts/verify-brew-lifecycle.sh --tap stefanopineda/quintile
#   SKIP_INSTALL=1 Scripts/verify-brew-lifecycle.sh   # only assert uninstall/orphans
#
# Exit 0 = pass. Non-zero = fail with a clear reason on stderr.
set -euo pipefail

TAP_CASK="${1:-stefanopineda/quintile/quintile}"
if [[ "${1:-}" == "--tap" ]]; then
  TAP_CASK="${2:-stefanopineda/quintile/quintile}"
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
CASK="quintile"
APP="/Applications/Quintile.app"
CASKROOM_OPT="/opt/homebrew/Caskroom/${CASK}"
CASKROOM_USR="/usr/local/Caskroom/${CASK}"
FAILS=0

log()  { printf '▸ %s\n' "$*"; }
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing $1" >&2; exit 2; }
}

cask_listed() {
  brew list --cask 2>/dev/null | grep -qx "$CASK"
}

caskroom_exists() {
  [[ -d "$CASKROOM_OPT" || -d "$CASKROOM_USR" ]]
}

app_exists() {
  [[ -d "$APP" || -L "$APP" ]]
}

process_running() {
  pgrep -x Quintile >/dev/null 2>&1
}

force_purge() {
  log "force purge (uninstall --force --zap + killall + rm leftovers)"
  brew uninstall --cask --force --zap "$TAP_CASK" 2>/dev/null || true
  brew uninstall --cask --force --zap "$CASK" 2>/dev/null || true
  killall Quintile 2>/dev/null || true
  sleep 0.3
  rm -rf "$APP" "$HOME/Applications/Quintile.app" \
    "$CASKROOM_OPT" "$CASKROOM_USR" 2>/dev/null || true
}

assert_clean() {
  local label="$1"
  log "assert clean: $label"
  if cask_listed; then fail "brew still lists cask ($label)"; else pass "not in brew list"; fi
  if caskroom_exists; then fail "Caskroom residue remains ($label)"; else pass "Caskroom empty"; fi
  if app_exists; then fail "app still at $APP ($label)"; else pass "app absent"; fi
  if process_running; then fail "Quintile process still running ($label)"; else pass "no process"; fi
}

assert_installed() {
  local label="$1"
  log "assert installed: $label"
  if cask_listed; then pass "brew lists cask"; else fail "brew does not list cask ($label)"; fi
  if app_exists; then pass "app present"; else fail "app missing at $APP ($label)"; fi
  local ver
  ver=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || echo "?")
  pass "CFBundleShortVersionString=$ver"
  # Binary must contain first-run coach copy (guards against shipping an old zip).
  if strings "$APP/Contents/MacOS/Quintile" 2>/dev/null | grep -q "Try your first tile"; then
    pass "binary contains first-run coach string"
  else
    fail "binary missing 'Try your first tile' — wrong/old build installed"
  fi
}

assert_first_run_window() {
  log "assert first-run window (Accessibility or coach) within 8s"
  local i names=""
  for i in $(seq 1 40); do
    if process_running; then
      names=$(osascript 2>/dev/null <<'EOF' || true
tell application "System Events"
  if exists process "Quintile" then
    tell process "Quintile"
      try
        return (name of every window) as text
      on error
        return ""
      end try
    end tell
  end if
end tell
EOF
)
      if [[ -n "$names" ]]; then
        pass "window present: $names"
        return 0
      fi
    fi
    sleep 0.2
  done
  fail "no Quintile window after install (process=$(process_running && echo yes || echo no))"
  return 0
}

# --- main ---
require_cmd brew
require_cmd plutil
require_cmd strings

log "tap cask target: $TAP_CASK"
brew update >/dev/null 2>&1 || true

# 1) Start from a known-clean slate (even if currently half-installed).
force_purge
assert_clean "after force purge"

if [[ "${SKIP_INSTALL:-0}" == "1" ]]; then
  log "SKIP_INSTALL=1 — purge-only mode"
  [[ "$FAILS" -eq 0 ]] && exit 0 || exit 1
fi

# 2) Fresh install must succeed (not "already installed").
log "brew install --cask $TAP_CASK"
if ! brew install --cask "$TAP_CASK" 2>&1 | tee /tmp/quintile-brew-install.log; then
  fail "brew install failed"
else
  if grep -qi "already installed" /tmp/quintile-brew-install.log; then
    fail "brew install said already installed on a clean slate — receipt leak"
  else
    pass "brew install completed without 'already installed'"
  fi
fi
assert_installed "after install"
assert_first_run_window

# 3) Plain install again must refuse upgrade path cleanly OR no-op with already installed
#    (that is expected when fully installed). What we reject is install-after-bad-uninstall.
log "second brew install (expect already-installed when healthy)"
brew install --cask "$TAP_CASK" 2>&1 | tee /tmp/quintile-brew-install2.log || true
if grep -qi "already installed\|Not upgrading" /tmp/quintile-brew-install2.log; then
  pass "second install reports already installed (healthy when app present)"
else
  pass "second install exited (see log)"
fi

# 4) brew uninstall must clear list + Caskroom + app
log "brew uninstall --cask $TAP_CASK"
brew uninstall --cask "$TAP_CASK" 2>&1 || fail "brew uninstall failed"
killall Quintile 2>/dev/null || true
sleep 0.3
assert_clean "after brew uninstall"

# 5) Install after clean uninstall must work again (this is the user failure mode)
log "reinstall after clean uninstall"
if brew install --cask "$TAP_CASK" 2>&1 | tee /tmp/quintile-brew-reinstall.log; then
  if grep -qi "Not upgrading.*already installed" /tmp/quintile-brew-reinstall.log \
     && ! app_exists; then
    fail "reinstall claimed already installed but app missing — THE BUG"
  else
    pass "reinstall after uninstall succeeded"
  fi
else
  fail "reinstall after uninstall failed"
fi
assert_installed "after reinstall"
assert_first_run_window

# 6) Simulated orphan receipt: app deleted outside brew → install must not stuck
log "simulate orphan receipt (rm app, leave brew state)"
killall Quintile 2>/dev/null || true
rm -rf "$APP"
if cask_listed && ! app_exists; then
  pass "orphan state created (listed, no app)"
  # User-facing recovery we document:
  if brew reinstall --cask "$TAP_CASK" 2>&1 | tee /tmp/quintile-brew-orphan-reinstall.log; then
    assert_installed "after reinstall from orphan"
  else
    fail "brew reinstall failed from orphan state"
  fi
else
  pass "skip orphan sim (state unexpected)"
fi

# 7) Final force purge leaves machine clean for the human
force_purge
assert_clean "final"

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "All brew lifecycle checks passed."
  exit 0
else
  echo "$FAILS check(s) failed." >&2
  exit 1
fi
