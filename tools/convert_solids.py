"""Find what a player must not walk through in a console room, from its model, and write it as boxes.

    blender -b -P tools/convert_solids.py -- --glb models/interior/10.glb --out models/interior/10_solids.json \\
        --floor "7.0:0,5.8:0.67,4.4:0.67,3.6:0.96,1.5:0.96" --min-r 2.5 --max-r 9.47 \\
        [--cell 0.25] [--above 0.45] [--head 1.6] [--clear "x0,z0,x1,z1" ...]

10_collision.glb (made by convert_interior.py) holds the console, the rotor and the door and nothing else, so the room's
pillars and railings could be walked through. This asks the model itself: the floor plan is cut into cells; a cell is
SOLID when any triangle of the model lies in the column from `--above` metres over the floor there up to `--head` metres
over it (a floor, a step and a ceiling are not in that column; a pillar, a rail and a wall are). `--floor` is the
profile the room walks on (radius:height pairs, as in console_rooms.gd), so that the cells on a platform are judged from
the platform. Touching cells are joined into boxes (rows first, then rows that line up), written in the glTF frame
(x, z; y up) and the model's own metres:

    {"cell": 0.25, "boxes": [[x0, z0, x1, z1, top], ...]}      # each box stands from 0 up to `top`

`--clear` rectangles (x0,z0,x1,z1) are left empty: the doorway, and where the player arrives. The model is only read.
"""
import argparse
import json
import math
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("--glb", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--floor", required=True, help="radius:height,radius:height from the outside in")
ap.add_argument("--min-r", type=float, default=2.5)
ap.add_argument("--max-r", type=float, default=9.47)
ap.add_argument("--cell", type=float, default=0.25)
ap.add_argument("--above", type=float, default=0.45)
ap.add_argument("--head", type=float, default=1.6)
ap.add_argument("--clear", action="append", default=[])
opt = ap.parse_args(argv)

profile = [tuple(float(v) for v in pair.split(":")) for pair in opt.floor.split(",")]
clear = [tuple(float(v) for v in c.split(",")) for c in opt.clear]


def floor_at(r):
    if r >= profile[0][0]:
        return profile[0][1]
    for (r0, h0), (r1, h1) in zip(profile, profile[1:]):
        if r1 <= r <= r0:
            t = (r0 - r) / (r0 - r1)
            return h0 + (h1 - h0) * t
    return profile[-1][1]


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=opt.glb)
scene = bpy.context.scene
dg = bpy.context.evaluated_depsgraph_get()
verts, polys = [], []
for o in scene.objects:
    if o.type != "MESH":
        continue
    me = o.evaluated_get(dg).to_mesh()
    base = len(verts)
    mw = o.matrix_world
    verts.extend(mw @ v.co for v in me.vertices)
    me.calc_loop_triangles()
    polys.extend(tuple(base + i for i in t.vertices) for t in me.loop_triangles)
tree = BVHTree.FromPolygons(verts, polys)
print("MODEL", len(verts), "vertices", len(polys), "triangles")

CUBE = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]
FACES = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)]


def solid(x, y_b, h0, h1):
    """Is there model in the column of one cell at Blender (x, y_b), from z = h0 to z = h1."""
    c = opt.cell
    pts = [Vector((x + (v[0] - 0.5) * c, y_b + (v[1] - 0.5) * c, h0 + v[2] * (h1 - h0))) for v in CUBE]
    return bool(tree.overlap(BVHTree.FromPolygons(pts, FACES)))


n = int(math.ceil(opt.max_r / opt.cell)) + 1
grid = {}
for i in range(-n, n + 1):
    for k in range(-n, n + 1):
        x = i * opt.cell
        z_gl = k * opt.cell
        r = math.hypot(x, z_gl)
        if not (opt.min_r <= r <= opt.max_r):
            continue
        if any(c[0] <= x <= c[2] and c[1] <= z_gl <= c[3] for c in clear):
            continue
        h = floor_at(r / 1.0)
        if solid(x, -z_gl, h + opt.above, h + opt.head):
            grid[(i, k)] = h
print("SOLID CELLS", len(grid))

# rows of touching cells, then rows with the same run joined: boxes
rows = {}
for (i, k) in sorted(grid, key=lambda t: (t[1], t[0])):
    runs = rows.setdefault(k, [])
    if runs and runs[-1][1] == i - 1:
        runs[-1][1] = i
        runs[-1][2] = max(runs[-1][2], grid[(i, k)])
    else:
        runs.append([i, i, grid[(i, k)]])
boxes = []
open_boxes = {}
for k in sorted(rows):
    seen = set()
    for i0, i1, h in rows[k]:
        key = (i0, i1)
        seen.add(key)
        if key in open_boxes and open_boxes[key][1] == k - 1:
            open_boxes[key][1] = k
            open_boxes[key][2] = max(open_boxes[key][2], h)
        else:
            if key in open_boxes:
                boxes.append((key, open_boxes[key]))
            open_boxes[key] = [k, k, h]
    for key in [key for key in open_boxes if key not in seen and open_boxes[key][1] < k]:
        boxes.append((key, open_boxes.pop(key)))
boxes.extend(open_boxes.items())
c = opt.cell
out = []
for (i0, i1), (k0, k1, h) in boxes:
    out.append([round((i0 - 0.5) * c, 3), round((k0 - 0.5) * c, 3), round((i1 + 0.5) * c, 3), round((k1 + 0.5) * c, 3), round(h + opt.head, 2)])
print("BOXES", len(out))
json.dump({"cell": c, "above": opt.above, "head": opt.head, "boxes": out}, open(opt.out, "w"))
# a plan of it, one character per 2 cells, for the log: # = solid
plan = []
for k in range(-n, n + 1, 2):
    plan.append("".join("#" if any((i + a, k + b) in grid for a in (0, 1) for b in (0, 1)) else "." for i in range(-n, n + 1, 2)))
print("PLAN\n" + "\n".join(plan))
