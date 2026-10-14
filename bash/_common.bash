# shellcheck shell=bash
# Shared by every harness launcher (pi/bash/_launch.bash, omp/bash/_launch.bash).
# Sourced, never run. Defines nothing but the helpers below.
#
# pi and omp (oh-my-pi) share ancestry, so they read many of the same PI_*
# variables. Whatever one harness (or an env manager such as mise) leaves in
# the environment would otherwise steer the other one into the wrong config
# and session store. Each launcher therefore starts from a scrubbed
# environment and then sets only what its own harness needs.

# Variables that select a harness's config root, agent dir, profile or
# session. Both launchers drop all of them before setting their own.
#   PI_CODING_AGENT_DIR          pi + omp  agent dir (omp: default profile only)
#   PI_CONFIG_DIR                omp       config root, a dirname under $HOME
#   OMP_PROFILE, PI_PROFILE      omp       named profile
#   PI_CONFIG_FILES              omp       extra config.yml overlays
#   PI_CODING_AGENT_SESSION_DIR  omp       session dir override
#   PI_SESSION_FILE              pi + omp  set for a harness's own child shells
#   PI_PACKAGE_DIR               pi + omp  install dir of the harness package
#   PI_CODING_AGENT              pi        "running inside pi" marker
_DOTS_HARNESS_VARS=(
  PI_CODING_AGENT_DIR
  PI_CONFIG_DIR
  OMP_PROFILE
  PI_PROFILE
  PI_CONFIG_FILES
  PI_CODING_AGENT_SESSION_DIR
  PI_SESSION_FILE
  PI_PACKAGE_DIR
  PI_CODING_AGENT
)

# _dots_scrub_args: print `-u NAME` pairs for env(1), one word per line,
# so a caller can do: mapfile -t scrub < <(_dots_scrub_args); env "${scrub[@]}" ...
_dots_scrub_args() {
  local v
  for v in "${_DOTS_HARNESS_VARS[@]}"; do printf '%s\n' -u "$v"; done
}

# _dots_root DIR: the repo root, given a harness's bash/ directory.
_dots_root() {
  (cd -- "$1/../.." && pwd -P)
}

# _dots_prompt ROOT FILE: the absolute path of a shared system prompt, or fail.
# A missing file would be appended as literal text, so fail loudly instead.
_dots_prompt() {
  local path="$1/system-prompts/$2"
  [[ -r $path ]] || { echo "dots: system prompt not found: $path" >&2; return 1; }
  printf '%s\n' "$path"
}
