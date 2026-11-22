import { type ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * /planning — structured project planning workflow.
 *
 * Breaks down a multi-part effort and produces a sequence of pickupable
 * cards, ready to be written one by one with /card.
 *
 * Usage:
 *   /planning Add dark mode to all app screens
 *   /planning Migrate from MySQL to Postgres
 *   /planning
 *   (empty args → show the planning framework)
 */

function blankFramework(): string {
  return [
    "Planning Framework",
    "═══════════════════",
    "",
    "Usage:  /planning <project or effort name>",
    "Example: /planning refactor the auth service",
    "",
    "Steps I'll walk through with you:",
    "",
    "  1. Scope      what's in, what's out",
    "  2. Sequence   order tasks so each one's pickupable (no hidden deps)",
    "  3. Cards      break into individual tickets with /card",
    "  4. Risks      what could slip, and the mitigation for each",
    "",
    "Give me the project name and I'll start with scope.",
  ].join("\n");
}

function buildPlan(project: string): string {
  return [
    `Project plan: "${project}"`,
    "════════════════════════════════════",
    "",
    "Before I break this down, I need to understand the boundaries.",
    "",
    "1.  SCOPE",
    "    What's in?  (the core outcome you're after)",
    "    What's out? (explicit non-goals — this is the hardest part, be deliberate)",
    "",
    "2.  CONTEXT",
    "    What already exists that affects the shape of this work? (frameworks,",
    "    integrations, legacy code you have to keep working, etc.)",
    "",
    "3.  CONSTRAINTS",
    "    Time budget?  (sprint / quarter / 'before the demo')",
    "    Any hard deadlines or blockers waiting upstream?",
    "",
    "Answer those three and I'll produce an ordered sequence of pickupable cards,",
    "each one checkable /card-level scope (≤ 1 day, explicit acceptance criteria).",
  ].join("\n");
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("planning", {
    description: "structured project planning — /planning <project or effort>",
    handler: async (args: string, ctx) => {
      const t = args?.trim();
      ctx.ui.notify(t ? buildPlan(t) : blankFramework(), "info");
    },
  });
}
