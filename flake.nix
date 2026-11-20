{
  description = "pi (Earendil coding agent) + local extensions";

  # Single input: pi on the `stable` branch. `flake.lock` will pin the exact
  # rev on first use. (Deliberately no separate `nixpkgs` input, to avoid
  # fetching a second nixpkgs onto this tight-disk box; pi carries its own.)
  inputs.pi.url = "github:earendil-works/pi/stable";

  outputs = { self, pi }@inputs:
    let
      system = "x86_64-linux"; # host; pi declares this + aarch64-linux
      piPkg = pi.packages.${system}.default;
    in
    {
      # Re-export pi's own app + package outputs into this flake so the usual
      # entry points work against pi: `nix run .#pi`, `nix build .#pi`, etc.
      apps.${system} = pi.apps.${system};
      packages.${system} = {
        default = piPkg;
        pi = piPkg;
      };

      # Authoring note (README.md has more):
      #   - pi loads .ts extensions at runtime via jiti -> NO build step needed.
      #   - run/author with:  nix run .#pi -- <args>
      #   - activate a local extension: link extensions/<name> into
      #     ~/.pi/agent/extensions/ (see README.md).
      # If you later want a Nix devShell too (when disk permits), add a
      # `nixpkgs` input and a `devShells` entry here that adds pi + nodejs.
    };
}
