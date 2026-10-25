---
name: pi-profile
description: >
  Create or audit a Pi agent profile in the user's harness-dots repo (~/Dotfiles/harness-dots): the pi/agent_<name>
  directory, its appended system prompt, its own extensions, the pi-<name> bash entry point that launches it,
  and the matching Paseo provider. Use when the user wants a new Pi profile, "agent_<name>", a purpose-specific
  agent, a `pi-<name>` command, per-profile extensions, or a system prompt, skills or MCP servers bundled into a
  launchable profile.
---

# Authoring a Pi profile (harness-dots)

The user keeps each Pi profile as a directory in `harness-dots`, selected by `PI_CODING_AGENT_DIR`,
and launches it through a small bash entry point in `harness-dots/pi/bash/`. `harness-dots/pi/` is
Pi's config home. The same entry points are what Paseo launches: each profile becomes a Paseo
provider in `paseo/config.json` (see the `harness-dots-paseo` skill). The repo also holds omp
(oh-my-pi) config under `omp/`; read the repo's `AGENTS.md` for the cross-harness conventions.

A new profile is four coordinated pieces: the profile dir (with its own `settings.json`), a system
prompt, the entry point, and the Paseo provider; logins are copied in separately. `scripts/scaffold.py` does the
mechanical parts and `paseo/gen-pi-providers.py` the Paseo part. You author the system prompt and
decide what goes inside the profile.

## The conventions

All paths are relative to the harness-dots checkout (`~/Dotfiles/harness-dots`). The scripts find it
themselves, so nothing relies on an environment variable.

| Thing | Location |
|---|---|
| Profile | `pi/agent_<name>/` (hyphens in the name become `_`) |
| System prompt | `system-prompts/append_<name>_0.md` at the repo root, shared by all harnesses (trailing number is a revision) |
| Entry point | `pi/bash/pi-<name>`, executable, built from the template below |
| Shared launcher | `pi/bash/_launch.bash` (sourced by every entry point; never edit per profile), which sources the repo-wide `bash/_common.bash` |
| Installer | `install.sh` (repo root) symlinks every entry point in `*/bash/` onto PATH (`~/.local/bin`) |
| Settings and extensions | `pi/agent_<name>/settings.json`, the profile's own file, tracked |
| Logins | `pi/agent_<name>/auth.json` and `models.json`, gitignored, copied between profiles by `pi/copy-auth.sh` |
| Paseo provider | `agents.providers["pi-<name>"]` in `paseo/config.json`, written by `paseo/gen-pi-providers.py` |

The vanilla profile is `pi/agent/` with entry point `vpi`; in Paseo it overrides the built-in `pi`
provider. It is named so that it never shadows the real `pi` binary; no entry point may be called `pi`.

### Extensions and settings are per profile

Each profile has its own `settings.json`; it holds the profile's Pi package declarations
(`packages`), so profiles differ in which extensions they load. Install into one profile through its
entry point, which routes Pi's subcommands to that profile:

```bash
pi-<name> install npm:some-pi-package     # writes pi/agent_<name>/settings.json, installs under its npm/
pi-<name> list
pi-<name> remove npm:some-pi-package
```

Never `vpi install` something meant for another profile, and never install with a bare `pi`: that
uses whatever `PI_CODING_AGENT_DIR` happens to be set, or `~/.pi/agent`.

- Profile `settings.json` files are tracked, so the package list is reproducible. Pi also writes
  small runtime values there (`lastChangelogVersion`, `defaultModel`); they're committed with the
  rest. Never symlink `settings.json` between profiles.
- `scaffold.py` creates `settings.json` as `{}` so the profile has its own from the start.
- Local extensions can also live in `pi/agent_<name>/extensions/` (Pi discovers that dir); those are
  tracked.

### Tracked inside a profile

Only what is *authored* is tracked:

- `skills/<skill>/` : skills copied in whole (a directory containing `SKILL.md`). Pi discovers
  `$PI_CODING_AGENT_DIR/skills/` on its own. Copy rather than symlink so the dotfiles stand alone.
