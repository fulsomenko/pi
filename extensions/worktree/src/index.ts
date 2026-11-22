import { type ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * /worktree — create a git worktree for parallel development.
 *
 * Usage:
 *   /worktree DEV-1234
 *   /worktree 4178
 */

function usage(): string {
  return [
    "Git worktree helper",
    "══════════════════════",
    "",
    "Usage:  /worktree <ticket-id | pr-number>",
    "Examples:",
    "   /worktree DEV-1234      → worktree at ~/wt/<repo>/dev-1234, branch max/dev-1234",
    "   /worktree 4178          → worktree at ~/wt/<repo>/pr-4178, uses PR head branch",
    "",
    "The script checks for create-worktree on PATH first;",
    "if missing it does the git worktree add manually.",
    "",
    "Tell me a ticket or PR number to get started.",
  ].join("\n");
}

function buildPrompt(target: string): string {
  const isPr = /^\d+$/.test(target);
  const label = isPr ? `PR #${target}` : target;
  const branch = isPr ? "" : `max/${target.toLowerCase()}`;
  const dir = `~/wt/<repo>/${isPr ? "pr-" + target : target.toLowerCase()}`;

  return [
    `Creating worktree for ${label}`,
    "══════════════════════════════════════",
    "",
    `Target directory :  ${dir}`,
    `Branch name      :  ${branch || "(resolved from PR head)"}`,
    "",
    "Steps I'll take (confirm before running):",
    "  1.  git rev-parse --show-toplevel  → get the repo root",
    `  2.  git worktree add ${dir} ${branch || "<head-branch>"}`,
    "  3.  Link .mcp.json from the source repo if present",
    "  4.  Create .envrc (use_flake) if flake.nix is present",
    "",
    "Ready?  I'll run the git commands — just confirm when you are.",
  ].join("\n");
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("worktree", {
    description: "create git worktree for parallel dev — /worktree <ticket|pr>",
    handler: async (args: string, ctx) => {
      const t = args?.trim();
      if (!t) {
        ctx.ui.notify(usage(), "info");
        return;
      }
      ctx.ui.notify(buildPrompt(t), "info");
    },
  });
}
