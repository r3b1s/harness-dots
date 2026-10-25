#!/usr/bin/env bash
# Copy the tracked paseo/config.json into Paseo's live config
# ($PASEO_HOME/config.json, default ~/.paseo/config.json).
#
#   ./install.sh [--home DIR] [--replace] [--reload] [--dry-run]
#
# The live file is a copy, never a link: Paseo writes UI changes and the daemon
# password (daemon.auth) into it, and those must not land in this repo.
#
# Default: deep-merge the tracked config over the live one. Objects merge key
# by key; arrays of objects that all carry an "id" (daemon.agentProfiles,
# daemon.terminalProfiles) merge by id; anything else takes the tracked value.
# Whatever exists only in the live file (password, UI-made profiles, providers
# you added in the app) is kept, so a provider deleted from the tracked file
# stays live until removed in the app or with --replace.
#
# --replace  write the tracked file as is, keeping only the live daemon.auth.
# --reload   run `paseo reload` afterwards (otherwise run it yourself).
# --dry-run  show the diff, write nothing.
#
# The previous live file is kept as config.json.bak. Refuses to run if the
# tracked config carries daemon.auth.
set -euo pipefail

here="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)"
src="$here/config.json"
home="${PASEO_HOME:-$HOME/.paseo}"
replace=0 reload=0 dry=0

while (($#)); do
  case "$1" in
    --home)    home="$2"; shift ;;
    --replace) replace=1 ;;
    --reload)  reload=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null || { echo "paseo: jq is required" >&2; exit 127; }
home="${home/#\~/$HOME}"
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
  def ided: type == "array" and length > 0 and all(.[]; type == "object" and has("id"));
  def merge($a; $b):
    if ($a | type) == "object" and ($b | type) == "object" then
      reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
    elif ($a | ided) and ($b | ided) then
      reduce $b[] as $e ($a;
        if any(.[]; .id == $e.id) then map(if .id == $e.id then merge(.; $e) else . end)
        else . + [$e] end)
    else $b end;
  if $replace then
    $src + (if $live.daemon.auth? != null
            then {daemon: (($src.daemon // {}) + {auth: $live.daemon.auth})} else {} end)
  else merge($live; $src) end'

replace_json=false; ((replace)) && replace_json=true
next="$(jq -n --argjson live "$live" --slurpfile s "$src" --argjson replace "$replace_json" \
  "\$s[0] as \$src | $merge")"

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
    echo "wrote    $dest"
    ((reload)) || echo "next:    paseo reload   # apply without restarting the daemon"
  fi
fi

if ((reload)); then
  if ((dry)); then echo "would: paseo reload"; else paseo reload; fi
fi
