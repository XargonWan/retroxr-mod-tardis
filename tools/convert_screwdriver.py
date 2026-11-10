"""Convert one sonic screwdriver source (USD/USDZ, FBX, blend) into the mod's GLB.

Run with Blender, not python; normally through tools/build_models.py, which holds each model's
settings. By hand:

    blender -b -P tools/convert_screwdriver.py -- --src <file> --out models/screwdriver/<id>.glb \\
        --length 0.17 --tip +Z [--grip 0.38] [--max-tris 6000] [--tex-size 256] \\
        [--drop REGEX] [--tex-dir DIR] [--tex MATERIAL:FILEPREFIX ...] \\
        [--led-material NAME [--led-above F]] [--led-object REGEX]

What it does to every model, so that they all behave the same in the hand:
  * throws away objects whose name matches --drop (reference planes, a second pose),
  * wires the textures it finds in --tex-dir to a material that has none (by the material's name,
    or the prefix --tex gives it),
  * scales it to --length metres along its long axis,
  * turns it so the business end (--tip, an axis of the SOURCE) points to Godot's -Z, the way a hand
    points, with the origin on the grip (--grip: how far up from the base, 0..1),
  * makes the LED a mesh of its own called "Led", the one thing the mod lights:
      --led-object REGEX   an object of the source is the LED,
      --led-material NAME  the faces with that material become it (all of the object when it has
                           just that material), and with --led-above F only the faces of them
                           above F (0..1 of the length from the base): the 10th Doctor's emitter
                           dome is the end of the same mesh as its core rod, so F = 0.955,
  * joins what shares a material (a source of 38 parts would be 38 draw calls) and decimates
    anything above --max-tris (a Quest 3 draws this with a whole room; the LED is left alone),
  * shrinks every texture above --tex-size px (the mod loads the GLB at run time, where nothing is
    GPU-compressed for it: a 1024 px map costs 5 MB of video memory on a 17 cm toy),
  * exports a GLB (Y up, textures embedded), printing the triangle count, bounds and each
    material's textures.
The source is untrusted data: it is only imported, never executed.
"""
import argparse
import os
import re
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--src", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--length", type=float, default=0.17)
ap.add_argument("--tip", default="+Z")
ap.add_argument("--grip", type=float, default=0.38)
ap.add_argument("--max-tris", type=int, default=6000)
ap.add_argument("--tex-size", type=int, default=256)
ap.add_argument("--drop", default="")
ap.add_argument("--tex-dir", default="")
ap.add_argument("--tex", action="append", default=[])
ap.add_argument("--led-material", default="")
ap.add_argument("--led-above", type=float, default=0.0)
ap.add_argument("--led-object", default="")
opt = ap.parse_args(argv)

bpy.ops.wm.read_factory_settings(use_empty=True)
ext = opt.src.lower().rsplit(".", 1)[-1]
if ext in ("usd", "usdc", "usda", "usdz"):
    bpy.ops.wm.usd_import(filepath=opt.src)
elif ext == "fbx":
    bpy.ops.import_scene.fbx(filepath=opt.src)
elif ext == "blend":
    bpy.ops.wm.open_mainfile(filepath=opt.src)
else:
    raise SystemExit("unsupported source: " + opt.src)
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


