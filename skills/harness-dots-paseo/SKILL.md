---
name: harness-dots-paseo
description: >
  Manage the user's tracked Paseo config in harness-dots (~/Dotfiles/harness-dots/paseo): config.json,
  install.sh and gen-pi-providers.py, and how harness-dots Pi profiles become Paseo providers and agent
  profiles. Use when the user wants to change Paseo settings or providers through their dotfiles, expose a
  Pi profile in Paseo, sync paseo/config.json with ~/.paseo/config.json, or debug a Paseo Pi agent that loads
  the wrong profile, extensions or ~/.pi/agent. Not for operating Paseo agents (use the paseo skill) or
  general Paseo product questions (paseo-help).
---

# Paseo config in harness-dots

[Paseo](https://paseo.sh) is a daemon that runs coding agents (Pi among them) and is driven from its
desktop app, web UI, CLI and MCP tools. The user tracks its settings in `harness-dots/paseo/` and
exposes each Pi profile from `harness-dots/pi/` as a Paseo provider. Read the repo's `AGENTS.md`
(sections *Paseo* and *Environment isolation*) for the full conventions. To create the Pi profile
itself, use the `pi-profile` skill.

## Layout and the one rule

| Path | Role |
|---|---|
| `paseo/config.json` | tracked source for Paseo's settings |
| `paseo/install.sh` | merges it into the live `$PASEO_HOME/config.json` |
| `paseo/gen-pi-providers.py` | writes one provider per Pi entry point into `paseo/config.json` |
| `~/.paseo/` | Paseo's home (`PASEO_HOME`, set by the systemd unit `~/.config/systemd/user/paseo.service`): live `config.json`, runtime state, keys, logs |

**The live config is a copy, never a link, and nothing flows back automatically.** The daemon writes
UI changes and the daemon password (`daemon.auth`, a hash) into `~/.paseo/config.json`; a symlink
would put those in git. Do not move `PASEO_HOME` into the repo, do not symlink `config.json`, and
never copy `daemon.auth` into `paseo/config.json` (`install.sh` refuses to install it). To keep a
change the user made in the app, copy that key into `paseo/config.json` by hand and show the diff.

`~/.paseo/config.json` is Paseo's only settings file: `agents.providers` (custom providers),
`daemon.agentProfiles` (agent profiles made in the UI), daemon settings (`listen`, `cors`, `relay`,
`mcp`), `app`, `features`. There is no `${VAR}` expansion, so provider `env` values are literal: a
provider that needs an API key does not belong in the tracked file. Ask the user where it should go.

## Pi profiles as Paseo providers

Paseo has two kinds of profile, and only one can select a Pi config dir:

- **Agent profile** (Settings → host → Agents → Agent profiles; `daemon.agentProfiles`): provider,
  model, mode, thinking level, feature values, notes. No environment, no command.
- **Custom provider** (`agents.providers.<id>`): `extends`, `label`, `command`, `env`, `models`,
  `additionalModels`, `disallowedTools`, `enabled`, `order`, `options`.

So each Pi profile is a provider, and agent profiles pick one of them plus a model and notes.
`gen-pi-providers.py` derives the providers from `pi/bash/`:

| Entry point | Provider id | Entry |
|---|---|---|
| `vpi` (profile `pi/agent`) | `pi` | overrides the built-in: `command` + `env` only |
| `pi-<name>` (profile `pi/agent_<name>`) | `pi-<name>` | `"extends": "pi"`, `label` from the entry point's line 3, `command`, `env` |

- `command` is the entry point itself (absolute path), so the appended prompt, `env_extra` and the
  variable scrubbing in its `PROFILE` block apply to Paseo launches too. Paseo appends `--mode rpc`,
  `--session`, `--extension` etc. after it; the launcher passes them through.
- `env.PI_CODING_AGENT_DIR` is the profile dir. The entry point sets it for `pi` anyway; Paseo needs
  it for its *own* reads of the profile (merging the profile's `mcp.json`, importing sessions).
- A provider with `"extends": "pi"` but no `command` inherits the `vpi` command and launches the
  vanilla profile whatever its `env` says. Always set both.
- Provider ids must match `^[a-z][a-z0-9-]*$`; entry point names already do.

The generator owns entries whose `command` points into `pi/bash/`: it updates `extends`, `command`
and `env.PI_CODING_AGENT_DIR`, sets `label` only if missing, removes owned entries whose entry point
is gone, and leaves other providers and other keys alone. It skips (with a message) an existing entry
with the same id but a foreign `command`. Paths are absolute: rerun it after moving the repo.

Extensions differ per profile because each profile has its own `settings.json` (`pi-<name> install
npm:<pkg>`; see `pi-profile`). Nothing about extensions goes into the Paseo config.

## Workflows

All commands from `~/Dotfiles/harness-dots`. Show dry runs before real runs.

**Regenerate providers** (after adding, removing or moving a Pi profile):

```bash
paseo/gen-pi-providers.py --dry-run   # diff against paseo/config.json
paseo/gen-pi-providers.py             # writes the tracked file only
paseo/gen-pi-providers.py --check     # exit 1 if stale
```

**Apply to the live Paseo config** (writes `~/.paseo`; run only when the user asks):

```bash
paseo/install.sh --dry-run            # diff of the live file
paseo/install.sh --reload             # write it (backup: config.json.bak), then `paseo reload`
```

Merge rules: objects merge key by key; arrays whose items all have an `id` (`daemon.agentProfiles`,
`daemon.terminalProfiles`) merge by `id`; everything else takes the tracked value. Live-only keys
survive (the password, UI-made profiles, providers added in the app), so a provider removed from the
tracked file stays live: remove it in the app, or use `paseo/install.sh --replace`, which writes the
tracked file as is and keeps only the live `daemon.auth`. `--home DIR` targets another Paseo home.

`paseo reload` applies `agents.providers`, `daemon.agentProfiles` and most UI-level settings live.
Daemon-level settings (`daemon.listen`, relay endpoints, ...) need `systemctl --user restart paseo`,
and so does any change to the daemon's own environment: Paseo passes its environment to every agent.
The unit starts it with `mise exec`, so mise's `[env]` lands in that environment.

**Track a setting the user changed in the app**: read the key from `~/.paseo/config.json`, add it to
`paseo/config.json` (never `daemon.auth`), show `git diff paseo/config.json`.

**Point an agent profile at a Pi profile**: in the app, set the agent profile's provider to
`pi-<name>`. To track it, copy its object (with its `id`) into `daemon.agentProfiles` in
`paseo/config.json`; the id-based merge then updates it in place on install.

## Troubleshooting: a Paseo Pi agent uses the wrong profile

Check in this order:

1. `jq '.agents.providers' ~/.paseo/config.json`: is the provider there with `command` and `env`?
   If not, `paseo/install.sh` was not run, or `paseo reload` was not run after it.
2. Is something exporting `PI_CODING_AGENT_DIR` globally? `grep -n PI_CODING_AGENT_DIR
   ~/.config/mise/config.toml ~/Dotfiles/mise-dots/config.toml ~/.bashrc
   ~/.config/systemd/user/paseo.service`. It must not be set anywhere global. A mise shim re-applies
   mise's `[env]` after the launcher's scrub; this used to send every Paseo Pi agent to `~/.pi/agent`.
3. The launcher resolves the real binary past mise shims: under the daemon's PATH,
   `env -i HOME="$HOME" PATH="$HOME/.local/share/mise/shims:/usr/bin:/bin" bash -c 'source
   ~/Dotfiles/harness-dots/bash/_common.bash; _dots_real_bin pi'` should print the install path, not
   `.../mise/shims/pi`.
4. A stale daemon environment: after removing a global variable, restart the daemon
   (`systemctl --user restart paseo`).
5. The Pi diagnostic in Paseo's provider settings always shows `~/.pi/agent/auth.json`. That label is
   hardcoded upstream and does not reflect the provider's `PI_CODING_AGENT_DIR`; ignore it.

## Rules

- Never commit `~/.paseo` content other than what the user chose to track; never commit secrets.
- `install.sh` and `paseo reload` / daemon restarts touch the user's running Paseo: dry-run first,
  run for real only when asked. Agents running inside Paseo are affected by a restart.
- Don't edit Paseo's source or its bundled skills to fit this setup; the upstream code lives at
  `~/3rdParty/paseo` for reading only.
- Don't commit unless the user asks.
