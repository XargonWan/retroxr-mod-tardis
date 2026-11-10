"""Convert a TARDIS interior (a Blender scene made for rendering) into the mod's console room GLB.

    blender -b -P tools/convert_interior.py -- --src <file.blend> --out models/interior/10.glb \\
        --meta models/interior/10.json [--budget-scale 1.0] [--tex-size 512]

Normally through tools/build_interiors.py. The 10th Doctor's source is 390 MB, 568 meshes, 4.1 million
triangles once its geometry nodes are evaluated, 116 node-built materials, 4096 px textures and 103
lights: made to be rendered, not walked in on a Quest 3. This brings it to about 150 000 triangles:

  * the objects of the collections listed in COLLECTIONS are realised (modifiers and geometry nodes
    applied; the rest, the cameras, the lights, the "rendering crap" shell, is dropped), and anything
    smaller than MIN_SIZE metres is thrown away,
  * each collection has a triangle budget (BUDGETS); inside it the objects share it by the square root
    of their size, so a small part is not wiped out by a big one, and are decimated to it,
  * each material is replaced by a plain one: the base-colour image where it has one (shrunk to
    --tex-size), else a colour taken from its nodes; glass and emission kept as they were meant;
    materials that came out alike are one,
  * everything static is joined and split again by material (about 40 draw calls instead of 568),
  * the time rotor and the door are kept as objects of their own ("Rotor1", "Rotor2", "Door"),
  * the whole is moved so that its origin is on the floor under the console; Blender's -Y (where the
    door is) is glTF's +Z; and what the mod needs to know is written to --meta: where the console,
    the door and the rotor are, the floor height, the radius of the room.
The source is untrusted data: it is only opened, never run.
"""
import argparse
import colorsys
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ap = argparse.ArgumentParser()
ap.add_argument("--src", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--meta", required=True)
ap.add_argument("--collision", required=True, help="GLB of the things to bump into (pillars, console, railings)")
ap.add_argument("--collision-budget", type=int, default=6000)
ap.add_argument("--budget-scale", type=float, default=1.0)
ap.add_argument("--tex-size", type=int, default=512)
opt = ap.parse_args(argv)

SCENE = "Inside Scene"
# collection -> triangle budget (before --budget-scale)
BUDGETS = {
    "Interior Details": 55000,
    "Hidable Wall": 15000,
    "Console Frame": 20000,
    "Console Details": 25000,
    "Floor Details": 15000,
    "Animated Stuff": 6000,
    "Harry's Door (hide for ext composits)": 8000,
}
MIN_SIZE = 0.05  # metres: smaller parts are not worth a draw of their own
# the console is all knobs and wires: nothing under this is seen from where a player stands
MIN_SIZE_BY_COLLECTION = {"Console Details": 0.12}
ROTOR_PREFIX = "New time rotor"
DOOR_NAME = "Main Door"
# a glass or a see-through material this clear stays see-through; the walls' lens glass does not
KEEP_OPAQUE = {"Roundel Glass", "Coral Roundel"}
NOT_COLOUR = ("bump", "norm", "nor_", "spec", "disp", "rough", "metal", "gloss", "height", "alphamesh", ".mp4", "vortex")

bpy.ops.wm.open_mainfile(filepath=opt.src)
scene = bpy.data.scenes[SCENE]
bpy.context.window.scene = scene
dg = bpy.context.evaluated_depsgraph_get()
work = bpy.data.collections.new("work")
scene.collection.children.link(work)


def log(*a):
    print("INT", *a, flush=True)


# ── realise ───────────────────────────────────────────────────────────────────
groups = {}  # collection name -> [new objects]
skipped_small = skipped_hidden = 0
for cname in BUDGETS:
    col = bpy.data.collections[cname]
    for o in col.all_objects:
        if o.type != "MESH":
            continue
        if o.hide_render:
            skipped_hidden += 1
            continue
        # the door's collection also holds the exterior light and frame; only the door is wanted
        if cname.startswith("Harry") and not o.name.startswith(DOOR_NAME):
            skipped_hidden += 1
            continue
        # Geometry nodes that only add detail to a mesh (the coral pillars: a 7 600 triangle shape
        # turned into hundreds of thousands) would, decimated back, come out as shards; the shape
        # they started from is the one wanted. Where the nodes make the whole mesh (no polygons
        # under them) the evaluated one is all there is.
        if any(m.type == "NODES" for m in o.modifiers) and len(o.data.polygons) > 0:
            me = o.data.copy()
        else:
            ev = o.evaluated_get(dg)
            tmp = ev.to_mesh()
            me = tmp.copy()
            ev.to_mesh_clear()
        if len(me.polygons) == 0:
            bpy.data.meshes.remove(me)
            continue
        new = bpy.data.objects.new(o.name, me)
        new.matrix_world = o.matrix_world.copy()
        work.objects.link(new)
        size = max(new.dimensions)
        if size < MIN_SIZE_BY_COLLECTION.get(cname, MIN_SIZE):
            skipped_small += 1
            bpy.data.objects.remove(new, do_unlink=True)
            continue
        groups.setdefault(cname, []).append(new)
log("realised", {k: len(v) for k, v in groups.items()}, "small dropped", skipped_small, "hidden", skipped_hidden)


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


# ── decimate to each collection's budget ─────────────────────────────────────
for cname, objs in groups.items():
    budget = BUDGETS[cname] * opt.budget_scale
    sizes = {o: tris(o) for o in objs}
    total = sum(sizes.values())
    weights = {o: math.sqrt(sizes[o]) * (3.0 if any(w in o.name.lower() for w in ("pillar", "coral", "console")) else 1.0)
               for o in objs}
    wsum = sum(weights.values())
    log(cname, "tris", total, "budget", int(budget))
    for o in objs:
        share = budget * weights[o] / wsum
        if sizes[o] <= max(share, 12):
            continue
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = max(0.002, share / sizes[o])
        m.use_collapse_triangulate = True
        select_only([o])
        bpy.ops.object.modifier_apply(modifier=m.name)
    # the first pass leaves a collection over its budget where its topology (loose parts, seams) resists:
    # more passes, each asking for what is still owed
    for _ in range(3):
        have = sum(tris(o) for o in objs)
        if have <= budget * 1.1:
            break
        ratio = budget / have
        for o in objs:
            if tris(o) <= 24:
                continue
            m = o.modifiers.new("dec", "DECIMATE")
            m.ratio = max(0.01, ratio)
            m.use_collapse_triangulate = True
            select_only([o])
            bpy.ops.object.modifier_apply(modifier=m.name)
    log(cname, "after", sum(tris(o) for o in objs))

# ── materials: replaced by plain ones ─────────────────────────────────────────
images_kept = {}


def mid_of_ramp(node):
    try:
        c = node.color_ramp.evaluate(0.5)
        return (c[0], c[1], c[2], 1.0)
    except Exception:
        return None


def colour_image(mat):
    """The base-colour image of a node material, or None."""
    if not mat.use_nodes:
        return None
    best = None
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.source != "MOVIE" and max(n.image.size) > 0:
            name = n.image.name.lower()
            if any(w in name for w in NOT_COLOUR):
                continue
            # prefer the one plugged into Base Color
            if best is None or any(l.to_socket.name == "Base Color" for o_ in n.outputs for l in o_.links):
                best = n.image
    return best


def summarise(mat):
    out = {"color": (0.55, 0.55, 0.55, 1.0), "image": None, "metallic": 0.0, "roughness": 0.6,
           "emission": None, "alpha": 1.0}
    dc = tuple(mat.diffuse_color)
    out["color"] = dc
    if not mat.use_nodes:
        return out
    nodes = mat.node_tree.nodes
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    out["image"] = colour_image(mat)
    if bsdf is not None:
        bc = bsdf.inputs["Base Color"]
        if bc.is_linked:
            src = bc.links[0].from_node
            ramp = src if src.type == "VALTORGB" else None
            c = mid_of_ramp(ramp) if ramp else None
            out["color"] = c or (0.55, 0.55, 0.55, 1.0) if src.type != "TEX_IMAGE" else (1, 1, 1, 1)
        else:
            out["color"] = tuple(bc.default_value)
        out["metallic"] = float(bsdf.inputs["Metallic"].default_value)
        out["roughness"] = float(bsdf.inputs["Roughness"].default_value)
        out["alpha"] = float(bsdf.inputs["Alpha"].default_value)
        es = float(bsdf.inputs["Emission Strength"].default_value) if "Emission Strength" in bsdf.inputs else 0.0
        if es > 0.05:
            ec = tuple(bsdf.inputs["Emission Color"].default_value)
            if max(ec[:3]) > 0.05:
                out["emission"] = (ec[:3], min(es, 4.0))
    else:
        for n in nodes:
            if n.type == "EMISSION":
                c = tuple(n.inputs["Color"].default_value)
                out["emission"] = (c[:3], min(float(n.inputs["Strength"].default_value), 4.0))
                out["color"] = c
            elif n.type in ("BSDF_DIFFUSE", "BSDF_GLOSSY", "BSDF_TRANSLUCENT") and "Color" in n.inputs:
                out["color"] = tuple(n.inputs["Color"].default_value)
            elif n.type == "RGB":
                out["color"] = tuple(n.outputs[0].default_value)
            elif n.type == "VALTORGB" and out["color"] == tuple(mat.diffuse_color):
                out["color"] = mid_of_ramp(n) or out["color"]
        types = {n.type for n in nodes}
        if "BSDF_GLASS" in types or "BSDF_TRANSPARENT" in types:
            out["alpha"] = 0.3
    low = mat.name.lower()
    if mat.name in KEEP_OPAQUE:
        out["alpha"] = 1.0
    elif "glass" in low and out["alpha"] > 0.5:
        out["alpha"] = 0.35
    return out


def key_of(s):
    q = lambda v, n: round(v * n) / n
    c = s["color"]
    return (s["image"].name if s["image"] else None,
            None if s["image"] else (q(c[0], 8), q(c[1], 8), q(c[2], 8)),
            q(s["metallic"], 3), q(s["roughness"], 3),
            None if not s["emission"] else (tuple(q(v, 4) for v in s["emission"][0]), q(s["emission"][1], 2)),
            q(s["alpha"], 3))


canon = {}      # key -> new material
mapping = {}    # old material name -> new material
for objs in groups.values():
    for o in objs:
        for old in {ms.material for ms in o.material_slots if ms.material}:
            if old.name in mapping:
                continue
            s = summarise(old)
            k = key_of(s)
            if k not in canon:
                m = bpy.data.materials.new("M%d" % len(canon))
                m.use_nodes = True
                b = m.node_tree.nodes["Principled BSDF"]
                b.inputs["Metallic"].default_value = min(s["metallic"], 0.6)
                b.inputs["Roughness"].default_value = max(s["roughness"], 0.35)
                if s["image"] is not None:
                    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
                    tex.image = s["image"]
                    m.node_tree.links.new(tex.outputs["Color"], b.inputs["Base Color"])
                    images_kept[s["image"].name] = s["image"]
                else:
                    c = s["color"]
                    b.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1.0)
                if s["emission"]:
                    e, strength = s["emission"]
                    b.inputs["Emission Color"].default_value = (e[0], e[1], e[2], 1.0)
                    b.inputs["Emission Strength"].default_value = strength
                if s["alpha"] < 0.99:
                    b.inputs["Alpha"].default_value = s["alpha"]
                    m.blend_method = "BLEND"
                canon[k] = m
            mapping[old.name] = canon[k]
