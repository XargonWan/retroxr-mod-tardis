#!/usr/bin/env python3
"""Build the mod pack and deploy it to RetroXR's mods folder, for testing in the game.

    python3 tools/pack.py                  # build, verify, copy to ~/retroxr/mods/
    python3 tools/pack.py --no-deploy      # build into build/ only
    python3 tools/pack.py --mods-dir DIR   # deploy somewhere else

The zip is made by tools/pack_mod.py, the very packer the release workflow runs, so what is tested here is what is
published (it takes the thumbnail from res/thumbnail.png, leaves out documentation, tests and the originals in src.local/,
and carries the .glb and .mp3 files this mod reads at run time). This script adds what the runner cannot do: it has the
pack read back by RetroXR's own loader (Tools/mods/pack_mod.gd --check, needs Godot) and copies it to the mods folder.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-deploy", action="store_true")
    ap.add_argument("--mods-dir", default=os.path.expanduser("~/retroxr/mods"))
    ap.add_argument("--godot", default=os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64"))
    ap.add_argument("--project", default=os.path.expanduser("~/gits/RetroXR-xargon/RetroXR"))
    args = ap.parse_args()

    manifest = json.load(open(os.path.join(ROOT, "mod.json")))
    mod_id = manifest["id"]
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    out = os.path.join(ROOT, "build", mod_id + ".zip")
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pack_mod.py"), "--out", out])
    if r.returncode != 0:
        sys.exit("pack_mod.py failed: nothing deployed")

    if os.path.exists(args.godot) and os.path.isdir(args.project):
        r = subprocess.run([args.godot, "--headless", "--path", args.project,
                            "--script", "res://Tools/mods/pack_mod.gd", "--", "--check=" + out],
                           capture_output=True, text=True)
        lines = [l for l in r.stdout.splitlines() if l.startswith("[pack]")]
        print("\n".join(lines))
        if not any("verified" in l for l in lines):
            sys.exit("pack_mod.gd --check did not verify the pack")
    else:
        print("Godot or the RetroXR project not found: pack NOT verified by RetroXR's loader")

    if not args.no_deploy:
        os.makedirs(args.mods_dir, exist_ok=True)
        dest = os.path.join(args.mods_dir, mod_id + ".zip")
        shutil.copyfile(out, dest)
        print("deployed to", dest)


main()
