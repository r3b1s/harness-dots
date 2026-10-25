#!/usr/bin/env bash
# Copy logins between pi profiles: auth.json and models.json from one profile
# into others. Copies, never links; both files stay gitignored.
#
#   ./copy-auth.sh [--from PROFILE] [--to PROFILE[,PROFILE...]] [--dry-run]
#
#   --from  source profile dir in pi/ (default: agent)
#   --to    target profile dirs (default: every other pi/agent and pi/agent_* dir)
#
# A file missing from the source is skipped (models.json is optional). A target
# file that already matches is left alone; one that differs is moved to
# <file>.bak first, so a login made only in that profile can be recovered. An
# old symlink (from the retired link.sh) is replaced by a real file. Copies are
# written atomically with mode 0600. Prints file names only, never contents.
set -euo pipefail

here="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)"
from=agent to="" dry=0
files=(auth.json models.json)

while (($#)); do
  case "$1" in
    --from)    from="$2"; shift ;;
    --to)      to="$2"; shift ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

run() { if ((dry)); then echo "would: $*"; else "$@"; fi; }

[[ -d $here/$from ]] || { echo "copy-auth: source profile not found: $here/$from" >&2; exit 1; }

targets=()
if [[ -n $to ]]; then
  IFS=, read -ra targets <<<"$to"
else
  for d in "$here"/agent "$here"/agent_*; do
    [[ -d $d && ${d##*/} != "$from" ]] && targets+=("${d##*/}")
  done
fi

status=0
for t in "${targets[@]}"; do
  [[ $t != "$from" ]] || { echo "skip     $t (same as --from)" >&2; continue; }
  [[ -d $here/$t ]] || { echo "missing  $here/$t (profile dir)" >&2; status=1; continue; }
  for f in "${files[@]}"; do
    src="$here/$from/$f" dest="$here/$t/$f"
    [[ -f $src ]] || continue
    if [[ -f $dest && ! -L $dest ]] && cmp -s -- "$src" "$dest"; then
      echo "ok       $dest"; continue
    fi
    if [[ -L $dest ]]; then
      run rm -- "$dest"
    elif [[ -e $dest ]]; then
      run mv -f -- "$dest" "$dest.bak"; ((dry)) || echo "backup   $dest.bak"
    fi
    if ((dry)); then
      echo "would: copy $src -> $dest (0600)"
    else
      tmp="$(mktemp -- "$here/$t/.$f.XXXXXX")"
      cat -- "$src" > "$tmp"
      chmod 600 -- "$tmp"
      mv -f -- "$tmp" "$dest"
      echo "copied   $src -> $dest"
    fi
  done
done
exit "$status"
