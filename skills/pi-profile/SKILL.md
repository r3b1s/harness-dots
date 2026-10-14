---
name: pi-profile
description: >
  Create or audit a Pi agent profile in the user's harness-dots repo (~/Dotfiles/harness-dots): the pi/agent_<name>
  directory, its appended system prompt, and the pi-<name> bash entry point that launches it. Use when
  the user wants a new Pi profile, "agent_<name>", a purpose-specific agent, a `pi-<name>` command, or
  a system prompt, skills or MCP servers bundled into a launchable profile.
---

# Authoring a Pi profile (harness-dots)

The user keeps each Pi harness profile as a directory in `harness-dots`, selected by `PI_CODING_AGENT_DIR`,
and launches it through a small bash entry point in `harness-dots/pi/bash/`. `harness-dots/pi/` is
Pi's config home. The repo also holds omp (oh-my-pi) config under `omp/`; read the repo's
`AGENTS.md` for the cross-harness conventions. A new profile is four
coordinated pieces: the profile dir, a system prompt, the entry point, and `link.sh` / `.gitignore`
bookkeeping. `scripts/scaffold.py` does the mechanical parts. You author the system prompt and decide
what goes inside the profile.

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
| Shared settings | `pi/settings.json`, symlinked into each profile by `pi/link.sh` and gitignored per profile in `pi/.gitignore` |

The vanilla profile is `pi/agent/` with entry point `vpi`. It is named so that it never shadows the
real `pi` binary; no entry point may be called `pi`.

Inside a profile only what is *authored* is tracked:

- `skills/<skill>/` : skills copied in whole (a directory containing `SKILL.md`). Pi discovers
  `$PI_CODING_AGENT_DIR/skills/` on its own. Copy rather than symlink so the dotfiles stand alone.
- `prompts/*.md` : slash-command prompt templates (frontmatter `description`, `argument-hint`).
- `mcp.json` : MCP servers. `pi/agent/mcp.json` is the reference: `donsetch` enabled, `agent-browser`
  present but disabled.
- `settings.json` : a symlink to the shared file, gitignored.
- Runtime state (`auth.json`, `sessions`, `models.json`, `npm`, ...) is gitignored already. Never
  create or commit it. Also never create a `bin/` under `pi/`: `pi/.gitignore` ignores that
  name (Pi keeps its own `bin` under a profile), which is why the entry points live in `pi/bash/`.

### The entry point

Every entry point has the same shape, and the only part that varies is the `PROFILE` block:

```bash
pi-<name>() {
  # --- PROFILE ---
  local profile=agent_<name>
  local prompt=append_<name>_0.md   # a file in system-prompts/; "" for none
  local -a env_extra=()             # extra environment for this profile, e.g. (NAME=value)
  # ---
  _pi_launch "$profile" "$prompt" "${env_extra[@]}" -- "$@"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then pi-<name> "$@"; fi
```

The file works two ways: run it (symlinked onto PATH, usable from scripts and cron) or `source` it to
define the function. `_pi_launch` scrubs every variable pi and omp share (`bash/_common.bash`), sets `PI_CODING_AGENT_DIR` for that one command only, adds
`--append-system-prompt` unless the first argument is a Pi subcommand (`install`, `remove`,
`uninstall`, `update`, `list`, `config`, `auth`, `mcp`), refuses to run if the prompt file is missing
(Pi would otherwise append the path as literal text), and runs the first real `pi` found on PATH. So
there are no `-install` / `-uninstall` helpers: `pi-<name> install npm:pkg` is the way.

Use `scaffold.py` instead of writing the file by hand; it renders exactly this template.

### Legacy mise tasks

The global mise config (`~/.config/mise/config.toml`, a symlink to `~/Dotfiles/mise-dots/config.toml`)
may still carry older `pi`, `pi-ctf*` and `pi-producer*` tasks from before the bash entry points
(the `omp` task has already moved to `omp/bash/vomp`).
They are superseded. **Do not add mise tasks for a new profile.** Do not remove the old ones unless
the user asks; that repo often has their own uncommitted edits, so look at `git diff` first and
report rather than bundle or revert them. Never wire `omp` (oh-my-pi) to a `pi/` profile:
it shares `PI_CODING_AGENT_DIR` and would pollute Pi's config and sessions. omp profiles live in `omp/`.

## Workflow

1. **Gather**: a short `name` (lowercase, hyphens ok), a `label` for the header ("video producer"),
   what the agent is for, which skills it should bundle (and where to copy them from), whether it
   should get an `mcp.json`, and any per-profile environment variables. If the purpose is clear
   from the request, pick the defaults below and say so instead of asking.
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
     [--mcp copy] [--env NAME=value ...] [--link] [--dry-run]
   ```

   It creates the profile dir, copies each `--skill`, optionally copies `pi/agent/mcp.json`, renders
   `pi/bash/pi-<name>` (mode 755), appends the `pi<N>` variable and `link` line to `pi/link.sh`, and adds
   `agent_<name>/settings.json` to `pi/.gitignore`. It skips any step already done, so rerunning is
   safe. `--link` also symlinks the shared `settings.json` into the new profile; omit it if the
   other profiles aren't linked on this machine (check). It does not touch `~/.local/bin`.
4. **Verify** and show the evidence:
   - `bash -n pi/bash/pi-<name>`;
   - `./install.sh --only pi-<name> --dry-run` shows the link it would make (run it for real only if
     the user says so; it writes into their home directory);
   - a launch smoke test against the real binary needs no session:
     `PATH=<dir containing the link>:$PATH pi-<name> --version` and `pi-<name> list`;
   - `git -C ~/Dotfiles/harness-dots status --short` shows only the expected changes.
5. **Report**: files created, the command name, whether it is linked onto PATH yet, and the defaults
   you chose. **Do not commit** unless the user asks.

## Defaults when unspecified

- No `mcp.json` (offer to copy `pi/agent/mcp.json`); settings symlink not created; prompt revision `_0`;
  no extra environment; entry point not linked onto PATH.
- Skills the user names are copied whole, including `references/` and `scripts/`. A skill that is a
  router for sibling skills (like `hyperframes`) is copied alone; don't pull in siblings unasked.
- Never put credentials, tokens or API keys in a profile; they belong in the gitignored runtime
  files Pi creates itself.

## Auditing an existing profile

Check the five pieces exist and agree: the `pi/agent_<name>/` dir, the prompt file named in the entry
point's `PROFILE` block, the entry point's mode (755) and `bash -n`, the `pi/link.sh` and `pi/.gitignore`
lines, and whether `install.sh` has linked it. Report gaps and offer fixes; don't rewrite a
profile's prompt or settings unasked.

## Sandbox note

When running under a sandbox, the harness-dots repo may be outside the project directory and writes
there need the sandbox lifted for that command. Request it for the scaffold run only.
