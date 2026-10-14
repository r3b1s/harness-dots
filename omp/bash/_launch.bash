# shellcheck shell=bash
# Shared launcher for the omp (oh-my-pi) entry points in this directory (vomp, ...).
# They source it; it is not meant to be run, and `install.sh` does not link it.
# The caller sets _OMP_BASH_DIR to this directory before sourcing. The real `omp`
# is the first one on PATH; no wrapper here is named `omp`, so there is no recursion.
#
# The repo's omp/ directory is omp's config root (what ~/.omp is by default):
# omp/agent/ is the default profile and omp/profiles/<name>/agent/ a named one.
# omp selects its root with PI_CONFIG_DIR, which it always joins onto $HOME, so
# the launcher passes omp/'s path relative to $HOME. It never sets
# PI_CODING_AGENT_DIR: that is pi's selector, and omp honours it only for the
# default profile anyway.

# shellcheck source=../../bash/_common.bash
source "$_OMP_BASH_DIR/../../bash/_common.bash"

# _omp_launch PROFILE PROMPT_FILE [NAME=value ...] -- [omp arguments ...]
#   PROFILE      omp profile name, or "default" for omp/agent
#   PROMPT_FILE  file in the repo's system-prompts/ to append, or "" for none
#   NAME=value   extra environment for this profile only
_omp_launch() {
  local profile=$1 prompt=$2 root real cfg home
  shift 2
  local -a extra=() scrub=() pre=()
  while (($#)) && [[ $1 != -- ]]; do extra+=("$1"); shift; done
  (($#)) && shift   # the --

  root="$(_dots_root "$_OMP_BASH_DIR")"
  real="$(type -P omp)" || { echo "dots: no omp binary found on PATH" >&2; return 127; }
  mapfile -t scrub < <(_dots_scrub_args)

  # PI_CONFIG_DIR must be relative to $HOME; an absolute value is re-rooted under it.
  home="$(cd -- "$HOME" && pwd -P)"
  if [[ $root == "$home"/* ]]; then
    cfg="${root#"$home"/}/omp"
  else
    cfg="$(realpath --relative-to="$home" -- "$root/omp")"
  fi

  # OMP_PROFILE wins over PI_PROFILE even when empty; empty selects the default.
  [[ $profile == default ]] && profile=""

  if [[ -n $prompt ]]; then
    # omp accepts launch flags in front of a subcommand and drops them there,
    # so the prompt can always go first (unlike pi).
    prompt="$(_dots_prompt "$root" "$prompt")" || return 1
    pre=(--append-system-prompt "$prompt")
  fi
  # The native-addon loader ignores PI_CONFIG_DIR and defaults to ~/.omp/natives;
  # keep it in the config root too unless the caller chose a dir.
  env "${scrub[@]}" PI_CONFIG_DIR="$cfg" OMP_PROFILE="$profile" \
    PI_NATIVES_DIR="${PI_NATIVES_DIR:-$root/omp/natives}" "${extra[@]}" \
    "$real" "${pre[@]}" "$@"
}
