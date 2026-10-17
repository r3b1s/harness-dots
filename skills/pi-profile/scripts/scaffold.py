#!/usr/bin/env python3
"""Scaffold a Pi profile in harness-dots/pi/: profile dir, bash entry point, link.sh and .gitignore entries.

    scaffold.py NAME --label "video producer" [--skill DIR ...] [--mcp copy|none]
                [--env NAME=value ...] [--link] [--dry-run]

NAME gives the profile dir pi/agent_<name> and the command pi-<name>. Stdlib only.
Idempotent: every step that is already done is reported and skipped.
The system prompt (system-prompts/append_<name>_<rev>.md) must exist first; this
script never writes prose for you. It does not touch ~/.local/bin or the mise
config: run ./install.sh to link the command onto PATH.
"""

import argparse
import os
import re
import shlex
import shutil
import sys
from pathlib import Path

ENTRY = """#!/usr/bin/env bash
# shellcheck shell=bash
# Pi {label} agent
#
# Two ways to use this file:
#   run it     symlink it onto PATH (../../install.sh) and call `{cmd} ...`
#   source it  defines the `{cmd}` function in the current shell
# Pi's own subcommands work as usual: `{cmd} install npm:pkg`, `{cmd} list`.

_PI_BASH_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${{BASH_SOURCE[0]}}")")" && pwd -P)"
# shellcheck source=_launch.bash
source "$_PI_BASH_DIR/_launch.bash"

{cmd}() {{
  # --- PROFILE ---------------------------------------------------------------
  local profile={profile}
  local prompt={prompt}   # a file in the repo's system-prompts/; "" for none
  local -a env_extra=({env})   # extra environment for this profile, e.g. (NAME=value)
  # ---------------------------------------------------------------------------
  _pi_launch "$profile" "$prompt" "${{env_extra[@]}}" -- "$@"
}}

if [[ ${{BASH_SOURCE[0]}} == "$0" ]]; then
  {cmd} "$@"
fi
"""


