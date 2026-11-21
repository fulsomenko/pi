# Purpose: point pi (the coding agent) at a custom model endpoint (Ollama, LM Studio,
#          vLLM, ...) by installing a models.json into the pi agent directory
#          (~/.pi/agent on the given user). See pi docs/models.md, "Configure a
#          compatible endpoint" and docs/configuration.md, "Agent directory".
# Platform: NixOS
# Options:  pi.agent.enable
#           pi.agent.user
#           pi.agent.provider
#           pi.agent.baseUrl
#           pi.agent.api
#           pi.agent.apiKey
#           pi.agent.models
{ config, lib, pkgs, users, ... }:

let
  cfg = config.pi.agent;

  modelToJson = m:
    { id = m.id; }
    // lib.optionalAttrs (m.name != null) { name = m.name; }
    // lib.optionalAttrs (m.contextWindow != null) { contextWindow = m.contextWindow; }
    // lib.optionalAttrs (m.maxTokens != null) { maxTokens = m.maxTokens; }
    // lib.optionalAttrs (m.reasoning != null) { reasoning = m.reasoning; };

  modelsJson = pkgs.writeText "pi-models.json" (builtins.toJSON {
    "$schema" = "https://pi.dev/schemas/models.schema.json";
    providers.${cfg.provider} = {
      inherit (cfg) baseUrl api apiKey;
      models = map modelToJson cfg.models;
    };
  });
in
{
  options.pi.agent = {
    enable = lib.mkEnableOption "a pi models.json pointing at a custom model endpoint";

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

    models = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf {
        id = lib.types.str;
        name = lib.types.nullOr lib.types.str;
        contextWindow = lib.types.nullOr lib.types.int;
        maxTokens = lib.types.nullOr lib.types.int;
        reasoning = lib.types.nullOr lib.types.bool;
      });
      default = [ ];
      example = [
        { id = "qwen3-coder:30b"; contextWindow = 65536; maxTokens = 32000; }
      ];
      description = "Models the endpoint exposes. Entries not set are omitted (pi applies schema defaults).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "";
        message = "pi.agent.user must be set to an existing users.users entry";
      }
    ];

    # models.json must live in the user's agent directory; symlink + chown it
    # during activation (the same pattern used for other per-home agent config).
    system.activationScripts.piAgent = ''
      mkdir -p "${users.users.${cfg.user}.home}/.pi/agent"
      chown ${cfg.user} "${users.users.${cfg.user}.home}/.pi/agent"
      ln -sf ${modelsJson} "${users.users.${cfg.user}.home}/.pi/agent/models.json"
      chown -h ${cfg.user} "${users.users.${cfg.user}.home}/.pi/agent/models.json"
    '';
  };
}
