# AGENTS.md: conventions for harness-dots

`harness-dots` (`~/Dotfiles/harness-dots`) is a catch-all for coding-agent **harness** configuration.
Today it holds two harnesses:

- **pi** ([pi.dev](https://pi.dev)), whose config home is `pi/`
- **omp** (oh-my-pi, [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi), a pi derivative),
  whose config home is `omp/`

Each harness's directory **is** that harness's global configuration: the launchers point the
harness straight at it, so neither `~/.pi` nor `~/.omp` is used. The two harnesses share ancestry and
many environment variables. The rule this layout exists to enforce:
**one harness must never read or write another harness's config, sessions or state.**

## Layout

```text
harness-dots/
├── AGENTS.md            this file
├── README.md            user-facing overview
├── install.sh           links every harness's entry points onto PATH
├── .gitignore           repo-wide safety net (credentials, *.db, .env)
├── bash/                GLOBAL bash, shared by all harnesses
│   ├── _common.bash     env-isolation helpers every launcher sources
│   └── rc.bash          source from ~/.bashrc; sources each <harness>/bash/rc.bash
├── system-prompts/      harness-agnostic appended system prompts
├── skills/              harness-agnostic skills (and skills for authoring this repo)
├── pi/                  pi's config home
│   ├── .gitignore       pi runtime state (blocklist)
│   ├── settings.json    shared pi settings, symlinked into each profile
│   ├── link.sh          creates those settings symlinks
│   ├── agent/           profile dirs: each one *is* a PI_CODING_AGENT_DIR
│   ├── agent_<name>/
│   └── bash/            _launch.bash, rc.bash, entry points (vpi, pi-ctf, pi-producer)
└── omp/                 omp's config root (PI_CONFIG_DIR points here)
    ├── .gitignore       allowlist: only authored config is trackable
    ├── agent/           default profile
    ├── profiles/<name>/agent/   named profiles (omp's native profile layout)
    └── bash/            _launch.bash, rc.bash, entry points (vomp)
```

### What goes where

- **Repo root**: only what is harness-agnostic (`system-prompts/`, `skills/`), plus the glue that
  spans harnesses (`bash/`, `install.sh`). A prompt or skill written for one harness but usable by
  both stays at the root.
- **`<harness>/`**: anything only that harness reads: settings files, profile dirs, MCP config,
  prompt templates, its `.gitignore`, any link script it needs, and its bash.
- A new harness gets a new top-level directory with the same shape (`bash/_launch.bash`,
  `bash/rc.bash`, entry points, `.gitignore`). `install.sh` and `bash/rc.bash` discover `*/bash/`
  on their own, so they need no edits.

## Bash

Three layers, each sourcing the one below:

1. **`bash/rc.bash`** (global). Source it from `~/.bashrc`. It sources `<harness>/bash/rc.bash` for
   every harness; `DOTS_HARNESSES="pi"` limits that. Shell settings meant for all harnesses go here.
2. **`<harness>/bash/rc.bash`**. Interactive config for one harness. It defines a function for every
   entry point in that directory. Harness-only aliases and completions go here.
3. **Entry points** (`pi/bash/vpi`, `omp/bash/vomp`, ...). Executable, no extension, no leading
   underscore. Each one works two ways: **run** it (`install.sh` symlinks it into `~/.local/bin`) or
   **source** it (defines a function of the same name). The only part that varies between entry
   points is the marked `PROFILE` block. Everything else lives in that harness's
   `bash/_launch.bash`, which sources the global `bash/_common.bash`.

Naming: an entry point is never named after the real binary (`pi`, `omp`); the launcher runs the
first real binary on PATH, so a same-named wrapper would recurse. The vanilla wrappers are `vpi` and
`vomp`; profile wrappers are `<harness>-<name>` (`pi-ctf`, and `omp-ctf` if one is ever added).
Names must be unique across harnesses, since they all land in one bin dir.

Files ending in `.bash` or starting with `_` are libraries: sourced, never linked onto PATH.

## Environment isolation

Variables both harnesses read: `PI_CODING_AGENT_DIR`, `PI_PACKAGE_DIR`, `PI_SESSION_FILE`,
`PI_CACHE_RETENTION`, `PI_TIMING`, `PI_HARDWARE_CURSOR`, `PI_TUI_WRITE_LOG`. omp also reads
`PI_CONFIG_DIR`, `OMP_PROFILE`/`PI_PROFILE`, `PI_CONFIG_FILES` and `PI_CODING_AGENT_SESSION_DIR`,
and it exports `PI_CODING_AGENT_DIR` to its own child processes.

So every launcher:

1. **Scrubs** every variable in `_DOTS_HARNESS_VARS` (`bash/_common.bash`) with `env -u`. That
   covers whatever another harness, a parent agent session or an env manager such as mise left
   behind.
2. **Sets only its own selectors**, for that one process:
   - pi: `PI_CODING_AGENT_DIR=<repo>/pi/<profile>`. Pi has no profile system and no config root
     beyond the agent dir, so each profile dir *is* the agent dir.
   - omp: `PI_CONFIG_DIR=<repo>/omp` (written relative to `$HOME`, see below) and
     `OMP_PROFILE=<name>`, empty for the default profile. omp then resolves `omp/agent/` or
     `omp/profiles/<name>/agent/` itself. The omp launcher never sets `PI_CODING_AGENT_DIR`: that
     is pi's selector, omp honours it only for the default profile, and even then omp's root-level
     state would stay in `~/.omp`.
3. Adds the profile's `env_extra` (from its `PROFILE` block) last.

Never export any harness variable globally (in `~/.bashrc`, mise `[env]` or similar). If a
variable is needed, put it in the profile's `env_extra`. Do not add a variable to the scrub list
unless it selects a harness's config, profile or session; user preferences such as
`PI_CACHE_RETENTION` pass through.

`PI_CONFIG_DIR` is always joined onto `$HOME` (by omp's JS and its native Rust code alike), so it
must be a *relative* path. An absolute value is re-rooted: `/home/$USER/.omp` becomes
`~/home/$USER/.omp`. The launcher computes the relative path itself, so the repo can live anywhere.

Two omp paths ignore `PI_CONFIG_DIR`. The native-addon cache defaults to `~/.omp/natives`, so
the launcher sets `PI_NATIVES_DIR=<repo>/omp/natives` unless you already set it. The browser
tool's `saveState()` without an explicit path writes `~/.omp/browser-state/` (hardcoded upstream).

Side effect of a non-default `PI_CONFIG_DIR`: omp also uses its name for project-scoped plugin
registries (`<project>/<PI_CONFIG_DIR>/plugins/installed_plugins.json`), so under `vomp` those
registries resolve under a path like `<project>/Dotfiles/harness-dots/omp/` instead of
`<project>/.omp/`. Other project config (`<project>/.omp/config.yml`, skills, rules) is unaffected.

## Runtime state and .gitignore

Both harnesses write runtime state (sessions, auth, databases, caches) into their config home,
which is inside this repo, so each harness dir has its own `.gitignore`:

- `pi/.gitignore` is a **blocklist**: pi's footprint is small and known.
- `omp/.gitignore` is an **allowlist**: omp writes dozens of paths (worktrees, python envs,
  browser profiles, natives, logs, caches) and adds more each release. Only authored config is
  trackable: `config.yml`, `mcp.json`, `lsp.json`, `keybindings.*`, `skills.json` /
  `skills.lock.json` (skills installed with `omp skill install`), the `*.md` prompt files
  (`AGENTS.md`, `SYSTEM.md`, ...), the `skills/`, `commands/`, `prompts/`, `rules/`, `hooks/`,
  `tools/`, `agents/`, `themes/` and `extensions/` dirs, and `plugins/package.json` (the npm
  plugin manifest). `secrets.yml`, `models.yml`, `.env`, `*.token` and `managed-skills/`
  (auto-learned from sessions) stay ignored on purpose. To track something new, add it to the
  allowlist.
- Allowed files can still carry secrets: `config.yml` accepts credential settings
  (`auth.broker.token`, `searxng.token`, `hindsight.apiToken`, ...) and `mcp.json` accepts
  `env`/`headers`. Write those as `${VAR}`, `$VAR` or `!command` references and keep the values
  in the ignored `omp/agent/.env`. Review `git diff --cached` on these files before committing.
- The root `.gitignore` is a safety net for both: `auth.json`, `*.token`, `.env*`, `*.db*`.

## Profiles

| | pi | omp |
|---|---|---|
| Config home | `pi/` | `omp/` |
| Profile dir | `pi/agent_<name>/` (`pi/agent/` for vanilla) | `omp/profiles/<name>/agent/` (`omp/agent/` for default) |
| Settings file | `settings.json` (shared `pi/settings.json`, symlinked by `pi/link.sh`) | `config.yml` |
| Selected by | `PI_CODING_AGENT_DIR` | `PI_CONFIG_DIR` + `OMP_PROFILE` |
| Entry point | `pi/bash/pi-<name>` | `omp/bash/omp-<name>` |
| Prompt flag | `--append-system-prompt`, skipped for pi subcommands | `--append-system-prompt`, always (omp drops it for subcommands) |

Appended system prompts live in `system-prompts/append_<name>_<rev>.md` and are named in the entry
point's `PROFILE` block. The launcher refuses to start if the file is missing, because both
harnesses would otherwise append the path as literal text.

The `skills/pi-profile` skill scaffolds pi profiles (`scripts/scaffold.py`). There is no omp
scaffold yet; copy `omp/bash/vomp`, set `profile=<name>` in its `PROFILE` block, and put tracked
config in `omp/profiles/<name>/agent/`.

## Rules for agents working in this repo

- Never commit runtime state or credentials: `auth.json`, `sessions/`, `*.db`, `models*.json`,
  `models.yml`, `secrets.yml`, `.env`. Check `git status` before staging.
- Never point one harness at another harness's directory, and never wire a pi profile into an omp
  launcher or the reverse. Don't point either harness at `~/.pi` or `~/.omp`.
- `install.sh` and `pi/link.sh` write outside the files they live next to (`~/.local/bin`, profile
  dirs). Run `install.sh --dry-run` first, and run either for real only when the user asks.
- The global mise config (`~/.config/mise/config.toml`, from the mise-dots repo) used to hold
  harness tasks; they are being moved here. Don't add new harness tasks there.
- Verify bash changes with `bash -n` on every touched file, plus a smoke test through the real
  binary (`vpi --version`, `vomp --version`).
- Don't commit unless the user asks.
