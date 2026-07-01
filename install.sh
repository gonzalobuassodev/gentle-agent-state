#!/usr/bin/env bash
# install.sh — agent-state notifier installer.
#
# Installs the neutral normalization core, the tmux display layer when tmux is
# available, and (opt-in) the per-agent adapters. Each adapter is installed ONLY
# when you ask for it, so this never touches the config of a tool you don't use.
#
#   ./install.sh                         core + Zellij backend (tmux display if available)
#   ./install.sh --with-opencode         core + opencode adapter
#   ./install.sh --with-pi --with-claude core + pi + claude adapters
#   ./install.sh --all                   core + every adapter whose tool is detected
#
# Backends: tmux, Zellij, and native Ghostty (auto-detected at runtime)
# Adapters: --with-opencode  --with-pi  --with-claude  --with-codex
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_STATE_DIR="$HOME/.config/agent-state/scripts"
TMUX_DIR="$HOME/.config/tmux"
SCRIPTS_DIR="$TMUX_DIR/scripts"

want_opencode=0 want_pi=0 want_claude=0 want_codex=0 want_all=0
for arg in "$@"; do
  case "$arg" in
    --with-opencode) want_opencode=1 ;;
    --with-pi)       want_pi=1 ;;
    --with-claude)   want_claude=1 ;;
    --with-codex)    want_codex=1 ;;
    --all)           want_all=1 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }

# --- dependency check ---
missing=""
command -v jq      >/dev/null 2>&1 || missing="$missing jq"
command -v python3 >/dev/null 2>&1 || missing="$missing python3"
if ! command -v tmux >/dev/null 2>&1 && ! command -v zellij >/dev/null 2>&1 && [ "${TERM_PROGRAM:-}" != "ghostty" ] && ! command -v ghostty >/dev/null 2>&1; then
  missing="$missing tmux-zellij-or-ghostty"
fi
if [ -n "$missing" ]; then
  say "❌ missing required tools:$missing"
  say "   install them and re-run. (jq + python3 power the claude/codex hook adapters)"
  exit 1
fi

# --- core: neutral dispatcher + terminal backends ---
say "🔧 installing agent-state core..."
mkdir -p "$AGENT_STATE_DIR"
cp -f "$SRC/scripts/"*.sh "$AGENT_STATE_DIR/"
chmod +x "$AGENT_STATE_DIR/"*.sh
say "  ⚙️  neutral scripts installed to $AGENT_STATE_DIR"
if command -v zellij >/dev/null 2>&1; then
  say "  ✅ Zellij detected — backend installed; no extra Zellij config is needed"
fi
if [ "${TERM_PROGRAM:-}" = "ghostty" ] || command -v ghostty >/dev/null 2>&1; then
  say "  ✅ Ghostty detected — native title backend installed"
fi

# --- tmux display layer (when tmux is available) ---
if command -v tmux >/dev/null 2>&1; then
  mkdir -p "$SCRIPTS_DIR"
  cp -f "$SRC/tmux/scripts/"*.sh "$SCRIPTS_DIR/"
  chmod +x "$SCRIPTS_DIR/"*.sh
  cp -f "$SRC/tmux/agents.conf" "$TMUX_DIR/agents.conf"
  say "  ⚙️  tmux scripts + agents.conf installed to $TMUX_DIR"
else
  say "  ⏭️  tmux not found — installed neutral core for Zellij/Ghostty when available"
fi

# --- ensure the tmux config sources agents.conf (idempotent, at end of file) ---
if command -v tmux >/dev/null 2>&1; then
  # Prefer ~/.config/tmux/tmux.conf, fall back to ~/.tmux.conf.
  TMUX_CONF="$TMUX_DIR/tmux.conf"
  [ -f "$TMUX_CONF" ] || { [ -f "$HOME/.tmux.conf" ] && TMUX_CONF="$HOME/.tmux.conf"; }
  [ -f "$TMUX_CONF" ] || TMUX_CONF="$TMUX_DIR/tmux.conf"   # create the modern path if neither exists

  SOURCE_LINE="if-shell '[ -f ~/.config/tmux/agents.conf ]' 'source-file ~/.config/tmux/agents.conf'"
  if [ -f "$TMUX_CONF" ] && grep -qF 'agents.conf' "$TMUX_CONF"; then
    say "  ✅ $TMUX_CONF already sources agents.conf"
  else
    mkdir -p "$(dirname "$TMUX_CONF")"
    {
      printf '\n# tmux agent-state notifier — sourced last so the per-tab state marker extends the theme\n'
      printf '%s\n' "$SOURCE_LINE"
    } >> "$TMUX_CONF"
    say "  ➕ appended source line to $TMUX_CONF"
  fi
