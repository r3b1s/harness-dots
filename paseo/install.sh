#!/usr/bin/env bash
# Copy tracked Paseo config and provider wrappers (bin/*) into Paseo's live
# directory ($PASEO_HOME, default ~/.paseo).
#
#   ./install.sh [--home DIR] [--replace] [--reload] [--dry-run]
#
# Live files are copies, never links: Paseo writes UI changes and the daemon
# password (daemon.auth) into config.json, and those must not land in this repo.
#
# Default: deep-merge tracked config.json over the live one ($PASEO_HOME,
# $COI_HOME and $HOME placeholders in config.json are expanded to target paths).
# Objects merge key by key; arrays of objects that all carry an "id"
# (daemon.agentProfiles, daemon.terminalProfiles) merge by id; anything else
# takes the tracked value. Whatever exists only in the live file (password,
# UI-made profiles, providers you added in the app) is kept, so a provider
# deleted from the tracked file stays live until removed in the app or with
# --replace. Wrapper scripts in bin/* are copied to $PASEO_HOME/bin/*.
#
# --replace  write the tracked config.json as is, keeping only live daemon.auth.
# --reload   run `paseo reload` afterwards (otherwise run it yourself).
# --dry-run  show diffs, write nothing.
#
# The previous live config.json is kept as config.json.bak. Refuses to run if
# tracked config.json carries daemon.auth.
set -euo pipefail

here="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)"
src="$here/config.json"
home="${PASEO_HOME:-$HOME/.paseo}"
coi_home="${COI_HOME:-$HOME/.coi}"
replace=0 reload=0 dry=0 changed=0

while (($#)); do
  case "$1" in
    --home)    home="$2"; shift ;;
    --replace) replace=1 ;;
    --reload)  reload=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null || { echo "paseo: jq is required" >&2; exit 127; }
expand_tilde() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#"~/"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
home="$(expand_tilde "$home")"
[[ $home != / ]] && home="${home%/}"
coi_home="$(expand_tilde "$coi_home")"
[[ $coi_home != / ]] && coi_home="${coi_home%/}"
dest="$home/config.json"

jq -e 'type == "object"' "$src" >/dev/null || { echo "paseo: $src is not a JSON object" >&2; exit 1; }
if jq -e '.daemon.auth? != null' "$src" >/dev/null; then
  echo "paseo: $src contains daemon.auth; keep the password out of the repo" >&2
  exit 1
fi

if [[ -e $dest ]]; then
  live="$(cat -- "$dest")"
else
  live='{}'
fi

# shellcheck disable=SC2016  # jq program, not shell expansion
merge='
  def render($paseo_home; $coi_home; $user_home):
    walk(if type == "string"
         then split("$PASEO_HOME") | join($paseo_home)
              | split("$COI_HOME") | join($coi_home)
              | split("$HOME") | join($user_home)
         else . end);
  def ided: type == "array" and length > 0 and all(.[]; type == "object" and has("id"));
  def merge($a; $b):
    if ($a | type) == "object" and ($b | type) == "object" then
      reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
    elif ($a | ided) and ($b | ided) then
      reduce $b[] as $e ($a;
        if any(.[]; .id == $e.id) then map(if .id == $e.id then merge(.; $e) else . end)
        else . + [$e] end)
    else $b end;
  ($s[0] | render($paseo_home; $coi_home; $user_home)) as $src |
  if $replace then
    $src + (if $live.daemon.auth? != null
            then {daemon: (($src.daemon // {}) + {auth: $live.daemon.auth})} else {} end)
  else merge($live; $src) end'

replace_json=false; ((replace)) && replace_json=true
next="$(jq -n \
  --argjson live "$live" \
  --slurpfile s "$src" \
  --argjson replace "$replace_json" \
  --arg paseo_home "$home" \
  --arg coi_home "$coi_home" \
  --arg user_home "$HOME" \
  "$merge")"

if [[ "$(jq -S . <<<"$live")" == "$(jq -S . <<<"$next")" ]]; then
  echo "ok       $dest is up to date"
else
  diff -u --label "$dest" --label "$dest (new)" <(jq . <<<"$live") <(printf '%s\n' "$next") || true
  if ((dry)); then
    echo "would: write $dest"
  else
    mkdir -p -- "$home"
    [[ -e $dest ]] && { cp -p -- "$dest" "$dest.bak"; echo "backup   $dest.bak"; }
    tmp="$(mktemp -- "$home/.config.json.XXXXXX")"
    printf '%s\n' "$next" > "$tmp"
    chmod 600 -- "$tmp"
    mv -f -- "$tmp" "$dest"
    changed=1
    echo "wrote    $dest"
  fi
fi

install_copied_file() {
  local src_file=$1 dest_file=$2 mode=$3

  local mode_ok=1
  if [[ $mode == 755 && ! -x $dest_file ]]; then
    mode_ok=0
  fi

  if [[ ! -L $dest_file && -f $dest_file ]] && ((mode_ok)) && cmp -s -- "$src_file" "$dest_file"; then
    echo "ok       $dest_file"
    return 0
  fi

  if [[ -e $dest_file ]]; then
    if cmp -s -- "$src_file" "$dest_file"; then
      echo "chmod    $dest_file ($mode)"
    else
      diff -u --label "$dest_file" --label "$dest_file (new)" "$dest_file" "$src_file" || true
    fi
  else
    diff -u --label /dev/null --label "$dest_file (new)" /dev/null "$src_file" || true
  fi

  if ((dry)); then
    echo "would: write $dest_file"
    return 0
  fi

  mkdir -p -- "$(dirname -- "$dest_file")"
  local tmp
  tmp="$(mktemp -- "$(dirname -- "$dest_file")/.paseo-install.XXXXXX")"
  cp -- "$src_file" "$tmp"
  chmod "$mode" -- "$tmp"
  mv -f -- "$tmp" "$dest_file"
  changed=1
  echo "wrote    $dest_file"
}

if [[ -d $here/bin ]]; then
  for src_bin in "$here"/bin/*; do
    [[ -f $src_bin ]] || continue
    name="$(basename -- "$src_bin")"
    [[ $name != _* ]] || continue
    install_copied_file "$src_bin" "$home/bin/$name" 755
  done
fi

if ((changed && ! dry && ! reload)); then
  echo "next:    paseo reload   # apply config changes without restarting the daemon"
fi

if ((reload)); then
  if ((dry)); then echo "would: paseo reload"; else paseo reload; fi
fi
