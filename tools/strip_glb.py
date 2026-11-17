"""Keep only the default scene of a GLB: drop the nodes of every other scene and everything only they use.

    python3 tools/strip_glb.py models/interior/10.glb            # in place
    python3 tools/strip_glb.py in.glb out.glb

Why: the 10th Doctor's room GLB carries a second scene, "Outside Scene" (the exterior, 35 meshes with 4096 px
textures: 20 of the file's 26 MB). Godot builds only the default scene, but GLTFDocument decodes EVERY image of the
file first, so entering the room decoded four 4096 px JPEGs (hundreds of MB of RAM on a Quest) for nothing.
The geometry that is kept is copied byte for byte; only the indices are renumbered.
"""
import json
import struct
import sys


def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jlen])
    blen = struct.unpack("<I", data[20 + jlen:24 + jlen])[0]
    return j, data[28 + jlen:28 + jlen + blen]


def write_glb(path, j, binary):
    j["buffers"] = [{"byteLength": len(binary)}]
    text = json.dumps(j, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(text), b"JSON") + text)
        f.write(struct.pack("<I4s", len(binary), b"BIN\0") + binary)


def strip(j, binary):
    """The glTF (JSON dict, BIN bytes) reduced to the default scene."""
    assert "animations" not in j and "skins" not in j, "this tool knows nothing of animations or skins"
    scene_index = j.get("scene", 0)
    # nodes reachable from the default scene, kept in their order
    keep_nodes = []
    seen = set()

    def walk(i):
        if i in seen:
            return
        seen.add(i)
        keep_nodes.append(i)
        for c in j["nodes"][i].get("children", []):
            walk(c)

    for r in j["scenes"][scene_index]["nodes"]:
        walk(r)
    keep_nodes.sort()
    node_map = {old: new for new, old in enumerate(keep_nodes)}

    def remap(table_name, used):
        order = sorted(used)
        return order, {old: new for new, old in enumerate(order)}

    mesh_order, mesh_map = remap("meshes", {j["nodes"][n]["mesh"] for n in keep_nodes if "mesh" in j["nodes"][n]})
    mat_used = {p["material"] for m in mesh_order for p in j["meshes"][m]["primitives"] if "material" in p}
    mat_order, mat_map = remap("materials", mat_used)

    def texture_refs(material):
        refs = []
        pb = material.get("pbrMetallicRoughness", {})
        for holder in (pb.get("baseColorTexture"), pb.get("metallicRoughnessTexture"), material.get("normalTexture"),
                       material.get("occlusionTexture"), material.get("emissiveTexture")):
            if holder is not None:
                refs.append(holder)
        for ext in material.get("extensions", {}).values():
            if isinstance(ext, dict):
                for v in ext.values():
                    if isinstance(v, dict) and "index" in v:
                        refs.append(v)
        return refs

    tex_used = {r["index"] for m in mat_order for r in texture_refs(j["materials"][m])}
    tex_order, tex_map = remap("textures", tex_used)
    img_order, img_map = remap("images", {j["textures"][t]["source"] for t in tex_order})

    acc_used = set()
    for m in mesh_order:
        for p in j["meshes"][m]["primitives"]:
            acc_used.update(p["attributes"].values())
            if "indices" in p:
                acc_used.add(p["indices"])
            for t in p.get("targets", []):
                acc_used.update(t.values())
    acc_order, acc_map = remap("accessors", acc_used)
    bv_used = {j["accessors"][a]["bufferView"] for a in acc_order if "bufferView" in j["accessors"][a]}
    bv_used.update(j["images"][i]["bufferView"] for i in img_order)
    bv_order, bv_map = remap("bufferViews", bv_used)

    # the new binary: the kept buffer views, each aligned to 4 bytes
    out = bytearray()
    new_views = []
    for old in bv_order:
        v = dict(j["bufferViews"][old])
        out += b"\0" * (-len(out) % 4)
        start = v.get("byteOffset", 0)
        v["byteOffset"] = len(out)
        out += binary[start:start + v["byteLength"]]
        new_views.append(v)

    new = {k: v for k, v in j.items() if k not in ("nodes", "scenes", "meshes", "materials", "textures", "images", "accessors", "bufferViews", "scene")}
    new["scene"] = 0
    new["scenes"] = [{k: ([node_map[r] for r in v] if k == "nodes" else v) for k, v in j["scenes"][scene_index].items()}]
    new["nodes"] = []
    for n in keep_nodes:
        node = dict(j["nodes"][n])
        if "mesh" in node:
            node["mesh"] = mesh_map[node["mesh"]]
        if "children" in node:
            node["children"] = [node_map[c] for c in node["children"]]
        new["nodes"].append(node)
    new["meshes"] = []
    for m in mesh_order:
        mesh = json.loads(json.dumps(j["meshes"][m]))
        for p in mesh["primitives"]:
            p["attributes"] = {k: acc_map[a] for k, a in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
            if "material" in p:
                p["material"] = mat_map[p["material"]]
        new["meshes"].append(mesh)
    new["materials"] = []
    for m in mat_order:
        mat = json.loads(json.dumps(j["materials"][m]))
        for ref in texture_refs(mat):
            ref["index"] = tex_map[ref["index"]]
        new["materials"].append(mat)
    new["textures"] = [dict(j["textures"][t], source=img_map[j["textures"][t]["source"]]) for t in tex_order]
    new["images"] = [dict(j["images"][i], bufferView=bv_map[j["images"][i]["bufferView"]]) for i in img_order]
    new["accessors"] = []
    for a in acc_order:
        acc = dict(j["accessors"][a])
        if "bufferView" in acc:
            acc["bufferView"] = bv_map[acc["bufferView"]]
        new["accessors"].append(acc)
    new["bufferViews"] = new_views
    return new, bytes(out)


def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    j, binary = read_glb(src)
    if len(j["scenes"]) < 2:
        print("%s: one scene, nothing to strip" % src)
        return
    before = (len(j["nodes"]), len(j["meshes"]), len(j.get("images", [])), len(binary))
    new, out = strip(j, binary)
    write_glb(dst, new, out)
    print("%s: nodes %d -> %d, meshes %d -> %d, images %d -> %d, binary %.1f -> %.1f MB" % (
        dst, before[0], len(new["nodes"]), before[1], len(new["meshes"]), before[2], len(new.get("images", [])), before[3] / 1048576.0, len(out) / 1048576.0))


if __name__ == "__main__":
    main()
