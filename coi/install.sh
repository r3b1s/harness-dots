#!/usr/bin/env bash
# Copy and render tracked coi config files (profiles/*) into coi's live
# directory ($COI_HOME, default ~/.coi).
#
#   ./install.sh [--home DIR] [--dry-run]
#
# Copies tracked files rather than symlinking them ($COI_HOME and $HOME
# placeholders are expanded to the target directory), leaving coi runtime state
# (sessions, storage, state, logs, locks, image-meta.json) untouched. Does not
# run `coi build` or manage host container prerequisites.
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
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$home" in
  "~") home="$HOME" ;;
  "~/"*) home="$HOME/${home#"~/"}" ;;
esac
[[ $home != / ]] && home="${home%/}"

# Render $COI_HOME and $HOME placeholders literally without regex/escape hazards.
render_text_file() {
  local infile=$1
  COI_HOME_VAL="$home" HOME_VAL="$HOME" awk '
    function replace_lit(s, old, val,   idx, out, n) {
      n = length(old)
      out = ""
      while ((idx = index(s, old)) > 0) {
        out = out substr(s, 1, idx - 1) val
        s = substr(s, idx + n)
      }
      return out s
    }
    {
      line = replace_lit($0, "$COI_HOME", ENVIRON["COI_HOME_VAL"])
      line = replace_lit(line, "$HOME", ENVIRON["HOME_VAL"])
      printf "%s\n", line
    }' "$infile"
}

install_file() {
  local src=$1 dest=$2 mode=$3
  local rendered_tmp
  rendered_tmp="$(mktemp)"
  render_text_file "$src" > "$rendered_tmp"

  if [[ ! -L $dest && -f $dest ]] && cmp -s -- "$rendered_tmp" "$dest"; then
    echo "ok       $dest"
    rm -f -- "$rendered_tmp"
    return 0
  fi
  if [[ -e $dest ]]; then
    diff -u --label "$dest" --label "$dest (new)" "$dest" "$rendered_tmp" || true
  else
    diff -u --label /dev/null --label "$dest (new)" /dev/null "$rendered_tmp" || true
  fi
  if ((dry)); then
    echo "would: write $dest"
    rm -f -- "$rendered_tmp"
    return 0
  fi
  mkdir -p -- "$(dirname -- "$dest")"
  local tmp
  tmp="$(mktemp -- "$(dirname -- "$dest")/.coi-install.XXXXXX")"
  cp -- "$rendered_tmp" "$tmp"
  chmod "$mode" -- "$tmp"
  mv -f -- "$tmp" "$dest"
  rm -f -- "$rendered_tmp"
  echo "wrote    $dest"
}

if [[ -d $here/profiles ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$here"/}"
    install_file "$src" "$home/$rel" 644
  done < <(find "$here/profiles" -type f -print0 | sort -z)
fi