fi

# --- adapters (opt-in) ---
install_opencode() {
  local dst="$HOME/.config/opencode/plugins"
  mkdir -p "$dst"
  rm -f "$dst/tmux-agent-state.js"
  cp -f "$SRC/adapters/opencode/gentle-agent-state.js" "$dst/"
  say "  🔌 opencode adapter → $dst"
}
install_pi() {
  local dst="$HOME/.pi/agent/extensions"
  mkdir -p "$dst"
  rm -f "$dst/tmux-agent-state.ts"
  cp -f "$SRC/adapters/pi/gentle-agent-state.ts" "$dst/"
  say "  🔌 pi adapter → $dst"
}

HOOK="bash $HOME/.config/agent-state/scripts/hook-adapter.sh"
OLD_HOOK="bash $HOME/.config/tmux/scripts/hook-adapter.sh"

# merge_hooks <target.json> <Event:matcher> ...
# APPENDS our hook (never replaces arrays), only if not already present — so it
# never clobbers other hooks you have configured.
merge_hooks() {
  local file="$1"; shift
  [ -f "$file" ] || echo '{"hooks":{}}' > "$file"
  local filter='.hooks = (.hooks // {})'
  local pair ev matcher
  for pair in "$@"; do
    ev="${pair%%:*}"; matcher="${pair#*:}"
    filter="$filter | addhook(\"$ev\"; \"$matcher\")"
  done
  jq --arg base "$HOOK" --arg oldbase "$OLD_HOOK" "
    def drop_old_agent_state_hooks:
      map(.hooks |= map(select(((.command // \"\") | startswith(\$oldbase)) | not)))
      | map(select((.hooks | length) > 0));
    def addhook(\$ev; \$matcher):
      (\$base + \" \" + \$ev) as \$cmd
      | .hooks[\$ev] = ((.hooks[\$ev] // [] | drop_old_agent_state_hooks)
        | if any(.[].hooks[]?; .command == \$cmd) then .
          else . + [{matcher: \$matcher, hooks: [{type: \"command\", command: \$cmd, timeout: 5}]}] end);
    $filter
  " "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

install_claude() {
  local file="$HOME/.claude/settings.json"
  if [ ! -f "$file" ]; then
    say "  ⏭️  claude: $file not found — run Claude once, then re-run with --with-claude"
    return
  fi
  merge_hooks "$file" "UserPromptSubmit:" "PreToolUse:*" "Notification:" "Stop:"
  say "  🪝 claude hooks merged → $file"
}
install_codex() {
  local file="$HOME/.codex/hooks.json"
  if [ ! -f "$file" ]; then
    say "  ⏭️  codex: $file not found — run Codex once, then re-run with --with-codex"
    return
  fi
  merge_hooks "$file" "UserPromptSubmit:" "PreToolUse:*" "Notification:" "Stop:" "TurnComplete:"
  say "  🪝 codex hooks merged → $file (approve the new hooks on next codex start)"
}

# --all = install every adapter whose tool is detected on disk
if [ "$want_all" = 1 ]; then
  [ -d "$HOME/.config/opencode" ] && want_opencode=1
  [ -d "$HOME/.pi" ]              && want_pi=1
  [ -d "$HOME/.claude" ]          && want_claude=1
  [ -d "$HOME/.codex" ]           && want_codex=1
fi

[ "$want_opencode" = 1 ] && install_opencode
[ "$want_pi" = 1 ]       && install_pi
[ "$want_claude" = 1 ]   && install_claude
[ "$want_codex" = 1 ]    && install_codex

if [ "$want_opencode$want_pi$want_claude$want_codex$want_all" = "00000" ]; then
  say ""
  say "ℹ️  core installed, no adapters. Add the agents you use:"
  say "    ./install.sh --with-opencode --with-pi --with-claude --with-codex"
  say "    ./install.sh --all      # auto-detect installed tools"
fi

say ""
if [ -n "${TMUX_CONF:-}" ]; then
  say "🎉 done. tmux: open a fresh session or run: tmux source-file $TMUX_CONF"
  if command -v zellij >/dev/null 2>&1; then
    say "🎉 done. Zellij: restart your agents inside Zellij; pane/tab titles will show agent state."
  fi
else
  say "🎉 done. Zellij/Ghostty: restart your agents inside the terminal; titles will show agent state."
fi
if [ "${TERM_PROGRAM:-}" = "ghostty" ] || command -v ghostty >/dev/null 2>&1; then
  say "🎉 done. Ghostty: restart your agents inside Ghostty; the window title will show agent state."
fi
