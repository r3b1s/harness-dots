# paseo

Tracked [Paseo](https://paseo.sh) configuration and provider adapter scripts installed into `$PASEO_HOME` (default `~/.paseo`). Live state, keys, logs, `daemon.auth`, and `coi-agy/` adapter caches stay in `$PASEO_HOME`.

## Ownership

`paseo/` owns Paseo daemon settings, provider registrations (`agents.providers`), thin `coi run --profile <name>` adapter scripts (`bin/`), and host-side `agy-coi` ACP probe caches (`$PASEO_HOME/coi-agy/`). Container profiles, builds, and container-mounted state belong to [../coi/](../coi/README.md). See [../AGENTS.md](../AGENTS.md#custom-coi-providers-what-coi-owns-vs-what-paseo-owns).

## Layout

| Path | Role |
|---|---|
| `config.json` | Source merged into `$PASEO_HOME/config.json` (expands `$PASEO_HOME`, `$COI_HOME`, `$HOME`) |
| `bin/claude-coi` | Wraps `claude` via `coi run --profile claude`, keeping `--version` and model-discovery probes fast on host |
| `bin/agy-coi` | ACP stdio proxy launching `agy acp` via `coi run --profile agy` with `$PASEO_HOME/coi-agy/` `version.txt` and `acp-init-result.json` caches |
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
