"""Render the TARDIS GLB from the front three-quarter, the door shut and swung open, to check it.

    blender -b -P tools/render_tardis.py -- models/tardis/default.glb OUT_PREFIX [OPEN_DEGREES]
"""
import sys
import math
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, prefix = argv[0], argv[1]
deg = float(argv[2]) if len(argv) > 2 else 100.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scn = bpy.context.scene
door = next(o for o in scn.objects if o.name.startswith("DoorR"))
scn.render.engine = "BLENDER_WORKBENCH"
scn.display.shading.light = "STUDIO"
scn.display.shading.color_type = "TEXTURE"
scn.render.resolution_x, scn.render.resolution_y = 900, 900
scn.world = bpy.data.worlds.new("w")
scn.world.color = (0.5, 0.5, 0.55)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("c"))
scn.collection.objects.link(cam)
scn.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = 3.0
cam.location = (-2.5, -3.5, 1.2)
cam.rotation_euler = (Vector((0.0, 0.0, 1.15)) - cam.location).to_track_quat("-Z", "Y").to_euler()
door.rotation_mode = "XYZ"
for state, angle in (("closed", 0.0), ("open", deg)):
    door.rotation_euler = (0, 0, math.radians(angle))
    scn.render.filepath = "%s_%s.png" % (prefix, state)
    bpy.ops.render.render(write_still=True)
