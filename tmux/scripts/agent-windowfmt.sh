#!/usr/bin/env bash
# agent-windowfmt — idempotently prepend the agent-state dot to
# window-status-format and window-status-current-format so the per-tab
# indicator survives theme reloads.
#
# Themes loaded via TPM set their own window-status-format synchronously, but
# this still runs deferred to ensure the theme's colors are fully applied first.
# Idempotent: only prepends when our dot segment isn't already present.
set -uo pipefail
command -v tmux >/dev/null 2>&1 || exit 0

dot_blocked='#{?#{==:#{@win_agent_state},blocked},#[fg=#e82424]● ,}'
dot_working='#{?#{==:#{@win_agent_state},working},#[fg=#dca561]● ,}'
dot="${dot_blocked}${dot_working}"

for fmt_opt in window-status-format window-status-current-format; do
  current="$(tmux show -gv "$fmt_opt" 2>/dev/null || true)"
  case "$current" in
    *'@win_agent_state'*) ;;  # already present — nothing to do
    *) tmux set -g "$fmt_opt" "${dot}${current}" ;;
  esac
done
