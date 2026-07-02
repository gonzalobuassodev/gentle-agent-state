#!/usr/bin/env bash
# telegram — agent-state hook.
# Sends a Telegram notification when the agent finishes or gets blocked.
#
# Configure credentials in ~/.config/agent-state/telegram.env:
#   AGENT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234"
#   AGENT_TELEGRAM_CHAT_ID="123456789"
#
# usage: telegram.sh <working|blocked|idle> [message]
set -uo pipefail

state="${1:-}"
msg="${2:-}"

# Source credentials from config file
config="${HOME}/.config/agent-state/telegram.env"
[ -f "$config" ] && source "$config"

token="${AGENT_TELEGRAM_BOT_TOKEN:-}"
chat_id="${AGENT_TELEGRAM_CHAT_ID:-}"

# Silent exit if not configured
[ -n "$token" ] && [ -n "$chat_id" ] || exit 0

# Toggle: remove ~/.config/agent-state/telegram.off to enable notifications
[ ! -f "${HOME}/.config/agent-state/telegram.off" ] || exit 0

# --- Enrich context from tmux pane ---
project=""
last_prompt=""

# Get project name from git
if command -v git >/dev/null 2>&1; then
  project="$(git rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null)"
fi

# Read last prompt saved by plugin
prompt_file="${HOME}/.config/agent-state/last-prompt"
[ -f "$prompt_file" ] && last_prompt="$(head -c 200 < "$prompt_file" | tr -d '\0')"

# Build message
case "$state" in
  idle)
    text="✅ OpenCode terminó"
    ;;
  blocked)
    text="⏸️ OpenCode necesita tu atención"
    ;;
  *) exit 0 ;;
esac

# Append context: project + prompt
ctx=""
[ -n "$project" ] && ctx="$project"
[ -n "$last_prompt" ] && ctx="${ctx:+${ctx} | }${last_prompt}"
[ -n "$msg" ] && ctx="${ctx:+${ctx} — }${msg}"
[ -n "$ctx" ] && text="${text} — ${ctx}"

curl -s -o /dev/null "https://api.telegram.org/bot${token}/sendMessage" \
  -d chat_id="${chat_id}" \
  -d text="${text}" \
  -d disable_notification=false
