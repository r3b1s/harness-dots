#!/usr/bin/env bash
# Share files across pi profiles by symlinking them from pi/ into each profile.
#
#   ./link.sh [--force] [--dry-run]
#
#   settings.json  shared settings (tracked)
#   auth.json      shared credentials: /login in any profile logs in all of them
#                  (gitignored; created empty with mode 0600 if missing)
#   models.json    shared custom providers (gitignored; linked only once
#                  pi/models.json exists, so rerun after creating it)
#
# Links are relative, so they survive moving the repo. pi rewrites auth.json in
# place, so the links hold. A profile file that is already a link to the shared
# file is left alone; an empty auth.json ("{}") is replaced. Any other existing
# file is left alone unless --force, which first moves it to <file>.bak; merge
# what you need from the .bak into the shared file afterwards.
set -euo pipefail

here="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)"
force=0 dry=0
while (($#)); do
  case "$1" in
    --force)   force=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# Pi profiles (directories in pi/). scaffold.py appends new ones here.
profiles=(
  agent
  agent_ctf
  agent_producer
)

shared=(settings.json auth.json models.json)

run() { if ((dry)); then echo "would: $*"; else "$@"; fi; }
status=0

if [[ ! -e $here/auth.json ]]; then
  ((dry)) && echo "would: create $here/auth.json (0600)" \
          || { (umask 077; printf '{}\n' > "$here/auth.json"); echo "created  $here/auth.json"; }
fi

for p in "${profiles[@]}"; do
  [[ -d $here/$p ]] || { echo "missing  $here/$p (profile dir)" >&2; status=1; continue; }
  for f in "${shared[@]}"; do
    src="$here/$f" dest="$here/$p/$f"
    [[ -e $src ]] || continue   # e.g. no pi/models.json yet

    if [[ -L $dest && "$(readlink -f -- "$dest")" == "$src" ]]; then
      echo "ok       $dest"; continue
    fi
    if [[ -e $dest || -L $dest ]]; then
      # An empty credentials file holds nothing worth keeping (size check only; never read).
      if [[ $f == auth.json && -f $dest && ! -L $dest && $(stat -c %s -- "$dest") -le 3 ]]; then
        run rm -- "$dest"
      elif ((force)); then
        run mv -- "$dest" "$dest.bak"; echo "backup   $dest.bak"
      else
        echo "exists   $dest (not linked; merge into pi/$f, or --force to move it to .bak)" >&2
        status=1; continue
      fi
    fi
    run ln -s -- "../$f" "$dest"; echo "linked   $dest -> ../$f"
  done
done
exit "$status"