log("materials", len(mapping), "->", len(canon), "images kept", [(n, tuple(i.size)) for n, i in images_kept.items()])
for objs in groups.values():
    for o in objs:
        for ms in o.material_slots:
            if ms.material:
                ms.material = mapping[ms.material.name]
        if not o.material_slots:
            o.data.materials.append(next(iter(canon.values())))

# ── the floor, the centre, the room ───────────────────────────────────────────
# the console's middle, and the floor: the biggest upward plane of the floor and the details
console = groups["Console Frame"]
cx = sum((o.matrix_world @ Vector(c)).x for o in console for c in o.bound_box) / (8 * len(console))
cy = sum((o.matrix_world @ Vector(c)).y for o in console for c in o.bound_box) / (8 * len(console))
# The floor is where a player standing in the room's ring would stand: rays dropped from just above
# head-height-of-a-child... no: from the middle of the room's height, down, at points on rings round
# the console, and the median of what they hit (the model has a raised platform and a lower floor; the
# biggest flat area is not the same thing as the one the door opens onto).
hits = []
for ring in (4.0, 6.0, 8.0):
    for k in range(24):
        a = math.tau * k / 24
        origin = Vector((cx + math.cos(a) * ring, cy + math.sin(a) * ring, 0.3))
        ok, loc, nrm, idx, obj, mat = scene.ray_cast(dg, origin, Vector((0, 0, -1)), distance=4.0)
        if ok and nrm.z > 0.9:
            hits.append(round(loc.z, 2))
