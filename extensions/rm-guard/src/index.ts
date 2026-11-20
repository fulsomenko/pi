import { type ExtensionAPI, type ToolCallEvent } from "@earendil-works/pi-coding-agent";

/**
 * Destructive-command guard for the bash tool.
 *
 * pi fires a `tool_call` event *before* a tool executes and lets the handler
 * block it. For the bash tool the command is at `event.input.command` and the
 * handler can return `{ block: true, reason }` to stop it. When the command
 * matches a "same-weight-as-rm" destructive pattern we pause and ask a yes/no
 * confirm (`ctx.ui.confirm`); a "no" blocks the call, a "yes" lets it proceed.
 *
 * Scope: strict + extended (see DESTRUCTIVE_WORDS / RULES). Always asks — there
 * is no remembered allow-list. Fails closed: if confirm times out or resolves
 * false, the command is blocked.
 *
 * NOTE: this guards the *agent's* bash tool. A user typing a literal `!cmd`
 * (the `user_bash` path) runs straight through in a live terminal, so it is
 * intentionally left un-gated.
 */

// Commands that are destructive in (nearly) every form — matched as a standalone
// command word. Includes path-basename forms (e.g. /usr/bin/rm) and sh -c "rm ...".
const DESTRUCTIVE_WORDS = [
  "rm", "rmdir", "shred", "dd", "truncate",
  "fdisk", "gdisk", "sgdisk", "parted", "wipefs",
];
const DESTRUCTIVE_WORD_SET = new Set(DESTRUCTIVE_WORDS);

// Subcommand / flag / redirect patterns (each carries a human-readable reason
// shown in the confirm dialog). Matched per statement segment.
const RULES: { pattern: RegExp; reason: string }[] = [
  { pattern: /\bfind\b[^\n;&|]*\s-delete\b/, reason: "find -delete" },
  { pattern: /\bgit\b[^\n;&|]*?\sreset\s+--hard\b/, reason: "git reset --hard" },
  { pattern: /\bgit\b[^\n;&|]*?\bclean\b[^\n;&|]*?-[a-z]*[fdx]/i, reason: "git clean -f/-d/-x" },
  { pattern: /\bgit\b[^\n;&|]*?\sbranch\s+(?:-D\b|--delete\b)/, reason: "git branch -D / --delete" },
  { pattern: /\bgit\b[^\n;&|]*?\spush\b(?=[^\n;&|]*\s(?:--force\b|-f\b|--force-with-lease))/, reason: "git push --force" },
  { pattern: /\bgit\b[^\n;&|]*?\scheckout\s+\.([^\w]|$)/, reason: "git checkout . (discard changes)" },
  { pattern: /\bgit\b[^\n;&|]*?\scheckout\s+--\s+\S/, reason: "git checkout -- (discard changes)" },
  { pattern: /\bgit\b[^\n;&|]*?\srestore\b\s+\S/, reason: "git restore (discards a version)" },
  { pattern: /\bchmod\s+(?:-[a-zA-Z]*R\b|--recursive\b)/i, reason: "chmod recursive (-R)" },
  { pattern: /\bchown\s+(?:-[a-zA-Z]*R\b|--recursive\b)/i, reason: "chown recursive (-R)" },
  { pattern: /\bmv\s+(?:-[a-zA-Z]*f\b|--force\b)/i, reason: "mv --force (overwrite)" },
  { pattern: /(?:>>?)\s?\/dev\/(?:sd[a-z0-9]+|nvme[a-z0-9./p]+|vd[a-z0-9]+|hd[a-z0-9]+|mem|kmem)/i, reason: "redirect to a raw device" },
];

// Words to ignore before finding the leading command (wrappers, not the command).
const WRAPPER_WORDS = new Set(["sudo", "env", "command", "nohup", "time", "nice", "timeout"]);

function isDestructiveWord(w: string): boolean {
  const base = w.split("/").pop() ?? w;
  return DESTRUCTIVE_WORD_SET.has(base) || base.startsWith("mkfs.");
}

// Split one command line into statement segments. Quotes are intentionally
// ignored — a guard that occasionally over-matches is fine (false positives
// only add a prompt; they never silently let a destructive op through).
function segments(command: string): string[] {
  return command
    .split(/\n|;|&&|\|\||\|/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function leadingCommand(segment: string): string | undefined {
  for (const token of segment.split(/\s+/).filter(Boolean)) {
    if (token.includes("=")) continue; // env assignment
    if (WRAPPER_WORDS.has(token) && !token.includes("/")) continue;
    return token;
  }
  return undefined;
}

function isDestructive(command: string): string | undefined {
  for (const seg of segments(command)) {
    // 1) The leading command word is destructive (handles `sudo rm ...`, `env X=1 rm ...`).
    const cmd = leadingCommand(seg);
    if (cmd && isDestructiveWord(cmd)) return `command \`${cmd.split("/").pop()}\``;

    // 2) Any token is a destructive word, after stripping shell quoting/globs.
    //    Closes the subshell hole: `sh -c "rm -rf x"`, `bash -lc rm ...`, `/bin/rm`, …
    for (const token of seg.replace(/["'(){};&|;,]/g, " ").split(/\s+/).filter(Boolean)) {
      if (isDestructiveWord(token)) return `command \`${token.split("/").pop()}\``;
    }

    // 3) A known destructive subcommand/flag/redirect pattern.
    for (const rule of RULES) {
      if (rule.pattern.test(seg)) return rule.reason;
    }
  }
  return undefined;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event: ToolCallEvent, ctx) => {
    if (event.toolName !== "bash") return; // only guard the bash tool

    const command = event.input.command;
    const reason = isDestructive(command);
    if (!reason) return; // benign -> let it run

    const approved = await ctx.ui.confirm(
      "Destructive command",
      `${reason}\n\nCommand:\n${command}`,
    );
    if (!approved) {
      return { block: true, reason: `Blocked by rm-guard (${reason})` };
    }
    // Approved: return void so pi proceeds with the call.
  });
}
