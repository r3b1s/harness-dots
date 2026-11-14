# coi

Tracked [coi](https://github.com/coipond/coi) profiles installed into `$COI_HOME` (default `~/.coi`). Runtime state (`sessions/`, `storage/`, `state/`, `logs/`, `locks/`, `image-meta.json`) stays in `$COI_HOME` and is never tracked here.

## Ownership

`coi/` owns container image definitions, sandbox policies, `forward_env`, `[[credentials]]`, and container-mounted agent state (`$COI_HOME/state/<name>/`). Paseo adapters in [../paseo/](../paseo/README.md) invoke these profiles with `coi run --profile <name>`. See [../AGENTS.md](../AGENTS.md#custom-coi-providers-what-coi-owns-vs-what-paseo-owns).

## Layout

| Path | Role |
|---|---|
| `profiles/agy/config.toml` | `coi-agy` image build (`antigravity-cli@latest`, `npm:command-code@latest`), open network, `forward_env`, and `$COI_HOME/state/agy/` mounts |
| `profiles/claude/config.toml` | `coi-default` profile with `[[credentials]] bundle = "claude"`, open network, and `$COI_HOME/state/claude/projects` mount |
| `install.sh` | Expands `$COI_HOME`/`$HOME` and copies `profiles/*` into `$COI_HOME` (always copies, never symlinks) |

## Usage

```bash
./install.sh --dry-run                # preview diff against ~/.coi
./install.sh                          # copy rendered profiles into $COI_HOME (~/.coi)
./install.sh --home /path/to/.coi     # target another directory
```

`install.sh` does not build images or verify host tools. When `coi-default` is built and you need to build or rebuild `coi-agy`, run:

```bash
coi build --profile agy
```

Interactive debugging shell with a profile's full mounts and environment:

```bash
coi shell --profile agy --debug
coi shell --profile claude --debug
```