- `prompts/*.md` : slash-command prompt templates (frontmatter `description`, `argument-hint`).
- `extensions/` : local extension files.
- `mcp.json` : MCP servers. `pi/agent/mcp.json` is the reference: `donsetch` enabled, `agent-browser`
  present but disabled.
- `settings.json` : the profile's settings and extensions (see above).
- Runtime state (`auth.json`, `models*.json`, `sessions`, `npm`, `trust.json`, ...) is gitignored
  already. Never commit it. Never create a `bin/` under `pi/`: `pi/.gitignore` ignores
  that name (Pi keeps its own `bin` under a profile), which is why the entry points live in `pi/bash/`.

### The entry point

Every entry point has the same shape, and the only part that varies is the `PROFILE` block:

```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# Pi <label> agent            <- line 3: Paseo shows this as the provider label
...
pi-<name>() {
  # --- PROFILE ---------------------------------------------------------------
  local profile=agent_<name>
  local prompt=append_<name>_0.md   # a file in system-prompts/; "" for none
  local -a env_extra=()             # extra environment for this profile, e.g. (NAME=value)
  # ---------------------------------------------------------------------------
  _pi_launch "$profile" "$prompt" "${env_extra[@]}" -- "$@"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then pi-<name> "$@"; fi
```

The file works two ways: run it (symlinked onto PATH, usable from scripts, cron and Paseo) or
`source` it to define the function. `_pi_launch`:

- scrubs every variable pi and omp share (`bash/_common.bash`) and sets `PI_CODING_AGENT_DIR` for
  that one command only;
- adds `--append-system-prompt` unless the first argument is a Pi subcommand (`install`, `remove`,
  `uninstall`, `update`, `list`, `config`, `auth`, `mcp`). Paseo's launches start with `--mode rpc`,
  so they get the prompt;
- refuses to run if the prompt file is missing (Pi would otherwise append the path as literal text);
- runs the real `pi` via `_dots_real_bin`, which follows a mise shim to the real binary. A shim
  re-applies mise's `[env]` after the scrub, and shims come first on PATH under Paseo's systemd unit.

`paseo/gen-pi-providers.py` reads these files, so keep the shape: executable, no leading `_`, no
`.bash` extension, a `# --- PROFILE ---` block containing `local profile=...`, and the label comment
on line 3. Use `scaffold.py` instead of writing the file by hand; it renders exactly this template.

### Environment rules

- Never export `PI_CODING_AGENT_DIR` or any other harness selector globally: not in `~/.bashrc`,
  not in mise `[env]` (`~/.config/mise/config.toml` and its tracked copy in `mise-dots`), not in a
  systemd unit. A global value in mise `[env]` used to override every shim-launched profile.
- Per-profile variables go in the entry point's `env_extra`. Paseo needs nothing more: its provider
  entry only adds `PI_CODING_AGENT_DIR` so Paseo's own reads (MCP config, session import) match.
- Do not add mise tasks for a profile; the entry points replaced them. Never wire `omp` to a `pi/`
  profile: it shares `PI_CODING_AGENT_DIR` and would pollute Pi's config and sessions.

## Workflow

1. **Gather**: a short `name` (lowercase, hyphens ok; it becomes the command and Paseo provider id
   `pi-<name>`), a `label` for the header ("video producer"), what the agent is for, which skills it
   should bundle (and where from), which extensions it should install, whether it should get an
   `mcp.json`, and any per-profile environment variables. If the purpose is clear from the request,
   pick the defaults below and say so instead of asking.
2. **Author the system prompt** to `system-prompts/append_<name>_0.md` *before* scaffolding (the
   script refuses to proceed without it). Read `append_ctf_0.md` and `append_producer_0.md` for
   tone. Write it as an **append** to Pi's default coding prompt, so it describes the role, not the
   harness. Good structure: one-paragraph role and who the user is to it; tooling and defaults
   (name the bundled skill and say to load it first); working style (verify output, keep originals
   intact); boundaries (what needs asking first, privacy, licensing, scope); communication. Keep it
   concrete and under about 60 lines; every rule should be one the agent would otherwise get wrong.
