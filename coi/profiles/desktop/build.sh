#!/usr/bin/env bash
# Build script for the `coi-desktop` image (base: coi-default, Ubuntu 24.04).
# Runs as root inside the build container (`coi build --profile desktop`).
#
# Adds a headless desktop that an agent can drive and a human can take over:
#
#   Xvfb :0 -> i3 -> AT-SPI           systemd --user units of `code` (linger)
#   Selkies + Pixelflux               HTML5 remote desktop on :8080 (basic auth)
#                                     and the loopback capture/input server
#                                     computer-use-linux prefers (127.0.0.1:5000)
#   computer-use-linux                agent-sh/computer-use-linux MCP server,
#                                     started through /usr/local/bin/desktop-mcp
#   Chromium (xtradeb .deb)           Ubuntu's own `chromium` is a snap stub
#
# The desktop design (units, flags, Pixelflux credentials) is ported from
# ~/Projects/actually-good-computer-use-sandbox (image/), minus its MCP bridge.
#
# coi/install.sh expands the literal placeholders for coi's home and the host
# home in every profile file, this one included: write the home variable as
# ${HOME} (braced) in here so it survives until it runs in the container.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

DESKTOP_USER="${DESKTOP_USER:-code}"
SELKIES_VERSION="${SELKIES_VERSION:-2.1.0}"
CU_LINUX_VERSION="${CU_LINUX_VERSION:-v0.7.53}"   # or "latest"

id -u "$DESKTOP_USER" >/dev/null
DESKTOP_UID="$(id -u "$DESKTOP_USER")"

# write <mode> <path>: install stdin as a root-owned file.
write() {
  install -D -m "$1" /dev/stdin "$2"
}

echo "==> apt: X11, i3, AT-SPI, fonts, Python"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl jq rsync software-properties-common \
  dbus-user-session dbus-x11 \
  xvfb x11-utils x11-xserver-utils xdotool wmctrl scrot \
  i3-wm i3status xterm dmenu \
  fonts-dejavu-core fonts-liberation fonts-noto-color-emoji \
  at-spi2-core libatk-bridge2.0-0t64 libgtk-3-0t64 \
  python3 python3-venv python3-pip

echo "==> apt: Chromium .deb from ppa:xtradeb/apps (pinned above the snap stub)"
add-apt-repository -y ppa:xtradeb/apps
write 0644 /etc/apt/preferences.d/xtradeb-chromium <<'EOF'
Package: chromium*
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 1001
EOF
apt-get update -y
apt-get install -y --no-install-recommends chromium
/usr/bin/chromium --version

echo "==> linger for $DESKTOP_USER (systemd --user starts at boot, no login needed)"
mkdir -p /var/lib/systemd/linger
touch "/var/lib/systemd/linger/$DESKTOP_USER"

echo "==> Selkies $SELKIES_VERSION + Pixelflux in /opt/selkies-venv"
python3 -m venv /opt/selkies-venv
/opt/selkies-venv/bin/pip install --quiet --upgrade pip
/opt/selkies-venv/bin/pip install --quiet "selkies==${SELKIES_VERSION}"

echo "==> computer-use-linux ($CU_LINUX_VERSION)"
(
  target="$(uname -m)-unknown-linux-gnu"
  asset="computer-use-linux-${target}"
  if [[ $CU_LINUX_VERSION == latest ]]; then
    base="https://github.com/agent-sh/computer-use-linux/releases/latest/download"
  else
    base="https://github.com/agent-sh/computer-use-linux/releases/download/${CU_LINUX_VERSION}"
  fi
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$base/$asset" -o "$tmp/$asset"
  curl -fsSL "$base/$asset.sha256" -o "$tmp/$asset.sha256"
  (cd "$tmp" && sha256sum --check --quiet "$asset.sha256")
  install -m 0755 "$tmp/$asset" /usr/local/bin/computer-use-linux
  /usr/local/bin/computer-use-linux --help >/dev/null
)

echo "==> helper scripts"

