#!/usr/bin/env bash
# Some profiles might share settings,
# while others will maintain bespoke
# versions of their own.
#
# Links the shared settings.json into each pi profile below. Run from
# anywhere; paths are relative to this file (the pi/ dir of the dots repo).
# Existing settings.json files and links are left alone.

here="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)"

# Settings Files
settings0="${here}/settings.json"

# Pi Profiles
pi0="${here}/agent"
pi1="${here}/agent_ctf"
pi2="${here}/agent_producer"

link() { [[ -e $2 || -L $2 ]] && echo "exists   $2" || ln -s "$1" "$2"; }

# LINK
link ${settings0} ${pi0}/settings.json # settings0 -> default pi
link ${settings0} ${pi1}/settings.json # settings0 -> ctf pi
link ${settings0} ${pi2}/settings.json # settings0 -> producer pi
