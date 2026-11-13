#!/usr/bin/env bash
# Copy tracked coi config files (profiles/*) into coi's live directory
# ($COI_HOME, default ~/.coi).
#
#   ./install.sh [--home DIR] [--dry-run]
#
# Copies tracked files rather than symlinking them, leaving coi runtime state
# (sessions, storage, logs, locks, image-meta.json) untouched. Does not run
# `coi build` or manage host container prerequisites.
#
# --home DIR target coi directory (default: $COI_HOME or ~/.coi).
# --dry-run  show diffs, write nothing.
set -euo pipefail

here="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)"
home="${COI_HOME:-$HOME/.coi}"
dry=0

while (($#)); do
  case "$1" in
    --home)    home="$2"; shift ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$home" in
  "~") home="$HOME" ;;
  "~/"*) home="$HOME/${home#"~/"}" ;;
esac
[[ $home != / ]] && home="${home%/}"

install_file() {
  local src=$1 dest=$2 mode=$3
  if [[ ! -L $dest && -f $dest ]] && cmp -s -- "$src" "$dest"; then
    echo "ok       $dest"
    return 0
  fi
  if [[ -e $dest ]]; then
    diff -u --label "$dest" --label "$dest (new)" "$dest" "$src" || true
  else
    diff -u --label /dev/null --label "$dest (new)" /dev/null "$src" || true
  fi
  if ((dry)); then
    echo "would: write $dest"
    return 0
  fi
  mkdir -p -- "$(dirname -- "$dest")"
  local tmp
  tmp="$(mktemp -- "$(dirname -- "$dest")/.coi-install.XXXXXX")"
  cp -- "$src" "$tmp"
  chmod "$mode" -- "$tmp"
  mv -f -- "$tmp" "$dest"
  echo "wrote    $dest"
}

if [[ -d $here/profiles ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$here"/}"
    install_file "$src" "$home/$rel" 644
  done < <(find "$here/profiles" -type f -print0 | sort -z)
fi
