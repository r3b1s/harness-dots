# harness-dots

Configuration for coding-agent harnesses: [Pi](https://pi.dev) in `pi/` and [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`) in `omp/`. Each of those directories is that harness's global config home; `~/.pi` and `~/.omp` are not used. Harness-agnostic pieces (`system-prompts/`, `skills/`) and the shared bash glue (`bash/`, `install.sh`) sit at the root. See [AGENTS.md](AGENTS.md) for the full conventions.

`omp` is a pi derivative and reads many of the same environment variables (`PI_CODING_AGENT_DIR` above all). Launched carelessly, one harness pollutes the other's config and session history. The launchers here scrub those variables before every run, so launch through them rather than with hand-set variables.

## Launching from bash

Each harness has entry points in `<harness>/bash/`:

| Command | Harness | Profile |
|---|---|---|
| `vpi` | pi | `pi/agent`, no appended prompt |
| `pi-ctf` | pi | `pi/agent_ctf` + `system-prompts/append_ctf_0.md` |
| `pi-producer` | pi | `pi/agent_producer` + `system-prompts/append_producer_0.md` |
| `vomp` | omp | `omp/agent` (omp's default profile), no appended prompt |

Use them either way:

- **Run:** `./install.sh` symlinks every entry point onto PATH (`~/.local/bin`, or `--bin-dir DIR` / `PI_BIN_DIR`; `--harness omp` or `--only vomp` to narrow it). They then work in scripts, cron and other non-interactive shells too. `./install.sh --uninstall` removes only the links it made.
- **Source:** add `source ~/Dotfiles/harness-dots/bash/rc.bash` to `~/.bashrc`. It sources `pi/bash/rc.bash` and `omp/bash/rc.bash`, which define the same commands as shell functions.

Harness subcommands work through any of them: `pi-ctf install npm:pkg`, `vpi list`, `vomp config list`.

Everything specific to a profile (profile, prompt file, extra environment variables in `env_extra`) sits in the marked `PROFILE` block of its file. The real `pi` / `omp` binary must be on PATH; with mise, that means `mise activate` or its shims.

## Runtime state

Both harnesses keep sessions, credentials and caches inside their config home, so inside this repo. `pi/.gitignore` and `omp/.gitignore` keep that out of git (omp's is an allowlist, since omp writes far more), and `pi/link.sh` symlinks the shared `pi/settings.json` into each pi profile.