hits.sort()
log("floor ray hits", len(hits), "of 72; z histogram", sorted({(z, hits.count(z)) for z in hits}, key=lambda t: -t[1])[:6])
floor_z = hits[len(hits) // 2] if hits else -1.2
log("floor z", floor_z, "centre", round(cx, 2), round(cy, 2))

# ── join the static, keep the rotor and the door ──────────────────────────────
rotors = [o for o in groups.get("Animated Stuff", []) if o.name.startswith(ROTOR_PREFIX)]
door = [o for o in groups.get("Harry's Door (hide for ext composits)", []) if o.name.startswith(DOOR_NAME)]
special = set(rotors) | set(door)
static = [o for objs in groups.values() for o in objs if o not in special]
for o in static + list(special):
    work.objects.link(o) if o.name not in work.objects else None
# the whole moves so that the floor under the console is the origin
log("shifting")
shift = Matrix.Translation(Vector((-cx, -cy, -floor_z)))
for o in static + list(special):
    o.matrix_world = shift @ o.matrix_world
bpy.context.view_layer.update()
for o in static + list(special):
    select_only([o])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

meta = {"floor_z_blender": floor_z, "centre_blender": [cx, cy]}


def bbox(o):
    ws = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return Vector((min(w.x for w in ws), min(w.y for w in ws), min(w.z for w in ws))), \
        Vector((max(w.x for w in ws), max(w.y for w in ws), max(w.z for w in ws)))


def godot(v):  # Blender (x, y, z) -> glTF/Godot (x, z, -y)
    return [round(v.x, 3), round(v.z, 3), round(-v.y, 3)]


if door:
    d = door[0]
    mn, mx = bbox(d)
    meta["door"] = {"centre": godot((mn + mx) / 2), "size": [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)]}
    d.name = "Door"
