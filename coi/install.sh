#!/usr/bin/env bash
# Copy and render tracked coi config files (profiles/*, bin/*) into coi's live
# directory ($COI_HOME, default ~/.coi), and ensure state directories exist.
#
#   ./install.sh [--home DIR] [--dry-run]
#
# Copies tracked files rather than symlinking them ($COI_HOME and $HOME
# placeholders are expanded in profiles/*, executable sources keep mode 755,
# others 644; bin/* files are installed verbatim with mode 755), and creates
# missing state directories (state/desktop/seeds, state/commandcode/projects)
# while leaving existing runtime state untouched. Does not run `coi build` or
# manage host container prerequisites.
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
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  local src=$1 dest=$2 mode=$3 require_verbatim=${4:-0}
  local rendered_tmp
  rendered_tmp="$(mktemp)"
  render_text_file "$src" > "$rendered_tmp"
  if ((require_verbatim)) && ! cmp -s -- "$src" "$rendered_tmp"; then
    rm -f -- "$rendered_tmp"
    echo "error: rendered output differs from source for $src (bin/* must not contain \$COI_HOME or \$HOME)" >&2
    exit 1
  fi

  if [[ ! -L $dest && -f $dest ]] && cmp -s -- "$rendered_tmp" "$dest"; then
    local cur_mode
    cur_mode="$(stat -c '%a' -- "$dest")"
    if [[ $cur_mode == "$mode" ]]; then
      echo "ok       $dest"
    elif ((dry)); then
      echo "would: chmod $mode $dest"
    else
      chmod "$mode" -- "$dest"
      echo "chmod    $dest ($cur_mode -> $mode)"
    fi
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

ensure_dir() {
  local dir=$1 mode=${2:-}
  if [[ -d $dir ]]; then
    if [[ -n $mode ]]; then
      local cur_mode
      cur_mode="$(stat -c '%a' -- "$dir")"
      if [[ $cur_mode != "$mode" ]]; then
        if ((dry)); then
          echo "would: chmod $mode $dir"
        else
          chmod "$mode" -- "$dir"
          echo "chmod    $dir ($cur_mode -> $mode)"
        fi
        return 0
      fi
    fi
    echo "ok       $dir"
    return 0
  fi
  if ((dry)); then
    if [[ -n $mode ]]; then
      echo "would: mkdir -m $mode -p $dir"
    else
      echo "would: mkdir -p $dir"
    fi
    return 0
  fi
  mkdir -p -- "$dir"
  [[ -n $mode ]] && chmod "$mode" -- "$dir"
  echo "mkdir    $dir"
}

if [[ -d $here/profiles ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$here"/}"
    mode=644
    [[ -x $src ]] && mode=755
    install_file "$src" "$home/$rel" "$mode"
  done < <(find "$here/profiles" -type f -print0 | sort -z)
fi

if [[ -d $here/bin ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$here"/}"
    install_file "$src" "$home/$rel" 755 1
  done < <(find "$here/bin" -maxdepth 1 -type f ! -name '_*' -print0 | sort -z)
fi

ensure_dir "$home/state/desktop/seeds" 700
ensure_dir "$home/state/commandcode/projects"