# Per-boot credentials shared by Selkies and computer-use-linux. /run/user is a
# tmpfs, so every container gets its own.
write 0755 /usr/local/bin/desktop-init-pixelflux-env <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
env_file="$runtime/pixelflux-cu.env"
[ -s "$env_file" ] && exit 0
umask 077
tmp="$(mktemp "$env_file.XXXXXX")"
cat >"$tmp" <<EOT
PIXELFLUX_CU=127.0.0.1:5000
PIXELFLUX_CU_TOKEN=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')
SELKIES_BASIC_AUTH_USER=$(id -un)
SELKIES_BASIC_AUTH_PASSWORD=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
EOT
mv "$tmp" "$env_file"
EOF

# `computer-use-linux <subcommand>` (default: mcp) inside the desktop session.
# This is the MCP server command the harnesses are pointed at.
write 0755 /usr/local/bin/desktop-mcp <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=i3
export GTK_MODULES=gail:atk-bridge
export QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
export COMPUTER_USE_LINUX_INDICATOR=0

env_file="$XDG_RUNTIME_DIR/pixelflux-cu.env"

# Selkies writes the credentials and opens the loopback server during boot. A
# session started before that stays on the slower X11 path for its lifetime, so
# give it a moment.
pixelflux_ready() {
  [ -f "$env_file" ] && (exec 3<>/dev/tcp/127.0.0.1/5000) 2>/dev/null
}
for _ in $(seq 1 150); do
  pixelflux_ready && break
  sleep 0.1
done
if pixelflux_ready; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
else
  echo "desktop-mcp: pixelflux loopback server is not up; using the X11 path" >&2
fi

exec /usr/local/bin/computer-use-linux "${@:-mcp}"
EOF

# Copy-on-start for the Chromium profile. The host keeps one golden profile
# ("seed", state/desktop/seeds/<name> under coi's home, attached per launch by
# `coi-desktop run --seed NAME`) mounted read-only at
# /opt/desktop/chromium-seed; every container works on its own copy, so
# parallel containers never fight over SingletonLock or the cookie database.
write 0755 /usr/local/bin/desktop-chromium-seed <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
seed=/opt/desktop/chromium-seed
dest="${XDG_CONFIG_HOME:-${HOME}/.config}/chromium"
marker="$dest/.desktop-seeded"

[ -e "$marker" ] && exit 0
mkdir -p "$dest"
exec 9>"$dest/.desktop-seed.lock"
flock 9
[ -e "$marker" ] && exit 0

if [ -d "$seed/Default" ] && [ ! -d "$dest/Default" ]; then
  rsync -a \
    --exclude='Singleton*' --exclude='*/LOCK' --exclude='lockfile' \
    --exclude='Cache/' --exclude='Code Cache/' --exclude='GPUCache/' \
    --exclude='GrShaderCache/' --exclude='ShaderCache/' --exclude='GraphiteDawnCache/' \
    --exclude='DawnGraphiteCache/' --exclude='DawnWebGPUCache/' \
    --exclude='Crash Reports/' --exclude='component_crx_cache/' \
    --exclude='Service Worker/CacheStorage/' \
    "$seed/" "$dest/"
  echo "desktop-chromium-seed: copied $seed -> $dest" >&2
fi
touch "$marker"
EOF

# `chromium` for agents and humans alike (precedes /usr/bin on PATH).
#   read-only seed mount  -> work on a private copy   (agent profiles)
#   writable seed mount   -> edit the seed in place   (`coi-desktop seed login`)
# --password-store=basic keeps cookies decryptable without a desktop keyring,
# which is also what makes the seed portable between containers.
write 0755 /usr/local/bin/chromium <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
export GTK_MODULES="${GTK_MODULES:-gail:atk-bridge}"

seed=/opt/desktop/chromium-seed
args=(
  --force-renderer-accessibility
  --no-first-run
  --no-default-browser-check
  --password-store=basic
  --ipc-connection-timeout=120
)
if [ -w "$seed" ]; then
  args+=("--user-data-dir=$seed")
else
  /usr/local/bin/desktop-chromium-seed || true
