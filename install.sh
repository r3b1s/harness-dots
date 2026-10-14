#!/usr/bin/env bash
# Symlink each harness's entry points (<harness>/bash/*, e.g. pi/bash/vpi,
# omp/bash/vomp) onto PATH (default ~/.local/bin).
#
#   ./install.sh [--bin-dir DIR] [--only vpi,vomp] [--harness pi,omp] [--uninstall] [--force] [--dry-run]
#
# PI_BIN_DIR also sets the directory. An entry point is an executable file whose
# name has no leading underscore and no .bash extension. Existing files, and
# links that point anywhere else, are left alone unless --force. --uninstall
# removes only links that point into this repo.
set -euo pipefail

root="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)"
bin="${PI_BIN_DIR:-$HOME/.local/bin}"
only="" harness="" uninstall=0 force=0 dry=0

while (($#)); do
  case "$1" in
    --bin-dir)   bin="$2"; shift ;;
    --only)      only="$2"; shift ;;
    --harness)   harness="$2"; shift ;;
    --uninstall) uninstall=1 ;;
    --force)     force=1 ;;
    --dry-run)   dry=1 ;;
    -h|--help)   sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

run() { if ((dry)); then echo "would: $*"; else "$@"; fi; }
status=0

for src in "$root"/*/bash/*; do
  name="$(basename "$src")"
  [[ -f $src && -x $src && $name != _* && $name != *.bash ]] || continue
  h="${src#"$root"/}"; h="${h%%/*}"
  if [[ -n $harness && ",$harness," != *",$h,"* ]]; then continue; fi
  if [[ -n $only && ",$only," != *",$name,"* ]]; then continue; fi
  dest="$bin/$name"

  if ((uninstall)); then
    if [[ -L $dest && "$(readlink -f -- "$dest")" == "$src" ]]; then
      run rm -- "$dest"; echo "removed  $dest"
    else
      echo "skipped  $dest (not a link to this repo)"
    fi
    continue
  fi

  if [[ -L $dest && "$(readlink -f -- "$dest")" == "$src" ]]; then
    echo "ok       $dest"
  elif [[ -e $dest || -L $dest ]] && ((! force)); then
    echo "exists   $dest (not ours; use --force to replace)" >&2; status=1
  else
    run mkdir -p -- "$bin"
    run ln -sfn -- "$src" "$dest"; echo "linked   $dest -> $src"
  fi
done

if ((! uninstall)) && [[ ":$PATH:" != *":$bin:"* ]]; then
  echo "note: $bin is not on PATH" >&2
fi
exit "$status"