def find_root() -> Path | None:
    """The harness-dots checkout: the nearest parent of this script, or of the cwd, holding pi/bash/_launch.bash."""
    for start in (Path(__file__).resolve(), Path.cwd().resolve()):
        for p in (start, *start.parents):
            if (p / "pi" / "bash" / "_launch.bash").is_file():
                return p
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", help="short name: lowercase letters, digits, hyphens (command pi-<name>)")
    ap.add_argument("--label", required=True, help='header text: "Pi <label> agent"')
    ap.add_argument("--skill", action="append", default=[], type=Path, help="skill directory to copy in (repeatable)")
    ap.add_argument("--mcp", choices=["copy", "none"], default="none", help="copy agent/mcp.json as a starting point")
    ap.add_argument("--env", action="append", default=[], metavar="NAME=value", help="extra environment for this profile (repeatable)")
    ap.add_argument("--rev", default="0", help="system prompt revision suffix (default 0)")
    ap.add_argument("--link", action="store_true", help="symlink the shared settings.json, auth.json and models.json into the profile")
    ap.add_argument("--repo", "--pi-dir", dest="pi_dir", type=Path, help="harness-dots repo root (default: found from this script or the cwd)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not re.fullmatch(r"[a-z][a-z0-9-]*", a.name):
        sys.exit("name must match [a-z][a-z0-9-]*")
    for e in a.env:
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", e):
            sys.exit(f"--env expects NAME=value, got: {e}")
    root = (a.pi_dir.expanduser().resolve() if a.pi_dir
            else find_root() or sys.exit("could not find harness-dots (pi/bash/_launch.bash); pass --repo"))
    pi_dir = root / "pi"   # the pi harness dir; system-prompts/ stays at the repo root
    under = a.name.replace("-", "_")
    cmd = f"pi-{a.name}"
    profile = pi_dir / f"agent_{under}"
    prompt_name = f"append_{under}_{a.rev}.md"
    prompt = root / "system-prompts" / prompt_name
    entry = pi_dir / "bash" / cmd

    if not prompt.exists():
        sys.exit(f"missing system prompt (author it first): {prompt}")
    for s in a.skill:
        if not (s / "SKILL.md").is_file():
            sys.exit(f"not a skill directory (no SKILL.md): {s}")

    todo: list[tuple[str, callable]] = []

    def step(msg, fn):
        todo.append((msg, fn))

    # 1. Profile dir, skills, mcp.json
    if profile.exists():
        print(f"= profile exists: {profile}")
    else:
        step(f"mkdir {profile}", lambda: profile.mkdir())
    for s in a.skill:
        dest = profile / "skills" / s.name
        if dest.exists():
            print(f"= skill already copied: {dest}")
        else:
            step(f"copy skill {s} -> {dest}",
                 lambda s=s, dest=dest: (dest.parent.mkdir(parents=True, exist_ok=True), shutil.copytree(s, dest)))
    mcp_src, mcp_dst = pi_dir / "agent" / "mcp.json", profile / "mcp.json"
    if a.mcp == "copy":
        if mcp_dst.exists():
            print(f"= mcp.json exists: {mcp_dst}")
        else:
            step(f"copy {mcp_src} -> {mcp_dst}", lambda: shutil.copy(mcp_src, mcp_dst))

    # 2. bash entry point
    if entry.exists():
        print(f"= entry point exists: {entry}")
    else:
        entry_text = ENTRY.format(label=a.label, cmd=cmd, profile=f"agent_{under}", prompt=prompt_name,
                            env=" ".join(shlex.quote(e) for e in a.env))
        def write_entry():
            entry.write_text(entry_text)
            entry.chmod(0o755)
        step(f"write {entry}", write_entry)

    # 3. link.sh: add the profile to its profiles=( ... ) list
    link = pi_dir / "link.sh"
    text = link.read_text()
    m = re.search(r"^profiles=\(\n(.*?)^\)", text, re.M | re.S)
    if not m:
        sys.exit("link.sh has no 'profiles=(' list to extend")
    if re.search(rf"^\s+agent_{under}$", m.group(1), re.M):
        print("= link.sh already lists the profile")
    else:
        new_text = text[:m.end(1)] + f"  agent_{under}\n" + text[m.end(1):]
        step(f"link.sh: add agent_{under} to profiles", lambda: link.write_text(new_text))

    # 4. .gitignore
    gi = pi_dir / ".gitignore"
    entry_ignore = f"agent_{under}/settings.json"
    gtext = gi.read_text()
    if entry_ignore in gtext.splitlines():
        print("= .gitignore already ignores the profile settings.json")
    else:
        glines = gtext.split("\n")
        idx = [i for i, l in enumerate(glines) if re.fullmatch(r"agent\w*/settings\.json", l)]
        if not idx:
            sys.exit(".gitignore has no 'agent*/settings.json' block to extend")
        glines.insert(idx[-1] + 1, entry_ignore)
        step(f".gitignore: add {entry_ignore}", lambda: gi.write_text("\n".join(glines)))

    # 5. shared-file symlinks (what link.sh would make for this profile)
    if a.link:
        for name in ("settings.json", "auth.json", "models.json"):
            dest = profile / name
            if not (pi_dir / name).exists():
                print(f"= no shared pi/{name} yet (run link.sh later)")
            elif dest.is_symlink() or dest.exists():
                print(f"= {name} already present in profile")
            else:
                step(f"symlink {dest} -> ../{name}", lambda dest=dest, name=name: dest.symlink_to(f"../{name}"))

    if not todo:
        print("nothing to do")
        return 0
    for msg, fn in todo:
        print(("would: " if a.dry_run else "do: ") + msg)
        if not a.dry_run:
            fn()
    if not a.dry_run:
        print(f"\nnext:\n  {root}/install.sh --only {cmd} --dry-run   # then without --dry-run to link it onto PATH")
    return 0


if __name__ == "__main__":
    sys.exit(main())
