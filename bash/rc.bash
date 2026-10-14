# shellcheck shell=bash
# Global interactive-shell config for every harness in this repo.
# Source it from ~/.bashrc:
#
#   [[ -r ~/Dotfiles/harness-dots/bash/rc.bash ]] && source ~/Dotfiles/harness-dots/bash/rc.bash
#
# It sources <harness>/bash/rc.bash for each harness directory (pi/, omp/, ...),
# which in turn defines that harness's launcher functions. Settings that apply
# to all harnesses belong here; anything harness-specific belongs in that
# harness's own rc.bash.
#
# Set DOTS_HARNESSES (space-separated, e.g. "pi") before sourcing to load only
# some harnesses; unset loads all of them.

DOTS_AGENT_ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd -P)"

for _rc in "$DOTS_AGENT_ROOT"/*/bash/rc.bash; do
  [[ -r $_rc ]] || continue
  _h="${_rc%/bash/rc.bash}"; _h="${_h##*/}"
  if [[ -n ${DOTS_HARNESSES-} && " $DOTS_HARNESSES " != *" $_h "* ]]; then continue; fi
  source "$_rc"
done
unset _rc _h