for i, r in enumerate(rotors):
    mn, mx = bbox(r)
    meta.setdefault("rotors", []).append({"name": "Rotor%d" % (i + 1), "centre": godot((mn + mx) / 2),
                                          "size": [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)]})
    r.name = "Rotor%d" % (i + 1)
    select_only([r])
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")

# ── collision proxy: the things in the walking volume that are not floor or wall ──────────────
col_of = {o: cname for cname, objs in groups.items() for o in objs}
solid = []
for o in static:
    mn, mx = bbox(o)
    cname = col_of.get(o, "")
    standing = mn.z < 0.6 and mx.z > 0.5 and max(mx.x - mn.x, mx.y - mn.y) < 11.0 and cname != "Floor Details"
    if cname == "Console Frame" or standing:
        solid.append(o)
# One CONVEX HULL per compact thing (a pillar, the console's legs and ring): a few hundred triangles each
# and the cheapest shape a physics engine has. The long thin things (the railings, whose hull would fill
# the room they curve round) are left out; decimating them to a mesh did not work in Blender here.
import bmesh
proxies = []
for o in solid:
    mn, mx = bbox(o)
    if max(mx.x - mn.x, mx.y - mn.y) > 4.5:
        continue
    me = o.data.copy()
    bm = bmesh.new()
    bm.from_mesh(me)
    hull = bmesh.ops.convex_hull(bm, input=bm.verts, use_existing_faces=False)
    dead = {g for g in hull["geom_interior"] + hull["geom_unused"] if isinstance(g, bmesh.types.BMVert)}
    bmesh.ops.delete(bm, geom=list(dead), context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(8), verts=bm.verts, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    c = bpy.data.objects.new("Col%d" % len(proxies), me)
    c.matrix_world = o.matrix_world.copy()
    work.objects.link(c)
    proxies.append(c)
if proxies:
    meta["collision_triangles"] = sum(tris(c) for c in proxies)
    meta["collision_objects"] = len(proxies)
    select_only(proxies)
    bpy.ops.export_scene.gltf(filepath=opt.collision, export_format="GLB", export_yup=True, use_selection=True,
                              export_materials="NONE", export_image_format="NONE")
    log("collision hulls", meta["collision_triangles"], "tris,", len(proxies), "of", len(solid), "objects")
    for c in proxies:
        bpy.data.objects.remove(c, do_unlink=True)

# the room's radius: how far the walls reach at standing height, from the centre
radii = []
for o in static:
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        if 0.8 < w.z < 1.6:
            radii.append(math.hypot(w.x, w.y))
radii.sort()
meta["wall_radius_p98"] = round(radii[int(len(radii) * 0.98)], 2) if radii else None
meta["wall_radius_max"] = round(radii[-1], 2) if radii else None
allmin = min(bbox(o)[0].z for o in static)
allmax = max(bbox(o)[1].z for o in static)
meta["height_range"] = [round(allmin, 2), round(allmax, 2)]

select_only(static)
bpy.ops.object.join()
log("joined")
joined = bpy.context.view_layer.objects.active
# Split by material with bmesh: the operator (edit-mode separate) crashes Blender 4.2 on this mesh.
import bmesh
mats = list(joined.data.materials)
used = {p.material_index for p in joined.data.polygons}
parts = []
for idx, mat in enumerate(mats):
    if idx not in used:
        continue
    me = joined.data.copy()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != idx], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(mat)
    o = bpy.data.objects.new("Static%d" % len(parts), me)
    work.objects.link(o)
    parts.append(o)
