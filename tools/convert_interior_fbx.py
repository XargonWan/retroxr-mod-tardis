"""Convert an interior that comes as one FBX (no textures, flat lambert colours) into the mod's console room GLB.

    blender -b -P tools/convert_interior_fbx.py -- --src "<file>.fbx" --out models/interior/1.glb \\
        --meta models/interior/1.json [--scale 60] [--console-ratio 0.18]

Made for the First Doctor's room ("type 30 tardis animated", src.local/interior/1): an octagonal room, a
hexagonal console, a time rotor, 200 000 triangles of which 158 000 are the console. Its units are cm read as
m, so it comes in 1/55 of the size of a room: `--scale` brings it to metres (60: a door 1.15 m wide, a console
1.9 m across, a room 9 m between walls).

  * everything that is not a mesh is dropped (2 290 empty transforms),
  * the geometry is taken to metres and moved so that the origin is on the floor under the console (the floor
    is found by rays dropped on a ring round it), the door wall on glTF's +Z (Blender's -Y),
  * the console is decimated to `--console-ratio`,
  * materials become one plain material per colour (the lambert colours; the cream roundels and the console's
    lamps glow a little), so the room is a mesh of about 15 surfaces,
  * the two time-rotor parts stay objects of their own ("Rotor1", "Rotor2") for the room to move,
  * `--meta` gets what the mod needs: the door, the rotors, the radius and the height of the room.

The door is the thin panel on the south wall (the room has two door-like panels; this one is on the wall the
mod puts the player's back to). The source is untrusted data: it is only opened, never run.
"""
import argparse
import json
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("--src", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--meta", required=True)
ap.add_argument("--scale", type=float, default=60.0)
ap.add_argument("--console-ratio", type=float, default=0.18)
opt = ap.parse_args(argv)

CONSOLE = "pCube1195"
ROOM = "empty_console_room:pCylinder940"
ROTORS = ["polySurface2292.001", "polySurface2337.001"]
# a colour that glows a little: the cream of the roundels, the red-orange lamps of the console
GLOW = {(0.97, 0.97, 1.0): 0.22, (1.0, 0.23, 0.0): 1.2}
# the photographs of the set: the console is pale mint green, the rotor's tube is clear acrylic; the door is made
# a different colour from the white wall, or nobody finds it
MINT = (0.62, 0.8, 0.72)
DOOR = (0.2, 0.26, 0.34)
GLASS_ALPHA = 0.2

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=opt.src)
for o in list(bpy.data.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o)
objs = {o.name: o for o in bpy.data.objects}
for name in [ROOM, CONSOLE] + ROTORS:
    if name not in objs:
        sys.exit("missing object %s: this is not the file this converter was written for" % name)

# bake every transform into the geometry, in metres
for o in bpy.data.objects:
    o.animation_data_clear()
    mw = o.matrix_world.copy()
    o.parent = None
    o.data.transform(Matrix.Scale(opt.scale, 4) @ mw)
    o.matrix_world = Matrix.Identity(4)

# the console's middle and the floor under it
cv = [v.co for v in objs[CONSOLE].data.vertices]
cx = (min(v.x for v in cv) + max(v.x for v in cv)) / 2.0
cy = (min(v.y for v in cv) + max(v.y for v in cv)) / 2.0
con_top = max(v.z for v in cv)
bm = bmesh.new()
bm.from_mesh(objs[ROOM].data)
tree = BVHTree.FromBMesh(bm)
hits = []
for r in (2.4, 3.0, 3.6):
    for k in range(16):
        a = k * math.tau / 16
        h = tree.ray_cast(Vector((cx + r * opt.scale / 55.0 * math.cos(a), cy + r * opt.scale / 55.0 * math.sin(a), con_top + 0.2)), Vector((0, 0, -1)))
        if h[0] is not None:
            hits.append(h[0].z)
