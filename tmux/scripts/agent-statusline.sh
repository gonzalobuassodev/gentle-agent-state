#!/usr/bin/env bash
# agent-statusline — idempotently prepend the silent self-heal heartbeat to
# status-right. status-right is the ONLY thing tmux re-runs on status-interval, so
# the heartbeat (agent-status.sh) has to live there.
#
# Themes loaded async via TPM set their own status-right AFTER us, clobbering the
# prepend and killing the heartbeat. So this is called twice: once deferred at load
# and again on the client-attached hook (theme is loaded by then). Idempotent — it
# only prepends when our segment isn't already present, so re-running is safe.
set -uo pipefail
command -v tmux >/dev/null 2>&1 || exit 0

current="$(tmux show -gv status-right 2>/dev/null || true)"
case "$current" in
  *agent-status.sh*) ;;  # already present — nothing to do
  *) tmux set -g status-right "#(~/.config/tmux/scripts/agent-status.sh)$current" ;;
esac
