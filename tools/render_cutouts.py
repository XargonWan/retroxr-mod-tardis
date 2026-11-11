"""Render each model on its own with NO background (a PNG with an alpha channel), to be cut into a collage.

    blender -b -P tools/render_cutouts.py -- OUT_DIR [--size 2048] [--only tardis|screwdrivers|ID ...]

Writes into OUT_DIR (src.local/res/ is where the mod author keeps them: it is git-ignored):
    tardis_closed.png, tardis_open.png     the TARDIS from the front three-quarter, the door shut and wide open
    screwdriver_<id>.png                   every Doctor's screwdriver, tip up, from a three-quarter view,
                                           its LED lit in the colour the mod gives it (10th blue, 11th green, 13th amber)
The picture is as tall as --size and as wide as the model needs, cropped to the model plus a margin, so the
files drop into an image editor already trimmed. Cycles on the CPU (no GPU is needed, so it works in a
terminal); a neutral grey sky lights the metal, with a key and a rim light.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:]
out_dir = argv[0]
size = 2048
only = []
i = 1
while i < len(argv):
    if argv[i] == "--size":
        size = int(argv[i + 1])
        i += 2
    elif argv[i] == "--only":
        i += 1
        while i < len(argv) and not argv[i].startswith("--"):
            only.append(argv[i])
            i += 1
    else:
        i += 1
os.makedirs(out_dir, exist_ok=True)

LED = {"10": (0.25, 0.5, 1.0), "11": (0.3, 1.0, 0.75), "13": (1.0, 0.6, 0.2)}
SCREWDRIVERS = ["2", "3", "4", "5", "10", "11", "12", "13"]


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = 64
    scn.cycles.use_denoising = True
    scn.render.film_transparent = True
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA"
    scn.view_settings.view_transform = "Standard"
    scn.world = bpy.data.worlds.new("w")
    scn.world.use_nodes = True
    bg = scn.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.75, 0.78, 0.85, 1)
    bg.inputs[1].default_value = 0.8
    return scn


def light(scn, name, kind, energy, rot, color=(1, 1, 1)):
    ob = bpy.data.objects.new(name, bpy.data.lights.new(name, kind))
    ob.data.energy = energy
    ob.data.color = color
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    scn.collection.objects.link(ob)


def bounds(objs):
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w))
            mx = Vector(map(max, mx, w))
    return mn, mx


def shoot(scn, objs, direction, path, margin=0.06):
    """Frame `objs` from `direction` (a vector from the model toward the camera) and render to `path`."""
    bpy.context.view_layer.update()
    mn, mx = bounds(objs)
    ctr = (mn + mx) / 2
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    scn.camera = cam
    cam.data.type = "ORTHO"
    d = Vector(direction).normalized()
    cam.location = ctr + d * 10
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()  # matrix_world is stale until then
    # the model's extent as the camera sees it: its width and height across the view
    inv = cam.matrix_world.inverted()
    xs, ys = [], []
    for o in objs:
        for c in o.bound_box:
            p = inv @ (o.matrix_world @ Vector(c))
            xs.append(p.x)
            ys.append(p.y)
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    pad = max(w, h) * margin
    w, h = w + 2 * pad, h + 2 * pad
    # the longer side is `size` pixels, the other follows; ortho_scale is the longer side in metres, and the
    # shift (a fraction of it) puts the model's middle in the frame's middle
    longer = max(w, h)
    cam.data.ortho_scale = longer
    cam.data.shift_x = ((max(xs) + min(xs)) / 2) / longer
    cam.data.shift_y = ((max(ys) + min(ys)) / 2) / longer
    scn.render.resolution_x = max(64, int(round(size * w / longer)))
    scn.render.resolution_y = max(64, int(round(size * h / longer)))
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("CUTOUT", path, scn.render.resolution_x, "x", scn.render.resolution_y)
    bpy.data.objects.remove(cam)


def tardis():
    scn = fresh()
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "models", "tardis", "default.glb"))
    objs = [o for o in scn.objects if o not in before and o.type == "MESH"]
    door = next(o for o in objs if o.name.startswith("DoorR"))
    # the white of the windows and the lettering is lit in the game: lit here too
    for m in bpy.data.materials:
        if m.name in ("Material.001", "Material.005") and m.use_nodes:
            b = m.node_tree.nodes.get("Principled BSDF")
            if b:
                b.inputs["Emission Color"].default_value = (1, 1, 1, 1)
                b.inputs["Emission Strength"].default_value = 1.0
    # what is seen through the open door in the game is a white light ("bigger on the inside"): a box of it,
    # the size and place tardis_exteriors.gd gives (glTF x, y, z -> Blender x, -z, y)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.905))
    inside = bpy.context.active_object
    inside.scale = (0.7, 0.7, 1.63)
    mat = bpy.data.materials.new("inside_light")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (1, 1, 1, 1)
    emit.inputs["Strength"].default_value = 3.0
    out_node = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(emit.outputs[0], out_node.inputs["Surface"])
    inside.data.materials.append(mat)
    light(scn, "key", "SUN", 4.0, (50, 0, 35))
    light(scn, "rim", "SUN", 2.0, (65, 0, -140), (0.7, 0.8, 1.0))
    # the front of the model is glTF +Z = Blender -Y; look from front-right, a little above
    front_right = (0.75, -1.0, 0.35)
    door.rotation_mode = "XYZ"
    for state, deg in (("closed", 0.0), ("open", 100.0)):
        inside.hide_render = state == "closed"  # shut, the box is inside the shell anyway: nothing shows
        door.rotation_euler = (0, 0, math.radians(deg))
        shoot(scn, objs, front_right, os.path.join(out_dir, "tardis_%s.png" % state))


def screwdriver(mid):
    scn = fresh()
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "models", "screwdriver", mid + ".glb"))
    new = [o for o in scn.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.rotation_mode = "XYZ"  # the importer leaves quaternions on
            o.rotation_euler = (math.radians(90), 0, math.radians(-25))  # the tip (glTF -Z) goes up
    objs = [o for o in new if o.type == "MESH"]
    if mid in LED:
        for o in objs:
            if o.name.startswith("Led"):
                for m in o.data.materials:
                    m.use_nodes = True
                    b = m.node_tree.nodes.get("Principled BSDF")
                    if b:
                        b.inputs["Base Color"].default_value = (*LED[mid], 1)
                        b.inputs["Emission Color"].default_value = (*LED[mid], 1)
                        b.inputs["Emission Strength"].default_value = 2.5
    light(scn, "key", "SUN", 4.5, (55, 0, 30))
    light(scn, "rim", "SUN", 2.5, (70, 0, -150), (0.8, 0.85, 1.0))
    shoot(scn, objs, (0.35, -1.0, 0.25), os.path.join(out_dir, "screwdriver_%s.png" % mid), margin=0.08)


want_tardis = not only or "tardis" in only
want_sd = [m for m in SCREWDRIVERS if not only or "screwdrivers" in only or m in only]
if want_tardis:
    tardis()
for m in want_sd:
    screwdriver(m)
