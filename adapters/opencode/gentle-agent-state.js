// gentle-agent-state — opencode adapter for the agent-state notifier.
// Translates opencode's native events into the canonical vocabulary and forwards
// them to the neutral multiplexer core (~/.config/agent-state/scripts/agent-report.sh).
//
// Active only when running inside tmux, Zellij, or native Ghostty (and NOT under herdr).

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const REPORT = join(homedir(), ".config", "agent-state", "scripts", "agent-report.sh");

function backendId() {
  if (process.env.TMUX_PANE) return process.env.TMUX_PANE;
  if (process.env.ZELLIJ_PANE_ID) return process.env.ZELLIJ_PANE_ID;
  if (process.env.TERM_PROGRAM === "ghostty") return "ghostty";
  return undefined;
}

function enabled() {
  // tmux sets TMUX_PANE; Zellij sets ZELLIJ_PANE_ID; native Ghostty sets TERM_PROGRAM=ghostty.
  return Boolean(backendId()) && process.env.HERDR_ENV !== "1";
}

function report(state, message) {
  const pane = backendId();
  if (!pane) return Promise.resolve();
  return new Promise((resolve) => {
    const child = spawn("bash", [REPORT, pane, state, message ?? ""], {
      stdio: "ignore",
      detached: false,
    });
    child.on("error", () => resolve());
    child.on("close", () => resolve());
  });
}

function stateFromSessionStatus(status) {
  if (typeof status !== "string") return undefined;
  switch (status.toLowerCase()) {
    case "idle":
      return "idle";
    case "active":
    case "busy":
    case "pending":
    case "running":
    case "streaming":
    case "working":
      return "working";
    default:
      return undefined;
  }
}

export const TmuxAgentStatePlugin = async () => {
  if (!enabled()) return {};

  return {
    "chat.message": async () => {
      await report("working");
    },
    event: async ({ event }) => {
      const type = event?.type;
      const properties = event?.properties ?? {};

      switch (type) {
        case "session.status": {
          const state = stateFromSessionStatus(properties.status);
          if (state) await report(state);
          break;
        }
        case "tool.execute.before":
        case "tool.execute.after":
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
        case "session.compacted":
          await report("working");
          break;
        case "permission.asked":
        case "question.asked":
          await report("blocked");
          break;
        // session.error fires for recoverable errors too (e.g. editing a file
        // before reading it) that the agent retries and works through. It is NOT
        // "waiting on the user", so we ignore it — real lifecycle events
        // (session.idle / permission.asked) drive the state instead.
        case "session.idle":
          await report("idle");
          break;
        case "session.deleted":
          await report("idle");
          break;
        default:
          break;
      }
    },
  };
};