def tris_of(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


# ── clean up the source ───────────────────────────────────────────────────────
if opt.drop:
    rx = re.compile(opt.drop)
    for o in [o for o in scene.objects if rx.fullmatch(o.name)]:
        bpy.data.objects.remove(o, do_unlink=True)
for o in meshes():  # flatten the hierarchy: only the meshes matter
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
objs = meshes()
if not objs:
    raise SystemExit("nothing left to convert")
# A source that smooths itself with a modifier (the 4th Doctor's: Subdivision Surface level 3, 874k
# polygons) must not export every level: one level is applied, then the budget below decimates.
for o in objs:
    for m in o.modifiers:
        if m.type == "SUBSURF":
            m.levels = min(m.levels, 1)
            m.render_levels = min(m.render_levels, 1)
if any(o.modifiers for o in objs):
    select_only([o for o in objs if o.modifiers])
    bpy.ops.object.convert(target="MESH")
    objs = meshes()


# ── textures ──────────────────────────────────────────────────────────────────
KINDS = (("base", ("base_color", "basecolor", "albedo", "diffuse", "_color")),
         ("normal", ("normal",)), ("rough", ("roughness",)), ("metal", ("metallic", "metalness")),
         ("emit", ("emissive", "emission")), ("alpha", ("opacity", "alpha")))


def wire_textures():
    if not opt.tex_dir:
        return
    files = []
    for dirpath, _d, names in os.walk(opt.tex_dir):
        files += [os.path.join(dirpath, n) for n in names if n.lower().endswith((".png", ".jpg", ".jpeg"))]
    overrides = dict(t.split(":", 1) for t in opt.tex)
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf is None or bsdf.inputs["Base Color"].is_linked:
            continue
        prefix = overrides.get(m.name, m.name).lower()
        found = {}
        for f in files:
            base = os.path.basename(f).lower()
            if not base.startswith(prefix):
                continue
            rest = base[len(prefix):]
            # "screwdriver" must not claim "screwdriver_tip_...": the rest is only a map's name
            for kind, words in KINDS:
                if any(w in rest for w in words) and kind not in found and "mixed_ao" not in rest:
                    found[kind] = f
        nodes, links = m.node_tree.nodes, m.node_tree.links

        def tex(path, colorspace):
            n = nodes.new("ShaderNodeTexImage")
            n.image = bpy.data.images.load(path)
            n.image.colorspace_settings.name = colorspace
            return n
        if "base" in found:
            links.new(tex(found["base"], "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
        if "normal" in found:
            nm = nodes.new("ShaderNodeNormalMap")
            links.new(tex(found["normal"], "Non-Color").outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        if "rough" in found:
            links.new(tex(found["rough"], "Non-Color").outputs["Color"], bsdf.inputs["Roughness"])
        if "metal" in found:
            links.new(tex(found["metal"], "Non-Color").outputs["Color"], bsdf.inputs["Metallic"])
        if "emit" in found:
            links.new(tex(found["emit"], "sRGB").outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 1.0
        if "alpha" in found:
            links.new(tex(found["alpha"], "Non-Color").outputs["Color"], bsdf.inputs["Alpha"])
            m.blend_method = "BLEND"
        print("TEXTURES", m.name, sorted(found))


wire_textures()
for _m in bpy.data.materials:  # what each material ended up with: to pick --led-material by eye
    if _m.use_nodes:
        print("MATERIAL", _m.name, sorted({os.path.basename(n.image.filepath) or n.image.name for n in _m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}))

# ── orient: the source's tip axis -> +Z ───────────────────────────────────────
axis = {"+X": Vector((1, 0, 0)), "-X": Vector((-1, 0, 0)), "+Y": Vector((0, 1, 0)),
        "-Y": Vector((0, -1, 0)), "+Z": Vector((0, 0, 1)), "-Z": Vector((0, 0, -1))}[opt.tip]
q = axis.rotation_difference(Vector((0, 0, 1)))
for o in objs:
    o.matrix_world = q.to_matrix().to_4x4() @ o.matrix_world
bpy.context.view_layer.update()

# ── the LED, split off while the tip is still +Z ──────────────────────────────
led = None
if opt.led_object:
    rx = re.compile(opt.led_object)
    hit = [o for o in objs if rx.fullmatch(o.name)]
    if hit:
        select_only(hit)
        if len(hit) > 1:
            bpy.ops.object.join()
        led = bpy.context.view_layer.objects.active
elif opt.led_material:
    host = next((o for o in objs if opt.led_material in [m.name for m in o.data.materials if m]), None)
    if host is None:
        raise SystemExit("no object has the material " + opt.led_material)
    mats = [m.name if m else "" for m in host.data.materials]
    idx = mats.index(opt.led_material)
    zs = [(o.matrix_world @ Vector(c)).z for o in objs for c in o.bound_box]
    zcut = min(zs) + (max(zs) - min(zs)) * opt.led_above
    select_only([host])
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(host.data)
    for f in bm.faces:
        f.select_set(f.material_index == idx and all((host.matrix_world @ v.co).z > zcut for v in f.verts))
    bmesh.update_edit_mesh(host.data)
    n_sel = sum(1 for f in bm.faces if f.select)
    n_all = len(bm.faces)
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    now = meshes()
    if n_sel == n_all:
        led = host  # the whole object was selected: nothing was split off
    else:
        led = next(o for o in now if o not in objs)
    print("LED faces", n_sel, "of", n_all)
objs = meshes()

# ── scale, grip ───────────────────────────────────────────────────────────────
mn, mx = bounds(objs)
k = opt.length / (mx.z - mn.z)
grip_z = mn.z + (mx.z - mn.z) * opt.grip
cx, cy = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2
for o in objs:
    o.matrix_world = Matrix.Scale(k, 4) @ Matrix.Translation(Vector((-cx, -cy, -grip_z))) @ o.matrix_world
bpy.context.view_layer.update()
for o in objs:  # bake the scale into the vertices: the GLB carries unit scale
    select_only([o])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# Blender +Z (tip) -> glTF +Y; lay it down so that the tip is glTF's -Z, where a hand points
for o in objs:
    o.matrix_world = Matrix.Rotation(-1.5707963267948966, 4, "X") @ o.matrix_world
    select_only([o])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ── join by material, then decimate ───────────────────────────────────────────
groups = {}
for o in meshes():
    if o == led:
        continue
    key = tuple(m.name if m else "" for m in o.data.materials)
    groups.setdefault(key, []).append(o)
for key, group in groups.items():
    if len(group) > 1:
        select_only(group)
        bpy.ops.object.join()
body = [o for o in meshes() if o != led]
total = sum(tris_of(o) for o in meshes())
print("TRIS before", total)
if total > opt.max_tris:
    keep = tris_of(led) if led else 0
    ratio = max(0.02, (opt.max_tris - keep) / max(1, total - keep))
    for o in body:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = ratio
        select_only([o])
        bpy.ops.object.modifier_apply(modifier=m.name)
print("TRIS after", sum(tris_of(o) for o in meshes()))

# ── textures down, names, export ──────────────────────────────────────────────
for img in bpy.data.images:
    if img.size[0] > opt.tex_size or img.size[1] > opt.tex_size:
        img.scale(min(img.size[0], opt.tex_size), min(img.size[1], opt.tex_size))
n = 0
for o in meshes():
    if o == led:
        o.name = "Led"
    else:
        n += 1
        o.name = "Body%d" % n
    o.data.name = o.name
mn, mx = bounds(meshes())
print("OBJECTS", [(o.name, [m.name for m in o.data.materials if m]) for o in meshes()])
print("BOUNDS", tuple(round(v, 4) for v in mn), tuple(round(v, 4) for v in mx))
bpy.ops.export_scene.gltf(filepath=opt.out, export_format="GLB", export_yup=True, export_apply=True,
                          export_image_format="JPEG", export_jpeg_quality=85)
print("WROTE", opt.out)
