# shellcheck shell=bash
# Shared launcher for the pi entry points in this directory (vpi, pi-ctf, ...).
# They source it; it is not meant to be run, and `install.sh` does not link it.
# The caller sets _PI_BASH_DIR to this directory before sourcing. The real `pi`
# is the first one on PATH, resolved past a mise shim (_dots_real_bin); no wrapper
# here is named `pi`, so there is no recursion.

# shellcheck source=../../bash/_common.bash
source "$_PI_BASH_DIR/../../bash/_common.bash"

# _pi_launch PROFILE_DIR PROMPT_FILE [NAME=value ...] -- [pi arguments ...]
#   PROFILE_DIR  directory in pi/ used as PI_CODING_AGENT_DIR
#   PROMPT_FILE  file in the repo's system-prompts/ to append, or "" for none
#   NAME=value   extra environment for this profile only
_pi_launch() {
  local profile=$1 prompt=$2 root dir real
  shift 2
  local -a extra=() scrub=()
  while (($#)) && [[ $1 != -- ]]; do extra+=("$1"); shift; done
  (($#)) && shift   # the --

  root="$(_dots_root "$_PI_BASH_DIR")"
  dir="$root/pi/$profile"
  [[ -d $dir ]] || { echo "dots: pi profile directory not found: $dir" >&2; return 1; }
  real="$(_dots_real_bin pi)" || { echo "dots: no pi binary found on PATH" >&2; return 127; }
  mapfile -t scrub < <(_dots_scrub_args)

  case "${1-}" in
    # Pi's own subcommands take the profile dir only; --append-system-prompt
    # in front would stop them being recognised.
    install|remove|uninstall|update|list|config|auth|mcp)
      env "${scrub[@]}" PI_CODING_AGENT_DIR="$dir" "${extra[@]}" "$real" "$@"
      ;;
    *)
      if [[ -n $prompt ]]; then
        prompt="$(_dots_prompt "$root" "$prompt")" || return 1
        env "${scrub[@]}" PI_CODING_AGENT_DIR="$dir" "${extra[@]}" "$real" \
          --append-system-prompt "$prompt" "$@"
      else
        env "${scrub[@]}" PI_CODING_AGENT_DIR="$dir" "${extra[@]}" "$real" "$@"
      fi
      ;;
  esac
}
