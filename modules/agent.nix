# Purpose: configure pi (the coding agent) for a user by installing files into
#          the pi agent directory (~/.pi/agent on the given user):
#           - models.json: point pi at a custom model endpoint (Ollama, LM
#             Studio, vLLM, ...). See pi docs/models.md, "Configure a
#             compatible endpoint".
#           - mcp.json: user-level MCP servers. See pi docs/mcp.md, "Configure
#             servers".
#          (plus docs/configuration.md, "Agent directory")
# Platform: NixOS
# Options:  pi.agent.enable
#           pi.agent.user
#           pi.agent.provider
#           pi.agent.baseUrl
#           pi.agent.api
#           pi.agent.apiKey
#           pi.agent.models
#           pi.agent.prompts
#           pi.agent.sendSessionAffinityHeaders
#           pi.agent.sessionAffinityFormat
#           pi.agent.mcpServers
#
# Only standard NixOS specialArgs (config/lib/pkgs) are used: a NixOS module
# is applied exactly once (lib/modules.nix loadModule/applyModuleArgs) and
# must return a top-level { options, config } attrset. The user's home dir
# is looked up through the users option, not a specialArg.
{ config, lib, pkgs, ... }:

let
  cfg = config.pi.agent;

  # Lazy by design: only forced when the activation script is produced
  # (pi.agent.enable = true with a valid pi.agent.user).
  home = config.users.users.${cfg.user}.home;

  # Free-form value a sampling param may take. pi's models.json `samplingParams`
  # is a free-form object merged into every request body, so any JSON value must
  # be typable: scalars, one level of attrs, or a list of scalars.
  scalar = lib.types.oneOf [ lib.types.str lib.types.int lib.types.float lib.types.bool ];
  samplingValue = lib.types.oneOf [ scalar (lib.types.attrsOf scalar) (lib.types.listOf scalar) ];

  # Optionally tag every request with pi's own session ID. pi models.json
  # (docs/models-configuration.md) exposes this as a per-model `compat` object:
  #   sendSessionAffinityHeaders : whether to emit a session-affinity header
  #   sessionAffinityFormat      : "openrouter" sends `x-session-id` (the header
  #                                the scribe proxy reads to classify pi's
  #                                transcripts); "openai" sends `session_id`,
  #                                `x-client-request-id`, `x-session-affinity`.
  # We apply the same value to every model so dotfiles can flip one provider-
  # level toggle instead of repeating the block per model.
  modelToJson = m:
    { id = m.id; }
    // lib.optionalAttrs (m.name != null) { name = m.name; }
    // lib.optionalAttrs (m.contextWindow != null) { contextWindow = m.contextWindow; }
    // lib.optionalAttrs (m.maxTokens != null) { maxTokens = m.maxTokens; }
    // lib.optionalAttrs (m.reasoning != null) { reasoning = m.reasoning; }
    // lib.optionalAttrs (m.samplingParams != { }) { samplingParams = m.samplingParams; }
    // lib.optionalAttrs cfg.sendSessionAffinityHeaders ({ compat = {
         sendSessionAffinityHeaders = true;
         sessionAffinityFormat = cfg.sessionAffinityFormat;
       }; });

  hasModels = cfg.models != [ ];
  # Plain store path (no lib.mkIf): it is interpolated into the activation
  # script, which must contain a forced string, and the optionalString
  # guards below decide whether the line appears. Building the store file
  # unconditionally is harmless (a few bytes of JSON).
  modelsJson = pkgs.writeText "pi-models.json" (builtins.toJSON {
    "$schema" = "https://pi.dev/schemas/models.schema.json";
    providers.${cfg.provider} = {
      inherit (cfg) baseUrl api apiKey;
      models = map modelToJson cfg.models;
    };
  });

  # mcp.json, one entry per server. Optional fields follow pi's mcp.json
  # schema (docs/mcp.md): stdio servers use command/args/env/cwd, HTTP
  # servers use url/headers. Unset fields are omitted so pi applies its
  # own defaults (e.g. enabled, timeout = 60).
  serverToJson = s: { }
    // lib.optionalAttrs (s.command != null) (
      { command = s.command; args = s.args; }
      // lib.optionalAttrs (s.env != { }) { env = s.env; }
      // lib.optionalAttrs (s.cwd != null) { cwd = s.cwd; }
    )
    // lib.optionalAttrs (s.url != null) (
      { url = s.url; }
      // lib.optionalAttrs (s.headers != { }) { headers = s.headers; }
    )
    // lib.optionalAttrs (s.description != null) { description = s.description; }
    // lib.optionalAttrs (!s.enabled) { enabled = s.enabled; }
    // lib.optionalAttrs (s.timeout != null) { timeout = s.timeout; }
    // lib.optionalAttrs (s.type != null) { type = s.type; }
    // lib.optionalAttrs (s.exposure != null) { exposure = s.exposure; }
    // lib.optionalAttrs (s.toolExposure != null) { toolExposure = s.toolExposure; };

  hasMcp = cfg.mcpServers != { };
  mcpJson = pkgs.writeText "pi-mcp.json" (builtins.toJSON {
    mcpServers = lib.mapAttrs (name: server: serverToJson server) cfg.mcpServers;
  });

  # Prompt templates: turn each `pi.agent.prompts.<name>` entry into a
  # `<agent-dir>/prompts/<name>.md` file, which pi auto-discovers and exposes
  # as a `/name` slash command (docs/prompt-templates.md). The file is classic
  # frontmatter + body:
  #   ---
  #   description: ...
  #   argument-hint: ...
  #   ---
  #   <body with $1 / $@ / $ARGUMENTS substitutions>
  # `argument-hint` is always double-quoted: a hint like `[focus]` would
  # otherwise be parsed by YAML as a list rather than the literal string.
  yamlStr = s: builtins.replaceStrings [ "\"" ] [ "\\\"" ] (lib.removeSuffix "\n" s);
  promptToMarkdown = p: "---\n"
    + (lib.optionalString (p.description != "") "description: \"${yamlStr p.description}\"\n")
    + (lib.optionalString (p.argumentHint != null) "argument-hint: \"${yamlStr p.argumentHint}\"\n")
    + "---\n"
    + p.body;

  hasPrompts = cfg.prompts != { };
  # A store *directory* whose direct children are the template files. Pi loads
  # direct `.md` children of the prompts dir (docs/prompt-templates.md), so the
  # files must sit at the top level, not nested.
  promptsDir = pkgs.writeTextDir "pi-prompts" (
    lib.mapAttrs' (name: p: lib.nameValuePair "${name}.md" (promptToMarkdown p)) cfg.prompts
  );