fi
# Agent harnesses kill a shell command's process group when the command
# returns, which would take a `chromium ... &` with it. Start the browser as a
# transient unit of the user manager instead, so this returns at once and the
# browser lives as long as the desktop. DESKTOP_CHROMIUM_FOREGROUND=1 keeps it
# in the foreground (desktop-login-session waits for it to exit).
if [ -z "${DESKTOP_CHROMIUM_FOREGROUND:-}" ] && [ -S "$XDG_RUNTIME_DIR/systemd/private" ]; then
  exec systemd-run --user --quiet --collect --same-dir /usr/bin/chromium "${args[@]}" "$@"
fi
exec /usr/bin/chromium "${args[@]}" "$@"
EOF
ln -sf chromium /usr/local/bin/chromium-browser

# Where a human can watch or take over this desktop.
write 0755 /usr/local/bin/desktop-takeover-info <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
env_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pixelflux-cu.env"
for _ in $(seq 1 150); do [ -s "$env_file" ] && break; sleep 0.1; done
[ -s "$env_file" ] || { echo "desktop-takeover-info: Selkies is not running" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"
if [ -n "${COI_PORT_DESKTOP:-}" ]; then
  echo "Desktop URL: http://127.0.0.1:${COI_PORT_DESKTOP}/   (open in a browser on the host)"
else
  echo "Desktop URL: run \`coi-desktop url\` on the host (container port 8080)"
fi
echo "Username:    ${SELKIES_BASIC_AUTH_USER}"
echo "Password:    ${SELKIES_BASIC_AUTH_PASSWORD}"
EOF

# Human login session for `coi-desktop seed login NAME`: Chromium runs on the
# writable seed until its last window is closed.
write 0755 /usr/local/bin/desktop-login-session <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
seed=/opt/desktop/chromium-seed
if [ ! -w "$seed" ]; then
  echo "desktop-login-session: $seed is not writable; start this with coi-desktop seed login NAME" >&2
  exit 1
fi
for _ in $(seq 1 150); do xdpyinfo -display :0 >/dev/null 2>&1 && break; sleep 0.1; done
echo
/usr/local/bin/desktop-takeover-info
cat <<'EOT'

Open the URL, log in to the sites the agents should reach, then close the
Chromium window (or press Ctrl-C here). Everything in this browser profile is
readable by every agent that mounts the seed, so log in only where needed.
EOT
status=0
DESKTOP_CHROMIUM_FOREGROUND=1 /usr/local/bin/chromium "$@" >/dev/null 2>&1 || status=$?
sleep 1
rm -f "$seed"/Singleton*
echo "Seed updated. New desktop containers pick it up on their first Chromium start."
exit "$status"
EOF

# MCP config for Claude Code (`claude --mcp-config /etc/desktop/claude-mcp.json`).
# The server is called "desktop" in every harness: Claude Code reserves the
# name "computer-use" and silently drops a server registered under it.
write 0644 /etc/desktop/claude-mcp.json <<'EOF'
{
  "mcpServers": {
    "desktop": {
      "command": "/usr/local/bin/desktop-mcp",
      "args": []
    }
  }
}
EOF

install -d -m 0755 /opt/desktop/chromium-seed

# Standing instructions for the agent. coi's profile-level `context` file is
# not injected for `coi run -- <agent>` sessions (which is how Paseo launches
# them), so the text goes where each harness looks on its own:
#   Claude Code   /etc/claude-code/CLAUDE.md   (managed memory)
#   Antigravity   ~/.gemini/GEMINI.md
#   Command Code  ~/.commandcode/AGENTS.md
write 0644 /etc/desktop/AGENTS.md <<'EOF'
# Desktop

This container runs a graphical desktop you can see and control.

- Display `:0` (Xvfb, 1920x1080) with the i3 window manager; `DISPLAY` is already set.
- Control it with the tools of the `desktop` MCP server (screenshot, pointer,
  keyboard, windows, accessibility tree).
- Browser: run `chromium <url>` in a shell. It returns immediately and the
  browser keeps running in the desktop session; run it again to open another
  tab. It starts with the user's saved logins when they have prepared them. Do
  not pass `--user-data-dir`, `--no-sandbox` or `--headless`, and do not use
  another browser.

## When a site wants a login, 2FA code or CAPTCHA

Do not try to get past it yourself and never ask for a password in chat. Run
`desktop-takeover-info`, give the user the URL, username and password it prints,
and ask them to complete the step in that remote desktop view. Wait for them to
say they are done, take a screenshot to confirm, then continue.
EOF
install -D -m 0644 /etc/desktop/AGENTS.md /etc/claude-code/CLAUDE.md
desktop_home="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"
for memory in .gemini/GEMINI.md .commandcode/AGENTS.md; do
  install -d -o "$DESKTOP_USER" -g "$DESKTOP_USER" "$desktop_home/$(dirname "$memory")"
  install -m 0644 -o "$DESKTOP_USER" -g "$DESKTOP_USER" /etc/desktop/AGENTS.md "$desktop_home/$memory"
done

echo "==> i3 config"
write 0644 /etc/desktop/i3.config <<'EOF'
# Minimal i3 for an agent-driven desktop with occasional human takeover.
# Alt, not Super: Super rarely survives the trip through a host compositor
# and a browser tab.
set $mod Mod1
font pango:DejaVu Sans Mono 10

workspace_layout default
default_border pixel 2
default_floating_border normal

bindsym $mod+Return exec xterm
bindsym $mod+b exec /usr/local/bin/chromium
bindsym $mod+d exec dmenu_run
bindsym $mod+Shift+q kill
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle

bar {
    status_command i3status
    position bottom
    mode dock
}
EOF

echo "==> session environment and systemd --user units"
write 0644 /etc/environment.d/10-desktop.conf <<'EOF'
DISPLAY=:0
XDG_SESSION_TYPE=x11
XDG_CURRENT_DESKTOP=i3
GTK_MODULES=gail:atk-bridge
QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
ACCESSIBILITY_ENABLED=1
EOF

write 0644 /etc/systemd/user/desktop-xvfb.service <<'EOF'
[Unit]
Description=Desktop Xvfb virtual display (:0)
After=dbus.socket
ConditionUser=!root

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :0 -screen 0 1920x1080x24 -s 0 -dpms +extension COMPOSITE +extension DAMAGE +extension GLX +extension RANDR +extension RENDER +extension MIT-SHM +extension XFIXES +extension XTEST +iglx +render -nolisten tcp -ac -noreset -shmem
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF

write 0644 /etc/systemd/user/desktop-i3.service <<'EOF'
[Unit]
Description=Desktop i3 window manager
After=desktop-xvfb.service
Requires=desktop-xvfb.service
ConditionUser=!root

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'for i in $(seq 1 50); do xdpyinfo -display :0 >/dev/null 2>&1 && exit 0; sleep 0.1; done; exit 1'
ExecStart=/usr/bin/i3 -c /etc/desktop/i3.config
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF

write 0644 /etc/systemd/user/desktop-atspi-guard.service <<'EOF'
[Unit]
Description=Desktop AT-SPI accessibility enablement
After=desktop-i3.service dbus.socket
Requires=desktop-i3.service
ConditionUser=!root

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/busctl --user set-property org.a11y.Bus /org/a11y/bus org.a11y.Status IsEnabled b true
Restart=on-failure
RestartSec=1

[Install]
WantedBy=default.target
EOF

write 0644 /etc/systemd/user/desktop-selkies.service <<'EOF'
[Unit]
Description=Desktop Selkies + Pixelflux streamer and computer-use loopback server
After=desktop-i3.service
Requires=desktop-i3.service
ConditionUser=!root

[Service]
Type=simple
ExecStartPre=/usr/local/bin/desktop-init-pixelflux-env
EnvironmentFile=-%t/pixelflux-cu.env
ExecStart=/opt/selkies-venv/bin/selkies --public --port=8080 --enable-resize=false --audio-enabled=false
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF

mkdir -p /etc/systemd/user/default.target.wants
for unit in desktop-xvfb desktop-i3 desktop-atspi-guard desktop-selkies; do
  ln -sf "../$unit.service" "/etc/systemd/user/default.target.wants/$unit.service"
done

echo "==> cleanup"
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "==> coi-desktop: done (user $DESKTOP_USER, uid $DESKTOP_UID)"