bpy.data.objects.remove(joined, do_unlink=True)
log("separated", len(parts))

# one UV map, no vertex colours: the GLB carries only what the room draws; smooth except at sharp edges.
# After the split: smoothing before it crashed Blender 4.2's separate-by-material.
for o in [o for o in work.objects if o.type == "MESH"]:
    me = o.data
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[-1])
    for attr in [a.name for a in me.color_attributes]:
        me.color_attributes.remove(me.color_attributes[attr])
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(75))
log("smoothed")

# ── textures down ─────────────────────────────────────────────────────────────
for img in images_kept.values():
    if max(img.size) > opt.tex_size:
        img.scale(min(img.size[0], opt.tex_size), min(img.size[1], opt.tex_size))

total = sum(tris(o) for o in work.objects if o.type == "MESH")
meta["triangles"] = total
meta["meshes"] = len([o for o in work.objects if o.type == "MESH"])
log("TRIANGLES", total, "meshes", meta["meshes"], "materials", len(canon))
log("META", json.dumps(meta))
for o in list(scene.objects):
    if o.name not in work.objects:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=opt.out, export_format="GLB", export_yup=True, export_apply=False,
                          export_image_format="JPEG", export_jpeg_quality=80)
with open(opt.meta, "w") as f:
    json.dump(meta, f, indent=1)
log("WROTE", opt.out)