3. **Scaffold** (dry run first, and show the plan):

   ```bash
   python3 ~/Dotfiles/harness-dots/skills/pi-profile/scripts/scaffold.py NAME \
     --label "video producer" \
     --skill /path/to/skill-dir [--skill ...] \
     [--mcp copy] [--env NAME=value ...] [--copy-auth] [--dry-run]
   ```

   It creates the profile dir with its own `settings.json` (`{}`), copies each `--skill`, optionally
   copies `pi/agent/mcp.json`, and renders `pi/bash/pi-<name>` (mode 755). It skips any step
   already done, so rerunning is safe. `--copy-auth` runs `pi/copy-auth.sh --to agent_<name>`,
   copying the vanilla profile's `auth.json` / `models.json` in; use it when the user wants the new
   profile logged in like the others. It does not touch `~/.local/bin` or Paseo.
4. **Extensions**: `pi/bash/pi-<name> install npm:<pkg>` for each one (this writes into the user's
   real profile and downloads packages; do it when the user asked for those extensions).
5. **Paseo provider**: `paseo/gen-pi-providers.py --dry-run`, show the new `pi-<name>` entry, then
   run it without `--dry-run`. That edits only the tracked `paseo/config.json`. Applying it to the
   live Paseo config (`paseo/install.sh`) writes into `~/.paseo`: offer it, run it only when asked
   (`harness-dots-paseo` skill).
6. **Verify** and show the evidence:
   - `bash -n pi/bash/pi-<name>`;
   - `./install.sh --only pi-<name> --dry-run` shows the link it would make (run it for real only if
     the user says so; it writes into their home directory);
   - a launch smoke test against the real binary needs no session: `pi/bash/pi-<name> --version`
     and `pi/bash/pi-<name> list`;
   - `paseo/gen-pi-providers.py --check` passes;
   - `git -C ~/Dotfiles/harness-dots status --short` shows only the expected changes.
7. **Report**: files created, the command name, whether it is linked onto PATH, whether the Paseo
   provider is generated and installed, and the defaults you chose. **Do not commit** unless the user
   asks.

Removing a profile: delete its entry point and directory (after asking; the directory holds
sessions and logins), rerun `paseo/gen-pi-providers.py` (it
drops the provider from `paseo/config.json`), and remove the provider from live Paseo in the app or
with `paseo/install.sh --replace`, since the default merge keeps live-only providers.

## Defaults when unspecified

- No `mcp.json` (offer to copy `pi/agent/mcp.json`); no extensions; prompt revision `_0`; no extra
  environment; entry point not linked onto PATH; Paseo provider generated but not installed.
- Skills the user names are copied whole, including `references/` and `scripts/`. A skill that is a
  router for sibling skills (like `hyperframes`) is copied alone; don't pull in siblings unasked.
- Never put credentials, tokens or API keys in a profile, an entry point or `paseo/config.json`;
  they belong in the gitignored runtime files Pi creates itself.

## Auditing an existing profile

Check the pieces exist and agree: the `pi/agent_<name>/` dir and its own tracked (non-link)
`settings.json`, the prompt file named in the entry point's `PROFILE` block, the entry point's mode
(755), `bash -n` and line-3 label, whether `auth.json` / `models.json` are real files (not leftover
symlinks to a shared file; `pi/copy-auth.sh` replaces those), whether `install.sh` has linked it,
and the Paseo provider (`paseo/gen-pi-providers.py --check`). Report gaps and offer fixes; don't
rewrite a profile's prompt or settings unasked.

## Sandbox note

When running under a sandbox, the harness-dots repo may be outside the project directory and writes
there need the sandbox lifted for that command. Request it for the scaffold run only. Writes to
`~/.paseo`, `~/.local/bin` and `~/.config` are outside it too.
