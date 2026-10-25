#!/usr/bin/env python3
"""Generate Paseo provider entries for the pi profiles in harness-dots.

    gen-pi-providers.py [--config FILE] [--dry-run | --check]

Reads every pi entry point in pi/bash/ (vpi, pi-ctf, ...) and writes one entry
per profile into agents.providers of paseo/config.json:

    vpi         -> "pi"          overrides Paseo's built-in pi provider
    pi-<name>   -> "pi-<name>"   a custom provider with "extends": "pi"

Each entry launches the entry point itself ("command"), so the appended system
prompt, env_extra and variable scrubbing stay in the entry point's PROFILE
block, and sets PI_CODING_AGENT_DIR ("env") so Paseo's own reads of the
profile (mcp.json, session import) look in the same directory.

An entry is generated (owned) when its command points into pi/bash/. Owned
entries whose entry point is gone are removed. Other providers and any other
keys on owned entries (models, order, enabled, extra env, a hand-set label)
are left alone. Paths are absolute: rerun after moving the repo.

This edits the tracked file only; run ./install.sh to copy it into Paseo.
Stdlib only.
"""

import argparse
import difflib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PI_BASH = ROOT / "pi" / "bash"
PROVIDER_ID = re.compile(r"[a-z][a-z0-9-]*")


def entry_points() -> list[Path]:
    """Executable files in pi/bash/ that are not libraries (same rule as install.sh)."""
    return sorted(p for p in PI_BASH.iterdir()
                  if p.is_file() and p.stat().st_mode & 0o111
                  and not p.name.startswith("_") and not p.name.endswith(".bash"))


def parse_entry(path: Path) -> dict | None:
    """Provider id, label and profile dir of one entry point, or None (with a warning) if unusable."""
    text = path.read_text()
    block = re.search(r"# --- PROFILE -+\n(.*?)\n\s*# -{3,}", text, re.S)
    profile = block and re.search(r"^\s*local profile=(\S+)", block.group(1), re.M)
    if not profile:
        print(f"skip     {path.name}: no PROFILE block with 'local profile='", file=sys.stderr)
        return None
    pid = "pi" if path.name == "vpi" else path.name
    if not PROVIDER_ID.fullmatch(pid):
        print(f"skip     {path.name}: not a valid Paseo provider id", file=sys.stderr)
        return None
    profile_dir = ROOT / "pi" / profile.group(1).strip("'\"")
    if not profile_dir.is_dir():
        print(f"skip     {path.name}: profile directory not found: {profile_dir}", file=sys.stderr)
        return None
    # Third line of the header comment: "# Pi CTF agent", "# Pi vanilla: ..."
    lines = text.splitlines()
    label = lines[2].lstrip("# ").split(":")[0].strip() if len(lines) > 2 and lines[2].startswith("#") else pid
    return {"id": pid, "label": label, "command": str(path), "dir": str(profile_dir)}


def owned(entry: object) -> bool:
    cmd = entry.get("command") if isinstance(entry, dict) else None
    return (isinstance(cmd, list) and bool(cmd) and isinstance(cmd[0], str)
            and Path(cmd[0]).parent == PI_BASH)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", type=Path, default=HERE / "config.json", help="config to edit (default: paseo/config.json)")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="print the diff, write nothing")
    mode.add_argument("--check", action="store_true", help="exit 1 if the config is out of date")
    a = ap.parse_args()

    before = a.config.read_text() if a.config.exists() else "{}\n"
    config = json.loads(before)
    providers = config.setdefault("agents", {}).setdefault("providers", {})

    wanted = {e["id"]: e for p in entry_points() if (e := parse_entry(p))}

    for pid in [pid for pid, entry in providers.items() if owned(entry) and pid not in wanted]:
        print(f"remove   {pid} (entry point gone)")
        del providers[pid]

    for pid, e in wanted.items():
        entry = providers.get(pid)
        if entry is not None and "command" in entry and not owned(entry):
            print(f"skip     {pid}: existing entry has its own command; edit or remove it by hand", file=sys.stderr)
            continue
        entry = providers.setdefault(pid, {})
        if pid != "pi":   # the built-in keeps its own id and label
            entry["extends"] = "pi"
            entry.setdefault("label", e["label"])
        entry["command"] = [e["command"]]
        entry.setdefault("env", {})["PI_CODING_AGENT_DIR"] = e["dir"]

    after = json.dumps(config, indent=2, ensure_ascii=False) + "\n"
    if after == before:
        print(f"ok       {a.config} is up to date")
        return 0
    if a.check:
        print(f"stale    {a.config}: run {Path(__file__).name}", file=sys.stderr)
        return 1
    diff = difflib.unified_diff(before.splitlines(True), after.splitlines(True), str(a.config), f"{a.config} (generated)")
    sys.stdout.writelines(diff)
    if not a.dry_run:
        a.config.write_text(after)
        print(f"wrote    {a.config}\nnext:    {HERE}/install.sh --dry-run")
    return 0


if __name__ == "__main__":
    sys.exit(main())
