"""Convert the TARDIS exterior (FBX) into the mod's GLB, with an anta (door leaf) of its own.

    blender -b -P tools/convert_tardis.py -- --src <TARDIS.fbx> --out models/tardis/default.glb \\
        [--height 2.3] [--max-tris 12000]

The original is a closed box with four identical sides and no door that moves. This makes the -Y
side (glTF +Z, the front of everything in RetroXR) the door side:
  * the faces of the right leaf (the viewer's right, x > 0) between the corner posts and under the
    sign are split into an object called "DoorR", its origin on the hinge (the outer edge), so that
    turning the node about Y swings it,
  * the origin of the whole is on the floor, in the middle of the base; the height is --height metres
    (the lantern included),
  * what shares a material is joined, and the lettering (most of the 31 000 triangles) is
    decimated to --max-tris,
  * exports a GLB (Y up, textures embedded).
The source is untrusted data: it is only imported, never executed.
"""
import argparse
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("--src", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--height", type=float, default=2.3)
ap.add_argument("--max-tris", type=int, default=12000)
# The door leaf's box in the SOURCE's frame, as fractions of the body's width/height (measured on
# the model: posts at about 0.6 of the half width, the sign from 0.78 of the height).
ap.add_argument("--leaf-x", default="0.03,0.50")
ap.add_argument("--leaf-z", default="0.04,0.77")
ap.add_argument("--leaf-front", type=float, default=0.55, help="faces at least this far out front (0..1 of the half depth)")
opt = ap.parse_args(argv)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=opt.src)
scene = bpy.context.scene


def meshes():
    return [o for o in scene.objects if o.type == "MESH"]


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def bounds(objs):
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w))
            mx = Vector(map(max, mx, w))
    return mn, mx


for o in meshes():  # flatten
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)

# ── frame: floor at z=0, centred on the base, scaled to the height ────────────
mn, mx = bounds(meshes())
k = opt.height / (mx.z - mn.z)
cx, cy = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2
for o in meshes():
    o.matrix_world = Matrix.Scale(k, 4) @ Matrix.Translation(Vector((-cx, -cy, -mn.z))) @ o.matrix_world
bpy.context.view_layer.update()
for o in meshes():
    select_only([o])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mn, mx = bounds(meshes())
print("FRAME", tuple(round(v, 3) for v in mn), tuple(round(v, 3) for v in mx))

# ── the door leaf: faces of the body on the -Y side, right of the seam ───────
body = max(meshes(), key=lambda o: len(o.data.materials))  # the box: the only object with several materials
half_w = (mx.x - mn.x) / 2
half_d = (mx.y - mn.y) / 2
height = mx.z - mn.z
x0, x1 = (float(v) * half_w for v in opt.leaf_x.split(","))
z0, z1 = (mn.z + float(v) * height for v in opt.leaf_z.split(","))
y_front = -half_d * opt.leaf_front
select_only([body])
bpy.ops.object.mode_set(mode="EDIT")
bm = bmesh.from_edit_mesh(body.data)
for f in bm.faces:
    c = body.matrix_world @ f.calc_center_median()
    f.select_set(x0 <= c.x <= x1 and z0 <= c.z <= z1 and c.y <= y_front)
n_leaf = sum(1 for f in bm.faces if f.select)
bmesh.update_edit_mesh(body.data)
bpy.ops.mesh.separate(type="SELECTED")
bpy.ops.object.mode_set(mode="OBJECT")
door = next(o for o in meshes() if o != body and o.name.startswith(body.name))
print("LEAF faces", n_leaf, "of", len(body.data.polygons) + n_leaf)
# origin on the hinge: the outer edge of the leaf, the middle of its height
dmn, dmx = bounds([door])
hinge = Vector((dmx.x, dmn.y if abs(dmn.y) > abs(dmx.y) else dmx.y, 0))
hinge.y = (dmn.y + dmx.y) / 2
hinge.z = dmn.z
scene.cursor.location = hinge
select_only([door])
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
print("HINGE", tuple(round(v, 3) for v in hinge), "leaf", tuple(round(v, 3) for v in dmn), tuple(round(v, 3) for v in dmx))
door.name = "DoorR"

# ── join by material (the lettering), decimate ────────────────────────────────
groups = {}
for o in meshes():
    if o == door:
        continue
    groups.setdefault(tuple(m.name if m else "" for m in o.data.materials), []).append(o)
for group in groups.values():
    if len(group) > 1:
        select_only(group)
        bpy.ops.object.join()


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


total = sum(tris(o) for o in meshes())
print("TRIS before", total)
if total > opt.max_tris:
    keep = tris(door) + tris(body)
    heavy = [o for o in meshes() if o not in (door, body)]
    heavy_tris = sum(tris(o) for o in heavy)
    ratio = max(0.05, (opt.max_tris - keep) / max(1, heavy_tris))
    for o in heavy:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = min(1.0, ratio)
        select_only([o])
        bpy.ops.object.modifier_apply(modifier=m.name)
print("TRIS after", sum(tris(o) for o in meshes()))
n = 0
for o in meshes():
    if o == door:
        continue
    n += 1
    o.name = "Body%d" % n
    o.data.name = o.name
door.data.name = "DoorR"
print("OBJECTS", [(o.name, tris(o)) for o in meshes()])
bpy.ops.export_scene.gltf(filepath=opt.out, export_format="GLB", export_yup=True, export_apply=True,
                          export_image_format="JPEG", export_jpeg_quality=85)
print("WROTE", opt.out)
