# pi — local extensions workspace

A Nix workspace around [pi](https://pi.dev), Earendil's minimal coding-agent
(CLI/TUI). pi is pulled in as a **flake input**; `extensions/` is where you
build your own.

**There is no TypeScript build step.** pi loads `.ts` extensions at runtime via
`jiti`, so the extensions are plain `.ts` files — no `tsc`, no `dist/`.

## extensions/

- **`hello/`** — demo: a `/hello` command, a `greet` tool, a `session_start` notice. Proof that a local `.ts` extension loads.
- **`rm-guard/`** — before pi runs a **destructive** bash command (`rm` and same-weight: `git reset --hard`, `git push --force`, `git clean -f`, `find -delete`, `dd`, `mv -f`, `chmod`/`chown -R`, `truncate -s0`, raw-disk redirects), it pauses for a **yes/no** confirm; `no` blocks the call. Always asks (no allow-list). Scope + rules live in `rm-guard/src/index.ts`.

> **Prompt-shorthand commands are not extensions.** `/card`, `/planning`,
> `/investigate`, and `/worktree` are pi **prompt templates** (a markdown file:
> frontmatter + a body that pi expands against your arguments and *submits to
> the model*). An extension that only `ctx.ui.notify()`s just prints to the UI
> and never reaches the model — that's why those four were templates, not
> `.ts`. They are Nix-managed: the mechanism is the `pi.agent.prompts` option
> in `modules/agent.nix` (installed to `~/.pi/agent/prompts/<name>.md`), and
> the actual commands are configured per-machine in the dotfiles
> (`a-smol-workstation/workstation-specific.nix`).

## Layout

```
flake.nix              # pulls pi (stable) as a flake input; re-exports its
                       #   app + package outputs (no devShell)
extensions/<name>/     # one directory per extension
  package.json         # { "pi": { "extensions": ["./src/index.ts"] } }
  src/index.ts         # default-exported factory (pi: ExtensionAPI) => ...
```

## Use

```
nix run .#pi          # run pi  (same as `nix run .#default`)
nix build .#pi        # build the pi package
```

## Activate an extension (verified)

Simplest, and what `pi list` shows: install the extension directory into pi's
user settings so it loads in every run:

```
pi install /home/max/pi/extensions/hello   # register it
pi list                                    # confirm it's listed
pi remove  /home/max/pi/extensions/hello   # take it out
```

(use any `pi` on PATH, or the Nix-built one: `nix run .#pi -- install ...`).

Other ways (see pi's `docs/extensions.md`):
- Link into the global discovery dir: `ln -sfn <dir> ~/.pi/agent/extensions/<name>`
- Per-run, without touching settings: `pi -e <path-or-dir> -- ...`
- Project-local (cwd, after trust): `.pi/extensions/...`
- Remote: `pi install git:...` / `pi install npm:...`

> Note: an *interactive* session needs a logged-in provider — a fresh install
> warns "No models available" until you `pi auth ...` / `/login`. Registering
> extensions (`pi install` / `pi list`) works without one.

## Day-one (no Nix build)

pi is also published to npm, so you can try an extension immediately without
building it via Nix (handy while sorting out disk space):

```
bun add -g --ignore-scripts @earendil-works/pi-coding-agent
# or: npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

then link the extension into `~/.pi/agent/extensions/` as above and run `pi`.

## Publishing an extension

Each `extensions/<name>/` is already a valid package. Push this repo and,
anywhere:

```
pi install git:github.com/<you>/<this-repo>
```

## Notes

- pi is pinned to the `stable` branch (currently `pi-1.6.0`); `flake.lock`
  records the exact rev on first use.
- There is deliberately **no separate `nixpkgs` input** — pi carries its own,
  so we don't fetch a second nixpkgs on this disk-constrained box. Add one
  back with a `devShells` entry if you later want a Nix dev shell.
