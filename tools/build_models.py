#!/usr/bin/env python3
"""Build the screwdriver GLBs from the originals in src.local/ (needs Blender; see CLAUDE.md).

    python3 tools/build_models.py            # all of them
    python3 tools/build_models.py 10 11      # these ids

Each model's settings live in MODELS below: the source file, which way its tip points IN THE
SOURCE, its length, and what is its LED. Extracting an archive is done here, into a temporary
directory (the archives are untrusted data: nothing in them is run).
"""
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLENDER = os.path.expanduser("~/gits/RetroQUEST/blender-4.2.3-linux-x64/blender")
SRC = os.path.join(ROOT, "src.local", "screwdriver")

# id -> (archive, file inside it, converter options). Lengths in metres.
MODELS = {
    "10": ("10/Sonic_Screwdriver_10th_Doctor.usdz", "scene.usdc",
           ["--length", "0.17", "--tip", "+Z", "--led-material", "Material__120", "--led-above", "0.955"]),
    "2": ("2/mk-6-screwdriver.zip", "source/mk 6 screwdriver.fbx",
          ["--length", "0.168", "--tip", "+Z"]),
    "3": ("3/mk-2-screwdriver.zip", "source/mk 2 screwdriver.fbx",
          ["--length", "0.171", "--tip", "+Z"]),
    "4": ("4/fourth-doctors-sonic-screwdriver.zip", "source/Fourth_Doctor's_Sonic_Screwdriver.blend.blend",
          ["--length", "0.16", "--tip=-Y", "--drop", "Plane.*"]),
    "5": ("5/Classic_Styled_Sonic_ScrewDriver.usdz", "scene.usdc",
          ["--length", "0.17", "--tip", "+Z"]),
    # The "posed" FBX holds two copies of the screwdriver (the .001 parts are a second pose, the tip
    # further out). The first is kept. Its tip is at -X. The glass tip is the LED.
    "11": ("11/Unconfirmed 475537.crdownload", "source/screwPosed.fbx",
           ["--length", "0.111", "--tip=-X", "--led-object", "tip_refr",
            "--drop", r"handle\.001|tip\.001|bolt\.001|tip_refr\.001|cog\.00[4-7]",
            "--tex", "screwdriver_tip:Material"]),
    "12": ("12/doctor-who-sonic-screwdriver-free-download.zip", "source/Doctor Who Sonic Screwdriver (12th).fbx",
           ["--length", "0.19", "--tip", "+Z"]),
    "13": ("13/doctor-who-sonic-screwdriver-low-poly.zip", "source/maya2sketchfab.fbx",
           ["--length", "0.157", "--tip", "+Z", "--led-material", "blinn1"]),
}


def main():
    ids = sys.argv[1:] or list(MODELS)
    for mid in ids:
        archive, member, opts = MODELS[mid]
        tmp = tempfile.mkdtemp(prefix="screwdriver_%s_" % mid)
        try:
            with zipfile.ZipFile(os.path.join(SRC, archive)) as z:
                z.extractall(tmp)
            for dirpath, _d, names in os.walk(tmp):  # a zip inside the zip (the 12th's)
                for n in names:
                    if n.lower().endswith(".zip"):
                        with zipfile.ZipFile(os.path.join(dirpath, n)) as inner:
                            inner.extractall(dirpath)
            out = os.path.join(ROOT, "models", "screwdriver", mid + ".glb")
            cmd = [BLENDER, "-b", "-P", os.path.join(ROOT, "tools", "convert_screwdriver.py"), "--",
                   "--src", os.path.join(tmp, member), "--out", out, "--tex-dir", tmp] + opts
            r = subprocess.run(cmd, capture_output=True, text=True)
            keep = [l for l in r.stdout.splitlines() if l.split(" ")[0] in
                    ("TRIS", "LED", "MATERIAL", "BOUNDS", "OBJECTS", "TEXTURES", "WROTE")]
            print("== %s\n%s" % (mid, "\n".join(keep)))
            if r.returncode != 0 or not os.path.exists(out):
                print(r.stdout[-1500:], r.stderr[-1500:])
                sys.exit("conversion of %s failed" % mid)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


main()
