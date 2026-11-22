import { type ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * /investigate — parallel codebase research.
 *
 * Decomposes a question into 2–4 research angles, walks through each one,
 * and synthesizes a concrete answer with file paths and line numbers.
 *
 * Usage:
 *   /investigate how auth token refresh works
 *   /investigate /investigate the retry strategy for API calls
 */

function buildPrompt(question: string): string {
  return [
    `Investigating: "${question}"`,
    "══════════════════════════════════════",
    "",
    "I'll work through three angles in parallel and then synthesize.",
    "Track each one separately, then connect them at the end.",
    "",
    "Angle 1 — WHERE it lives",
    "  grep for the primary keywords, find the entry points,",
    "  and map the call graph so we know which files to open.",
    "",
    "Angle 2 — HOW it works",
    "  Open the core files, trace the main path top-down,",
    "  note the happy path *and* the error handling.",
    "",
    "Angle 3 — VARIANTS & EDGE CASES",
    "  Find sibling implementations, test files, or config knobs",
    "  that reveal the intended behavior under different conditions.",
    "",
    `Start with Angle 1: grep for the key terms in "${question}".`,
  ].join("\n");
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("investigate", {
    description: "parallel codebase research — /investigate <question>",
    handler: async (args: string, ctx) => {
      const q = args?.trim();
      if (!q) {
        ctx.ui.notify(
          "Usage:  /investigate <codebase question>\n" +
          "Example: /investigate how auth token refresh works\n" +
          "I'll decompose it into 3 parallel research angles and synthesize with file:line references.",
          "info",
        );
        return;
      }
      ctx.ui.notify(buildPrompt(q), "info");
    },
  });
}
