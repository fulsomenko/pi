import { type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

// A pi extension is a default-exported factory that receives the ExtensionAPI.
// Loaded at runtime by pi via jiti, so this .ts is used as-is (no tsc step).
export default function (pi: ExtensionAPI) {
  // Fires once when a session starts.
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.notify("hello extension loaded", "info");
  });

  // A slash command the user can type: /hello [args]
  pi.registerCommand("hello", {
    description: "Say hello (pi extension demo)",
    handler: async (args, ctx) => {
      ctx.ui.notify(`Hello, ${args || "world"}!`, "info");
    },
  });

  // A tool the model can call.
  pi.registerTool({
    name: "greet",
    label: "Greet",
    description: "Greet someone by name",
    parameters: Type.Object({ name: Type.String() }),
    async execute(_toolCallId, params: { name: string }, _signal, _onUpdate, _ctx) {
      return {
        content: [{ type: "text", text: `Hello, ${params.name}!` }],
        details: {},
      };
    },
  });
}
