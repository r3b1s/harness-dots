# paseo

Tracked [Paseo](https://paseo.sh) configuration and provider adapter scripts installed into `$PASEO_HOME` (default `~/.paseo`). Live state, keys, logs, `daemon.auth`, and `coi-<profile>/` adapter caches stay in `$PASEO_HOME`.

## Ownership

`paseo/` owns Paseo daemon settings, provider registrations (`agents.providers`), thin `coi run --profile <name>` adapter scripts (`bin/`), and host-side ACP probe caches (`$PASEO_HOME/coi-<profile>/`). Container profiles, builds, and container-mounted state belong to [../coi/](../coi/README.md). See [../AGENTS.md](../AGENTS.md#custom-coi-providers-what-coi-owns-vs-what-paseo-owns).

## Layout

| Path | Role |
|---|---|
| `config.json` | Source merged into `$PASEO_HOME/config.json` (expands `$PASEO_HOME`, `$COI_HOME`, `$HOME`) |
| `bin/claude-coi` | Wraps `claude` via `coi run --profile <profile>` (default `claude`), keeping `--version` and model-discovery probes fast on host |
| `bin/agy-coi` | Generic ACP stdio proxy over `coi run --profile <profile>` (default `agy` / `agy acp`) with `$PASEO_HOME/coi-<profile>/` `version.txt`, `acp-init-result.json`, and `probe-workspace` |
| `install.sh` | Deep-merges `config.json` (preserving live `daemon.auth` and UI keys) and copies `bin/*` into `$PASEO_HOME/bin/` (never symlinks) |
| `gen-pi-providers.py` | Updates `pi` / `pi-*` entries in `config.json` from `../pi/bash/` |

## Usage

```bash
./gen-pi-providers.py --dry-run       # preview pi provider updates in config.json
./gen-pi-providers.py --check         # verify pi providers are up to date

./install.sh --dry-run                # preview diff against ~/.paseo
./install.sh --reload                 # install config + bin/* (backup: config.json.bak) and run `paseo reload`
./install.sh --replace                # overwrite live config.json (keeps only live daemon.auth)
```

`install.sh` does not check or install `coi`, container images, `claude`, or `node`.

## Containerized (`coi`) providers

The desktop variants add three providers in `config.json` with no new wrapper scripts; `bin/claude-coi` and `bin/agy-coi` are parameterized via provider `env`:

| Provider | Extends | Wrapper | `coi` profile | Key `env` settings |
|---|---|---|---|---|
| `claude-coi` | `claude` | `bin/claude-coi` | `claude` | `CLAUDE_CONFIG_DIR=$COI_HOME/state/claude` |
| `agy-coi` | `acp` | `bin/agy-coi` | `agy` | defaults (`agy acp`, cache `$PASEO_HOME/coi-agy/`) |
| `claude-coi-desktop` | `claude` | `bin/claude-coi` | `claude-desktop` | `CLAUDE_CONFIG_DIR=$COI_HOME/state/claude`, `PASEO_COI_PROFILE=claude-desktop`, `PASEO_COI_MCP_CONFIG=/etc/desktop/claude-mcp.json` |
| `agy-coi-desktop` | `acp` | `bin/agy-coi` | `agy-desktop` | `PASEO_COI_PROFILE=agy-desktop`, `PASEO_COI_DESKTOP_MCP=1` |
| `commandcode-coi-desktop` | `acp` | `bin/agy-coi` | `commandcode-desktop` | `PASEO_COI_PROFILE=commandcode-desktop`, `PASEO_COI_ACP_ARGV=["cmd","acp"]`, `PASEO_COI_FORWARD_ENV=""`, `PASEO_COI_STRIP_THOUGHT_LEVEL="0"` |

`commandcode-coi-desktop` extends `acp` rather than Paseo's `commandcode` plugin provider because that plugin launches a single daemon-wide binary, so it lacks the plugin's extra slash commands. Its `desktop` MCP server is registered at user scope in the `coi-agy-desktop` image.

Wrapper environment variables:

- `bin/claude-coi`: `PASEO_COI_PROFILE` (default `claude`), `PASEO_COI_MCP_CONFIG` (passed to in-container `claude` as `--mcp-config`), `PASEO_COI_SEED` (named browser seed; default empty = none), `PASEO_COI_DESKTOP_BIN` (path to `coi-desktop` launcher; default `${COI_HOME:-$HOME/.coi}/bin/coi-desktop`).
- `bin/agy-coi`: `PASEO_COI_PROFILE` (default `agy`; sets cache dir `$PASEO_HOME/coi-<profile>/`), `PASEO_COI_ACP_ARGV` (JSON non-empty string array; default `["agy","acp","--dangerously-skip-permissions","--disable-telemetry"]`), `PASEO_COI_FORWARD_ENV` (comma-separated env vars to forward; unset uses the default Gemini/Google list, `""` forwards none), `PASEO_COI_STRIP_THOUGHT_LEVEL` (`"0"` disables stripping `thought_level` options), `PASEO_COI_DESKTOP_MCP` (`"1"` adds the `desktop` stdio MCP server to ACP `session/new`, `session/load`, and `session/resume` requests), `PASEO_COI_SEED` (named browser seed; default empty = none), `PASEO_COI_DESKTOP_BIN` (path to `coi-desktop` launcher; default `${COI_HOME:-$HOME/.coi}/bin/coi-desktop`).

Browser seeds are opt-in per provider (none are set in tracked `config.json`). When `PASEO_COI_SEED` is set, the wrapper launches the session through `coi-desktop run --seed <name> --` instead of calling `coi` directly; metadata and version probes never use a seed. To give different agents different logins, add a provider entry per seed (for example, copy `claude-coi-desktop` to `claude-coi-desktop-github` with `"PASEO_COI_SEED": "github"`).
