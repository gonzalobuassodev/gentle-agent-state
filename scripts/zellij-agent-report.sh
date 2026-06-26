#!/usr/bin/env bash
# zellij-agent-report — Zellij backend for the agent-state notifier.
#
# Zellij does not expose tmux-style per-window user options. The portable display
# surface is the pane title, so we rename the agent pane while it is working or
# blocked and remove the custom title when it goes idle.
#
# usage: zellij-agent-report.sh <pane_id> <working|blocked|idle> [message]
set -uo pipefail

pane="${1:-${ZELLIJ_PANE_ID:-}}"
state="${2:-}"
[ -n "$pane" ] && [ -n "$state" ] || exit 0

case "$state" in working|blocked|idle|unknown) ;; *) exit 0 ;; esac
command -v zellij >/dev/null 2>&1 || exit 0

# State is persisted only for transition-aware sound. Pane titles are owned by
# Zellij, so idle uses undo-rename-pane instead of storing/restoring old titles.
session="${ZELLIJ_SESSION_NAME:-default}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/agent-state-zellij"
mkdir -p "$state_dir" 2>/dev/null || true
state_file="$state_dir/${session}_${pane}.state"
prev="$(cat "$state_file" 2>/dev/null || true)"
printf '%s' "$state" > "$state_file" 2>/dev/null || true

case "$(uname -s)" in
  Darwin)
    SOUND_BLOCKED="${AGENT_SOUND_BLOCKED:-/System/Library/Sounds/Funk.aiff}"
    SOUND_IDLE="${AGENT_SOUND_IDLE:-/System/Library/Sounds/Glass.aiff}"
    ;;
  *)
    SOUND_BLOCKED="${AGENT_SOUND_BLOCKED:-/usr/share/sounds/freedesktop/stereo/dialog-warning.oga}"
    SOUND_IDLE="${AGENT_SOUND_IDLE:-/usr/share/sounds/freedesktop/stereo/complete.oga}"
    ;;
esac

play() {
  [ -f "$1" ] || return 0
  if command -v afplay >/dev/null 2>&1; then (afplay "$1" >/dev/null 2>&1 &)
  elif command -v paplay >/dev/null 2>&1; then (paplay "$1" >/dev/null 2>&1 &)
  elif command -v canberra-gtk-play >/dev/null 2>&1; then (canberra-gtk-play -f "$1" >/dev/null 2>&1 &)
  elif command -v aplay >/dev/null 2>&1; then (aplay -q "$1" >/dev/null 2>&1 &)
  fi
}

case "$state" in
  blocked)
    zellij action rename-pane --pane-id "$pane" "● agent blocked" >/dev/null 2>&1 || true
    [ "$state" != "$prev" ] && play "$SOUND_BLOCKED"
    ;;
  working)
    zellij action rename-pane --pane-id "$pane" "● agent working" >/dev/null 2>&1 || true
    ;;
  idle)
    zellij action undo-rename-pane --pane-id "$pane" >/dev/null 2>&1 || true
    case "$prev" in working|blocked) play "$SOUND_IDLE" ;; esac
    ;;
  unknown)
    zellij action undo-rename-pane --pane-id "$pane" >/dev/null 2>&1 || true
    ;;
esac
