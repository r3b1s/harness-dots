# shellcheck shell=bash
# Interactive-shell config for pi. Sourced by the repo's bash/rc.bash; not run.
# Defines a shell function for every pi entry point in this directory (vpi,
# pi-ctf, ...), so they work even without ./install.sh. Add pi-only aliases,
# completions and the like below.

for _f in "${BASH_SOURCE[0]%/*}"/*; do
  [[ -f $_f && -x $_f && ${_f##*/} != _* && $_f != *.bash ]] && source "$_f"
done
unset _f
