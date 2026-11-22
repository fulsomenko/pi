import { type ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * /card — build a pickupable task card.
 *
 * A pickupable card has enough detail that another developer (or a future
 * you) can pick it up and start working without asking questions.
 *
 * Usage:
 *   /card Add rate limiting to the API gateway
 *   /card Fix memory leak in worker pool
 *   /card
 *   (empty args → show the blank template with guidance)
 */

function buildCard(title: string | undefined): string {
  const t = title?.trim();

  if (!t) {
    return [
      "Task Card Template",
      "══════════════════",
      "",
      "Usage:  /card <clear, outcome-oriented task title>",
      "Example: /card Add pagination to the project list",
      "",
      "What makes a card pickupable:",
      "  • Title states the outcome, not the method",
      "  • Scope is bounded — someone can estimate it in minutes",
      "  • Acceptance criteria are checkable (pass/fail)",
      "  • Dependencies are named, not implied",
      "  • A 'not doing' list prevents scope creep",
      "",
      "Give me a title and I'll fill in the rest.",
    ].join("\n");
  }

  return [
    `## Task Card: ${t}`,
    "",
    "**Title**      " + t,
    "**Why**        (1–2 sentences: the problem being solved or the value delivered)",
    "**Scope**      (concrete list of what this card covers — and what it does *not*)",
    "**Not doing**  (explicit out-of-scope items to prevent drift)",
    "",
    "**Acceptance criteria**  (checkable, testable statements)",
    "  - [ ] ",
    "  - [ ] ",
    "  - [ ] ",
    "",
    "**Definition of done**   (technical bar: tests, CI green, no feature flag, docs updated?)",
    "  - ",
    "",
    "**Dependencies**         (what must be complete before this can be picked up)",
    "  - None  (or name the ticket / PR / system)",
    "",
    "**Estimate**             S / M / L  —  S < 2h, M < 1 day, L < 3 days)",
    "**Priority**             P0 (blocker) / P1 (this sprint) / P2 (next sprint) / P3 (nice to have)",
    "",
    "**Risks / blockers**     (anything that could prevent pickup or completion)",
    "  - ",
    "",
    "**Notes**                (links, relevant files, prior discussion)",
    "  - ",
    "",
    "---",
    "Fill in any blank field, then say **\"done\"** when it's ready to pick up.",
  ].join("\n");
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("card", {
    description: "Plan a pickupable task card — /card <outcome-oriented title>",
    handler: async (args: string, ctx) => {
      ctx.ui.notify(buildCard(args), "info");
    },
  });
}
