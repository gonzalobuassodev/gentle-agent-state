#!/usr/bin/env bash
# agent-report — multiplexer dispatcher for the agent-state notifier.
#
# Adapters call this neutral entrypoint. It forwards the canonical state to the
# active terminal backend (tmux, Zellij, or native Ghostty).
#
# usage: agent-report.sh <pane_id> <working|blocked|idle> [message]
set -uo pipefail

pane="${1:-${TMUX_PANE:-${ZELLIJ_PANE_ID:-}}}"
state="${2:-}"
msg="${3:-}"
[ -n "$state" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$state" in working|blocked|idle|unknown) ;; *) exit 0 ;; esac

if [ -n "${TMUX_PANE:-}" ] || [[ "$pane" == %* ]]; then
  if command -v tmux >/dev/null 2>&1; then
    exec bash "$SCRIPT_DIR/tmux-agent-report.sh" "$pane" "$state" "$msg"
  fi
fi

if [ -n "${ZELLIJ_PANE_ID:-}" ] || [ -n "${ZELLIJ:-}" ]; then
  if command -v zellij >/dev/null 2>&1; then
    exec bash "$SCRIPT_DIR/zellij-agent-report.sh" "${pane:-${ZELLIJ_PANE_ID:-}}" "$state" "$msg"
  fi
fi

if [ "${TERM_PROGRAM:-}" = "ghostty" ]; then
  exec bash "$SCRIPT_DIR/ghostty-agent-report.sh" "$pane" "$state" "$msg"
fi

exit 0
