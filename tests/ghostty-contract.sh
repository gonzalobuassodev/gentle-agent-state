#!/usr/bin/env bash
# Contract tests for native Ghostty support.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  expected="$1"
  actual="$2"
  label="$3"
  [ "$actual" = "$expected" ] || fail "$label: expected $(printf %q "$expected"), got $(printf %q "$actual")"
  printf 'ok - %s\n' "$label"
}

printf '1..8\n'

# Keep shell syntax coverage deterministic and dependency-free.
bash -n install.sh uninstall.sh scripts/*.sh tmux/scripts/*.sh tests/*.sh
printf 'ok - shell syntax\n'

osc_blocked=$'\033]2;agent: blocked\007'
osc_idle=$'\033]2;agent: idle\007'

ghostty_env=(env -i HOME="$HOME" PATH="$PATH" TERM_PROGRAM=ghostty AGENT_GHOSTTY_FORCE_STDOUT=1)

actual="$(${ghostty_env[@]} bash scripts/agent-report.sh ghostty blocked)"
assert_eq "$osc_blocked" "$actual" "Ghostty dispatcher emits blocked title"

actual="$(${ghostty_env[@]} bash scripts/agent-report.sh ghostty idle)"
assert_eq "$osc_idle" "$actual" "Ghostty dispatcher emits idle title"

tmp_home="$(mktemp -d)"
cleanup() { rm -rf "$tmp_home" "${install_home:-}" "${adapter_home:-}"; }
trap cleanup EXIT
mkdir -p "$tmp_home/.config/agent-state/scripts"
cp scripts/*.sh "$tmp_home/.config/agent-state/scripts/"

hook_env=(env -i HOME="$tmp_home" PATH="$PATH" TERM_PROGRAM=ghostty AGENT_GHOSTTY_FORCE_STDOUT=1)

actual="$(${hook_env[@]} bash scripts/hook-adapter.sh Stop </dev/null)"
assert_eq "$osc_idle" "$actual" "hook adapter routes Ghostty Stop to idle"

actual="$(printf '{"tool_name":"AskUserQuestion"}' | ${hook_env[@]} bash scripts/hook-adapter.sh PreToolUse)"
assert_eq "$osc_blocked" "$actual" "hook adapter routes Ghostty blocking tool to blocked"

install_home="$(mktemp -d)"
install_output="$(env -i HOME="$install_home" PATH="$PATH" TERM_PROGRAM=ghostty bash ./install.sh)"
[ -x "$install_home/.config/agent-state/scripts/ghostty-agent-report.sh" ] || fail "installer did not install Ghostty backend"
case "$install_output" in
  *"Ghostty detected"*|*"Zellij/Ghostty"*) ;;
  *) fail "installer did not mention Ghostty support" ;;
esac
env -i HOME="$install_home" PATH="$PATH" bash ./uninstall.sh >/dev/null
[ ! -e "$install_home/.config/agent-state/scripts/ghostty-agent-report.sh" ] || fail "uninstaller did not remove Ghostty backend"
printf 'ok - installer and uninstaller handle Ghostty backend\n'

adapter_home="$(mktemp -d)"
mkdir -p "$adapter_home/.config/agent-state/scripts"
cat > "$adapter_home/.config/agent-state/scripts/agent-report.sh" <<'REPORT'
#!/usr/bin/env bash
printf '<%s>|<%s>|<%s>\n' "${1-}" "${2-}" "${3-}" >> "$AGENT_REPORT_LOG"
REPORT
chmod +x "$adapter_home/.config/agent-state/scripts/agent-report.sh"

log="$adapter_home/report.log"
node_env=(env -i HOME="$adapter_home" PATH="$PATH" TERM_PROGRAM=ghostty AGENT_REPORT_LOG="$log")

"${node_env[@]}" node --input-type=module <<'NODE'
const mod = await import(`file://${process.cwd()}/adapters/opencode/gentle-agent-state.js`);
const plugin = await mod.TmuxAgentStatePlugin();
if (typeof plugin["chat.message"] !== "function") {
  throw new Error("opencode plugin did not enable in native Ghostty");
}
await plugin["chat.message"]();
NODE
assert_eq "<ghostty>|<working>|<>" "$(cat "$log")" "opencode adapter reports Ghostty backend id"

: > "$log"
"${node_env[@]}" node --input-type=module <<'NODE'
const mod = await import(`file://${process.cwd()}/adapters/pi/gentle-agent-state.ts`);
const handlers = new Map();
const pi = { on(name, handler) { handlers.set(name, handler); } };
mod.default(pi);
if (!handlers.has("agent_start")) {
  throw new Error("pi extension did not enable in native Ghostty");
}
handlers.get("agent_start")();
await new Promise((resolve) => setTimeout(resolve, 100));
NODE
assert_eq "<ghostty>|<working>|<>" "$(cat "$log")" "pi adapter reports Ghostty backend id"
