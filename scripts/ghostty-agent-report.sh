#!/usr/bin/env bash
# ghostty-agent-report — native Ghostty backend for the agent-state notifier.
#
# Ghostty has no tmux/Zellij-style pane metadata available to shell hooks, so this
# backend intentionally stays minimal: it publishes the latest state by changing
# the terminal title with an OSC escape sequence.
#
# usage: ghostty-agent-report.sh <ignored> <working|blocked|idle> [message]
set -uo pipefail

state="${2:-}"
msg="${3:-}"
[ -n "$state" ] || exit 0

case "$state" in working | blocked | idle | unknown) ;; *) exit 0 ;; esac

case "$state" in
blocked) title="agent: blocked${msg:+ — $msg}" ;;
working) title="agent: working" ;;
idle) title="agent: idle" ;;
unknown) title="agent: unknown" ;;
esac

# Keep notification text from injecting nested terminal control sequences.
title="${title//$'\033'/}"
title="${title//$'\a'/}"

emit_title() {
	printf '\033]2;%s\007' "$title"
}

if [ "${AGENT_GHOSTTY_FORCE_STDOUT:-}" = "1" ]; then
	emit_title
	exit 0
fi

if [ -w /dev/tty ] && emit_title 2>/dev/null >/dev/tty; then
	exit 0
fi

emit_title
