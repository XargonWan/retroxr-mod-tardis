"""Render every screwdriver GLB side by side, tip up, to check them by eye.

    blender -b -P tools/render_lineup.py -- OUT.png ID [ID ...]
"""
import sys
import os
import math
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out, ids = argv[0], argv[1:]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
for i, mid in enumerate(ids):
    before = set(scn.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(root, "models", "screwdriver", mid + ".glb"))
    new = [o for o in scn.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.rotation_mode = "XYZ"  # the importer leaves quaternions on
            o.rotation_euler = (math.radians(90), 0, 0)  # the tip (glTF -Z = Blender +Y) goes up
            o.location = (i * 0.05, 0, 0)
    print("LINEUP", mid, [(o.name) for o in new if o.type == "MESH"])
scn.render.engine = "BLENDER_WORKBENCH"
scn.display.shading.light = "STUDIO"
scn.display.shading.color_type = "TEXTURE"
scn.render.resolution_x, scn.render.resolution_y = 1600, 560
scn.world = bpy.data.worlds.new("w")
scn.world.color = (0.3, 0.3, 0.36)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("c"))
scn.collection.objects.link(cam)
scn.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = max(0.2, len(ids) * 0.05 + 0.02)
cam.location = ((len(ids) - 1) * 0.025, -1.0, 0.02)
cam.rotation_euler = (math.radians(90), 0, 0)
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
