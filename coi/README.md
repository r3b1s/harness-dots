# coi

Tracked [coi](https://github.com/coipond/coi) profiles installed into `$COI_HOME` (default `~/.coi`). Runtime state (`sessions/`, `storage/`, `state/`, `logs/`, `locks/`, `image-meta.json`) stays in `$COI_HOME` and is never tracked here.

## Ownership

`coi/` owns container image definitions, sandbox policies, `forward_env`, `[[credentials]]`, and container-mounted agent state (`$COI_HOME/state/<name>/`). Paseo adapters in [../paseo/](../paseo/README.md) invoke these profiles with `coi run --profile <name>`. See [../AGENTS.md](../AGENTS.md#custom-coi-providers-what-coi-owns-vs-what-paseo-owns).

## Layout

| Path | Role |
|---|---|
| `profiles/agy/config.toml` | `coi-agy` image build (`antigravity-cli@latest`, `npm:command-code@latest`), open network, `forward_env`, and `$COI_HOME/state/agy/` mounts |
| `profiles/claude/config.toml` | `coi-default` profile with `[[credentials]] bundle = "claude"`, open network, and `$COI_HOME/state/claude/projects` mount |
| `profiles/desktop/` | `coi-desktop` image build (`config.toml`, `build.sh`) from `coi-default`: Xvfb `:0`, i3, AT-SPI, Selkies/Pixelflux `:8080`, `computer-use-linux` MCP (`/usr/local/bin/desktop-mcp`), `ppa:xtradeb/apps` Chromium wrapper, and in-image `/etc/desktop/AGENTS.md` + harness memory copies |
| `profiles/claude-desktop/config.toml` | `coi-desktop` with `[[credentials]] bundle = "claude"` and `$COI_HOME/state/claude/projects` |
| `profiles/agy-desktop/config.toml` | `coi-agy-desktop` image build from `coi-desktop` (`agy` + `command-code` + user-scope `desktop` MCP) and `$COI_HOME/state/agy/` mounts |
| `profiles/commandcode-desktop/config.toml` | `coi-agy-desktop` with `~/.commandcode/{auth,config}.json` (`[[credentials]]`) and `$COI_HOME/state/commandcode/projects` |
| `bin/coi-desktop` | Host CLI (installed to `$COI_HOME/bin/coi-desktop`) to manage named seeds in `$COI_HOME/state/desktop/seeds/<name>/` (`status`, `seed list\|profiles\|import\|login\|clear\|remove`), attach a seed via `COI_CONFIG` overlay (`run`), and list running desktop URLs (`url`) |
| `install.sh` | Expands `$COI_HOME`/`$HOME` in `profiles/*`, keeps executable bits (for `build.sh`), installs `bin/*` verbatim (mode 755), copies everything into `$COI_HOME` (never symlinks), and creates `state/desktop/seeds` (mode 700) and `state/commandcode/projects` |

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

## Desktop profiles

### Images and build order

Build `coi-desktop` from `coi-default` first, then layer `coi-agy-desktop` on top of it:

```bash
coi build --profile desktop
coi build --profile agy-desktop
```

`desktop/build.sh` installs Xvfb `:0`, i3, and AT-SPI as `systemd --user` units of `code` (with linger enabled), Selkies/Pixelflux remote desktop on container port `8080` (per-container basic-auth credentials in `/run/user/1000/pixelflux-cu.env`), `agent-sh/computer-use-linux` behind `/usr/local/bin/desktop-mcp` (registered under the MCP name `desktop`), and `ppa:xtradeb/apps` Chromium (since Ubuntu's `chromium` package is a snap stub) behind `/usr/local/bin/chromium`, which starts the browser as a transient `systemd --user` unit and returns immediately so a harness's process-group cleanup on shell exit does not kill it. Because `coi` does not inject a profile `context` file for `coi run -- <agent>` sessions, `desktop/build.sh` writes the agent instructions to `/etc/desktop/AGENTS.md` and installs copies at `/etc/claude-code/CLAUDE.md`, `~/.gemini/GEMINI.md`, and `~/.commandcode/AGENTS.md`; changing those instructions requires rebuilding the images. `claude-desktop` runs `coi-desktop`; `commandcode-desktop` runs `coi-agy-desktop`.

The four desktop profiles (`desktop`, `claude-desktop`, `agy-desktop`, `commandcode-desktop`) deliberately omit `inherits` because `inherits` replaces `[[mounts]]` instead of appending to it. `[environment]` and `[ports]` are repeated in each profile; update all of them when changing either section. No profile mounts a seed.

### Parallelism and state

Each desktop profile publishes `[ports] map = [{ name = "desktop", container = 8080 }]`, which binds to `127.0.0.1` on a host port per workspace/slot so parallel sessions each get their own desktop URL.

- `claude-desktop` shares `$COI_HOME/state/claude/projects` with `claude` (and `[[credentials]] bundle = "claude"`).
- `agy-desktop` shares `$COI_HOME/state/agy/` with `agy`.
- `commandcode-desktop` copies `~/.commandcode/auth.json` and `config.json` from the host at session start (`[[credentials]]`) and keeps transcripts in `$COI_HOME/state/commandcode/projects`.

### Browser login seeds

Authenticated browser sessions live in named Chromium profiles on the host at `$COI_HOME/state/desktop/seeds/<name>/` (one per purpose, outside the repo, never tracked). No `coi` profile mounts a seed: without one, Chromium starts with no logins.

`coi-desktop run --seed NAME [--writable] -- <coi args>` attaches a seed per launch via a `COI_CONFIG` overlay (`$COI_HOME/state/desktop/overlays/<name>-ro|rw.toml`) whose `[[mounts]]` `coi` adds to the profile's. Agent launches mount it read-only at `/opt/desktop/chromium-seed`, and `/usr/local/bin/chromium` copies it into the container on first start so parallel containers share logins without contending on a profile lock. Changes an agent makes stay in that container and are discarded with it; already-running containers keep the copy they started with. `coi-desktop run` refuses to start if `COI_CONFIG` is already set.

Manage seeds and launch with them using `coi-desktop` (installed to `$COI_HOME/bin/coi-desktop` by `./install.sh`, or `./bin/coi-desktop`):

```bash
coi-desktop status
coi-desktop seed list
coi-desktop seed login NAME [URL...]            # recommended: runs `desktop` with seed NAME writable; log in via the printed URL, then close the browser
coi-desktop seed profiles                         # list host Chromium profiles
coi-desktop seed import NAME [--profile P] [--user-data-dir DIR] [--domains a.com,b.com] [--with-storage]
coi-desktop seed clear NAME
coi-desktop seed remove NAME
coi-desktop run --seed NAME -- shell --profile claude-desktop
```

`seed import` selects the host Chromium profile (`--profile`) by directory or display name, copies cookies, and re-encrypts them from the host keyring key to the keyless form used in the container.

**Security:** everything in a seed is readable by every agent launched with it. Keep one seed per purpose, log in only to sites those agents need, and prefer `--domains` when importing.

### Human takeover

When a running session hits 2FA, a CAPTCHA, or an unexpected login:

- **From the host:** run `coi-desktop url` to list running desktops with URL, username, and password.
- **From inside the container:** the in-image instructions (`/etc/desktop/AGENTS.md`, installed into each harness's global memory file) tell the agent to run `desktop-takeover-info` and give the user the URL, username, and password it prints.

Logins entered in a running agent container live only in that container.

### Verification status

Verified end to end (2026-11-13):

- `coi build` of `coi-desktop` and `coi-agy-desktop`; desktop units, Selkies basic auth and the published port in real `coi run` sessions.
- All three Paseo providers (`claude-coi-desktop`, `agy-coi-desktop`, `commandcode-coi-desktop`): each loads the `desktop` MCP tools, opens Chromium from a shell, takes a screenshot of the page, and receives the login/2FA/CAPTCHA handover instructions from its global memory file.
- Three providers in parallel on one workspace: separate containers, host ports and passwords, all listed by `coi-desktop url`.
- `seed login` (Chromium runs on the writable seed; closing it ends the session and leaves no lock) and `seed import` against the host keyring; a cookie imported from host Chromium 155 is sent by container Chromium 156.
- Named seeds verified with real `coi` (read-only and writable attach).
