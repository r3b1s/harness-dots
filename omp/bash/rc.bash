# shellcheck shell=bash
# Interactive-shell config for omp (oh-my-pi). Sourced by the repo's bash/rc.bash; not run.
# Defines a shell function for every omp entry point in this directory (vomp,
# ...), so they work even without ./install.sh. Add omp-only aliases,
# completions and the like below.

for _f in "${BASH_SOURCE[0]%/*}"/*; do
  [[ -f $_f && -x $_f && ${_f##*/} != _* && $_f != *.bash ]] && source "$_f"
done
unset _f