in
{
  options.pi.agent = {
    enable = lib.mkEnableOption "pi agent config (models.json and/or mcp.json) installed into the user's pi agent directory";

    user = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "User whose ~/.pi/agent gets models.json. Must exist in users.users.";
    };

    provider = lib.mkOption {
      type = lib.types.str;
      default = "ollama";
      description = "Provider key under models.json's providers table.";
    };

    # Tell pi to tag every request with its own session ID as a header (pi
    # models-configuration.md: per-model compat.sendSessionAffinityHeaders +
    # compat.sessionAffinityFormat). This is what the scribe proxy classifies
    # pi's transcripts by: the proxy reads the `x-session-id` request header.
    sendSessionAffinityHeaders = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Send pi's own session ID on every model request, so the scribe proxy can classify transcripts per session (compat.sendSessionAffinityHeaders = true).";
    };

    sessionAffinityFormat = lib.mkOption {
      type = lib.types.enum [ "openai" "openai-nosession" "openrouter" ];
      default = "openrouter";
      description = "Session-affinity header format (compat.sessionAffinityFormat). \"openrouter\" emits x-session-id -- the header the scribe proxy reads; the other formats emit different headers.";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434/v1";
      description = "API base URL of the model endpoint.";
    };

    api = lib.mkOption {
      type = lib.types.str;
      default = "openai-completions";
      description = "API implementation for the endpoint, e.g. openai-completions.";
    };

    apiKey = lib.mkOption {
      type = lib.types.str;
      default = "ollama";
      description = "Literal key, $NAME env interpolation, or !command. Ollama accepts a dummy value.";
    };

    # A list of model records. `attrsOf` does not work here -- it types the
    # _values of a map_, not a fixed field set -- so each entry is a
    # submodule with the fields the pi models.json schema accepts.
    models = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "Model id served by the endpoint, e.g. qwen3-coder:30b.";
          };
          name = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional display name.";
          };
          contextWindow = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Optional context window size (pi defaults to 128000).";
          };
          maxTokens = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Optional max output tokens (pi defaults to 16384).";
          };
          reasoning = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Optional reasoning flag (pi defaults to false).";
          };
          samplingParams = lib.mkOption {
            type = lib.types.attrsOf samplingValue;
            default = { };
            description = "Optional sampling params merged into every request body (pi: samplingParams, OpenAI-compatible APIs). E.g. { reasoning_effort = \"low\"; }.";
          };
        };
      });
      default = [ ];
      example = [
        { id = "qwen3-coder:30b"; contextWindow = 65536; maxTokens = 32000; }
        { id = "qwen3.8:27b-128k"; contextWindow = 131072; samplingParams.reasoning_effort = "low"; }
      ];
      description = "Models the endpoint exposes. Entries not set are omitted (pi applies schema defaults).";
    };

    # Prompt templates -> ~/.pi/agent/prompts/<name>.md (pi docs/prompt-templates.md).
    # Each entry becomes a `/name` slash command: pi auto-discovers the .md file,
    # expands the body against the arguments the user typed, and submits the
    # result to the model. This is the mechanism for /card, /planning,
    # /investigate, /worktree -- "prompt shorthand" commands in the style of
    # qwen/codex command .md files, with no executable behaviour.
    #
    # Substitutions available in `body` (docs/prompt-templates.md): $1, $2, ...
    # (positional args), $@ / $ARGUMENTS (all args). NOTE: author bodies with
    # only the braceless forms -- ${1:-default} / ${@:N} are written by pi, not
    # here, and a Nix `''...''` string would try to interpolate them.
    prompts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Shown in command completion. If empty, pi uses the first non-empty line of the body.";
          };
          argumentHint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional usage hint, e.g. \"<ticket | pr>\". Angle brackets = required, square brackets = optional. Omitted when null.";
          };
          body = lib.mkOption {
            type = lib.types.str;
            description = "The prompt text. $1/$2/$@/$ARGUMENTS are substituted with the user's arguments before the text is submitted.";
          };
        };
      });
      default = { };
      example = {
        card = {
          description = "Plan a pickupable task card";
          argumentHint = "<outcome-oriented title>";
          body = "Produce a pickupable task card for: $ARGUMENTS";
        };
      };
      description = "Prompt templates installed into the user's pi agent directory; each key becomes a / slash command.";
    };

    # User-level MCP servers -> ~/.pi/agent/mcp.json (pi docs/mcp.md).
    # Map: server name -> server config. Names may contain only letters,
    # digits, _ and -; each server needs a command (stdio) or a url (http).
    mcpServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          command = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Executable of a stdio server (one program, not a shell string). Mutually exclusive with url.";
          };
          args = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Arguments of a stdio server.";
          };
          env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Env vars for a stdio server. Values may use \${NAME} interpolation or !command.";
          };
          cwd = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Working directory of a stdio server; ~/... and relative paths resolve as pi documents.";
          };
          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Streamable-HTTP endpoint of a remote server. Mutually exclusive with command.";
          };
          headers = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "HTTP headers, e.g. { Authorization = \"Bearer \${TOKEN}\"; }. \${NAME} and !command allowed.";
          };
          description = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "One-sentence summary of what the server offers (shown in the system prompt).";
          };
          enabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Keep the entry but do not connect (pi's enabled: false).";
          };
          timeout = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Per-request timeout in seconds (pi defaults to 60).";
          };
          type = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ "stdio" "http" "streamable-http" ]);
            default = null;
            description = "Optional transport; pi infers stdio from command, http from url.";
          };
          exposure = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "How the server's tools reach the model (pi docs/mcp.md, tool exposure).";
          };
          toolExposure = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Per-tool exposure. Omitted; see pi docs/mcp.md for the expected shape.";
          };
        };
      });
      default = { };
      example = {
        filesystem = {
          command = "npx";
          args = [ "-y" "@modelcontextprotocol/server-filesystem" "." ];
          description = "Read and write files on this machine";
        };
        docs = {
          url = "https://example.com/mcp";
          headers = { Authorization = "Bearer \${DOCS_TOKEN}"; };
        };
      };
      description = "User-level MCP servers (pi docs/mcp.md), written to the user's ~/.pi/agent/mcp.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "" && config.users.users ? ${cfg.user};
        message = "pi.agent.user must name an existing users.users entry (got '${cfg.user}')";
      }
      {
        assertion = lib.all (name: builtins.match "[a-zA-Z0-9_-]+" name != null)
          (builtins.attrNames cfg.mcpServers);
        message = "pi.agent.mcpServers: server names may contain only letters, digits, _ and -";
      }
      {
        assertion = lib.all (s: s.command != null || s.url != null)
          (lib.mapAttrsToList (_: s: s) cfg.mcpServers);
        message = "pi.agent.mcpServers: each server needs a command (stdio) or a url (http)";
      }
    ];

    # Both files must live in the user's agent directory; symlink + chown
    # during activation (the same pattern used for other per-home agent
    # config). Each file is only touched if its data is actually configured.
    system.activationScripts.piAgent = ''
      ${lib.optionalString (hasModels || hasMcp || hasPrompts) ''
        mkdir -p "${home}/.pi/agent"
        chown ${cfg.user} "${home}/.pi/agent"
      ''}
      ${lib.optionalString hasModels ''
        ln -sf ${modelsJson} "${home}/.pi/agent/models.json"
        chown -h ${cfg.user} "${home}/.pi/agent/models.json"
      ''}
      ${lib.optionalString hasMcp ''
        ln -sf ${mcpJson} "${home}/.pi/agent/mcp.json"
        chown -h ${cfg.user} "${home}/.pi/agent/mcp.json"
      ''}
      ${lib.optionalString hasPrompts ''
        # -n: prompts is a *directory* symlink; treat any existing symlink-to-dir
        # as a file so relinking replaces rather than nests inside it.
        ln -sfn ${promptsDir} "${home}/.pi/agent/prompts"
        chown -h ${cfg.user} "${home}/.pi/agent/prompts"
      ''}
    '';
  };
}