hits.sort()
floor = hits[len(hits) // 2]
print("console centre", round(cx, 2), round(cy, 2), "floor", round(floor, 3), "rays", len(hits))
shift = Matrix.Translation((-cx, -cy, -floor))
for o in bpy.data.objects:
    o.data.transform(shift)

# the door: a thin panel on the south wall (a component of its material, 1.2 m wide, 1.8 m tall)
bm = bmesh.new()
bm.from_mesh(objs[ROOM].data)
bm.faces.ensure_lookup_table()
seen = set()
door = None
for f in bm.faces:
    if f.index in seen:
        continue
    stack, comp = [f], [f]
    seen.add(f.index)
    while stack:
        cur = stack.pop()
        for e in cur.edges:
            for nf in e.link_faces:
                if nf.index not in seen and nf.material_index == f.material_index:
                    seen.add(nf.index)
                    stack.append(nf)
                    comp.append(nf)
    vs = [v.co for ff in comp for v in ff.verts]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    sz, mid = mx - mn, (mn + mx) / 2.0
    if 0.9 < sz.x < 1.5 and sz.y < 0.3 and 1.4 < sz.z < 2.3 and mid.y < -2.0 and abs(mid.x) < 1.0 and abs(mn.z) < 0.7:
        door = (mid, sz, mn.z)
        door_polys = [ff.index for ff in comp]
if door is None:
    sys.exit("no door panel found on the south wall")
mid, dsz, dmin = door
print("door at", tuple(round(x, 2) for x in mid), "size", tuple(round(x, 2) for x in dsz))
bm.free()

# plain materials, one per colour
mats = {}


def material_for(src, obj_name=""):
    col = (0.5, 0.5, 0.5)
    if src is not None and src.node_tree:
        for n in src.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                col = tuple(n.inputs["Base Color"].default_value[:3])
    glass = src is not None and src.name.endswith("lambert6")
    here = tuple(round(c, 2) for c in col)
    if obj_name == CONSOLE and here in ((0.5, 0.5, 0.5), (1.0, 0.99, 0.72)):
        col = MINT
    elif obj_name == ROOM and here == (1.0, 0.99, 0.72):
        col = (0.97, 0.97, 1.0)  # the roundels are white in the photographs, not cream
    elif obj_name == ROOM and here == (0.5, 0.5, 0.5):
        col = (0.82, 0.82, 0.86)
    key = ("glass",) if glass else tuple(round(c, 2) for c in col)
    if key not in mats:
        shown = (1.0, 1.0, 1.0) if glass else key
        m = bpy.data.materials.new("glass" if glass else "M_%02x%02x%02x" % tuple(int(round(c * 255)) for c in key))
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (shown[0], shown[1], shown[2], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.85 if not glass else 0.1
        bsdf.inputs["Metallic"].default_value = 0.0
        if glass:
            bsdf.inputs["Alpha"].default_value = GLASS_ALPHA
            m.blend_method = "BLEND"
        if key in GLOW:
            bsdf.inputs["Emission Color"].default_value = (key[0], key[1], key[2], 1.0)
            bsdf.inputs["Emission Strength"].default_value = GLOW[key]
        mats[key] = m
    return mats[key]


for o in bpy.data.objects:
    me = o.data
    olds = list(me.materials)
    remap = []
    new_slots = []
    for m in olds:
        nm = material_for(m, o.name)
        if nm not in new_slots:
            new_slots.append(nm)
        remap.append(new_slots.index(nm))
    # (clearing the slots zeroes every polygon's index: keep them aside and put them back)
    kept = [remap[min(p.material_index, len(remap) - 1)] for p in me.polygons]
    me.materials.clear()
    for nm in new_slots:
        me.materials.append(nm)
    for p, k in zip(me.polygons, kept):
        p.material_index = k

# the door panel: a colour of its own
door_mat = bpy.data.materials.new("door")
door_mat.use_nodes = True
db = door_mat.node_tree.nodes["Principled BSDF"]
db.inputs["Base Color"].default_value = (DOOR[0], DOOR[1], DOOR[2], 1.0)
db.inputs["Roughness"].default_value = 0.6
rme = objs[ROOM].data
rme.materials.append(door_mat)
for pi in door_polys:
    rme.polygons[pi].material_index = len(rme.materials) - 1

# the console: decimated
bpy.context.view_layer.objects.active = objs[CONSOLE]
before = len(objs[CONSOLE].data.polygons)
mod = objs[CONSOLE].modifiers.new("d", "DECIMATE")
mod.ratio = opt.console_ratio
mod.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=mod.name)
print("console faces", before, "->", len(objs[CONSOLE].data.polygons))

# the rotor parts keep a node of their own
rotors = []
for i, name in enumerate(ROTORS):
    o = objs[name]
    o.name = "Rotor%d" % (i + 1)
    vs = [v.co for v in o.data.vertices]
    sz = [max(v[a] for v in vs) - min(v[a] for v in vs) for a in range(3)]
    rotors.append({"name": o.name, "size": [round(sz[0], 3), round(sz[2], 3), round(sz[1], 3)]})

# the room and the console become one mesh with a surface per colour
bpy.ops.object.select_all(action="DESELECT")
objs[ROOM].select_set(True)
objs[CONSOLE].select_set(True)
bpy.context.view_layer.objects.active = objs[ROOM]
bpy.ops.object.join()
room = bpy.context.view_layer.objects.active
room.name = "Room"
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(50))
tris = sum(len(p.vertices) - 2 for p in room.data.polygons)
from collections import Counter
cnt = Counter(p.material_index for p in room.data.polygons)
print("SURFACES", [(room.data.materials[i].name, n) for i, n in sorted(cnt.items())])
print("room tris", tris, "surfaces", len(room.data.materials))

rv = [v.co for v in room.data.vertices]
radius = abs(mid.y) - dsz.y / 2.0 - 0.05
meta = {
    "scale_blender_to_m": opt.scale,
    "floor_z_blender": round(floor, 3),
    "door": {"centre": [round(mid.x, 3), round(mid.z, 3), round(-mid.y, 3)], "size": [round(dsz.x, 3), round(dsz.z, 3)]},
    "rotors": rotors,
    "wall_radius_p98": round(radius, 2),
    "height_range": [round(min(v.z for v in rv), 2), round(max(v.z for v in rv), 2)],
    "console_radius": round(max(max(v.x for v in cv) - min(v.x for v in cv), max(v.y for v in cv) - min(v.y for v in cv)) / 2.0, 2),
    "console_height": round(con_top - floor, 2),
    "triangles": tris,
}
with open(opt.meta, "w") as fh:
    json.dump(meta, fh, indent=2)
print(json.dumps(meta))

bpy.ops.export_scene.gltf(filepath=opt.out, export_format="GLB", export_yup=True, export_apply=False,
    export_animations=False, export_materials="EXPORT", export_image_format="NONE", export_cameras=False, export_lights=False)
print("FINISHED", opt.out)
