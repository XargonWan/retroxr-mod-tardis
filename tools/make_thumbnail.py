"""Render thumbnail.png (1280x720, the mod's tile and its mod.io logo) from a screwdriver GLB.

    blender -b -P tools/make_thumbnail.py -- models/screwdriver/10.glb thumbnail.png
"""
import sys
import math
import bpy
from mathutils import Vector

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scn = bpy.context.scene
meshes = [o for o in scn.objects if o.type == "MESH"]
mn = Vector((1e9,) * 3)
mx = Vector((-1e9,) * 3)
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        mn = Vector(map(min, mn, w))
        mx = Vector(map(max, mx, w))
ctr = (mn + mx) / 2
size = (mx - mn).length
# the dome (the LED) glows in the picture, as it does in the room
for o in meshes:
    if o.name.startswith("Led"):
        for m in o.data.materials:
            m.use_nodes = True
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Emission Color"].default_value = (0.25, 0.5, 1.0, 1)
                bsdf.inputs["Emission Strength"].default_value = 6.0
                bsdf.inputs["Base Color"].default_value = (0.25, 0.5, 1.0, 1)
scn.render.engine = "BLENDER_EEVEE_NEXT"
scn.render.resolution_x, scn.render.resolution_y = 1280, 720
scn.world = bpy.data.worlds.new("w")
scn.world.use_nodes = True
bg = scn.world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.02, 0.05, 0.14, 1)
bg.inputs[1].default_value = 0.25
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scn.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scn.collection.objects.link(cam)
scn.camera = cam
cam.data.lens = 70
# the screwdriver lies along Y in Blender: lay the shot diagonally across the frame
cam.location = ctr + Vector((size * 0.75, -size * 1.0, size * 0.25))
cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
for o in meshes:
    o.rotation_euler = (0, 0, math.radians(-28))
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
