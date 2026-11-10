#!/usr/bin/env python3
"""Build the mod pack and deploy it to RetroXR's mods folder.

    python3 tools/pack.py                  # build, verify, copy to ~/retroxr/mods/
    python3 tools/pack.py --no-deploy      # build into build/ only
    python3 tools/pack.py --mods-dir DIR   # deploy somewhere else

Why not RetroXR's own Tools/mods/pack_mod.gd: it packs source files only (.gd .tscn .png ...) and
skips the .glb and .mp3 this mod ships, which it expects to come from a full Godot export. This mod
reads both at run time (GLTFDocument, AudioStreamMP3), so they need no import and travel as they are.
The result is then put through pack_mod.gd --check, the loader's own reader, unless Godot is missing.

Left out of the pack: CLAUDE.md (a .md is refused by RetroXR: it is also a Mega Drive ROM
extension), tools/, tests/, src.local/ (the 300 MB of originals), .git, TODO*, build/.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INCLUDE_TOP = ["mod.json", "mod_main.gd", "mod_main.gd.uid", "thumbnail.png", "README.txt",
               "CREDITS.txt", "scenes", "scripts", "models", "assets", "licenses"]
# RetroXR refuses a pack carrying a program or a game: keep this list honest about what we ship.
FORBIDDEN_EXT = {".md", ".so", ".dll", ".exe", ".iso", ".bin", ".zip", ".nes", ".sfc", ".chd"}


def collect():
    for top in INCLUDE_TOP:
        path = os.path.join(ROOT, top)
        if os.path.isfile(path):
            yield top
        elif os.path.isdir(path):
            for dirpath, _dirs, files in os.walk(path):
                for f in sorted(files):
                    # .import files, and the textures Godot extracts next to a GLB when the project
                    # scans it (the GLB carries its own): editor leftovers, not part of the mod.
                    if f.endswith(".import") or (top == "models" and not f.endswith((".glb", ".json"))):
                        continue
                    yield os.path.relpath(os.path.join(dirpath, f), ROOT)


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
    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in collect():
            if os.path.splitext(rel)[1].lower() in FORBIDDEN_EXT:
                sys.exit("refusing to pack %s: RetroXR would refuse the pack" % rel)
            z.write(os.path.join(ROOT, rel), "mods/%s/%s" % (mod_id, rel.replace(os.sep, "/")))
            n += 1
    print("wrote %s: %d files, %.1f KB, version %s" % (out, n, os.path.getsize(out) / 1024, manifest["version"]))

    if os.path.exists(args.godot) and os.path.isdir(args.project):
        r = subprocess.run([args.godot, "--headless", "--path", args.project,
                            "--script", "res://Tools/mods/pack_mod.gd", "--", "--check=" + out],
                           capture_output=True, text=True)
        lines = [l for l in r.stdout.splitlines() if l.startswith("[pack]")]
        print("\n".join(lines))
        if not any("verified" in l for l in lines):
            sys.exit("pack_mod.gd --check did not verify the pack")
    else:
        print("Godot or the RetroXR project not found: pack NOT verified")

    if not args.no_deploy:
        os.makedirs(args.mods_dir, exist_ok=True)
        dest = os.path.join(args.mods_dir, mod_id + ".zip")
        shutil.copyfile(out, dest)
        print("deployed to", dest)


main()
