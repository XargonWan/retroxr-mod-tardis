## Reading the mod's own model and sound files at run time, shared by the screwdriver and the TARDIS.
##
## Why not `load()`: a pack made by tools/pack.py carries source files only, and a `.glb` or `.mp3`
## is "imported" into a resource only by the editor. In the checkout `load()` would work and in the
## pack it would not, so the files are read as bytes (GLTFDocument, AudioStreamMP3). Each is parsed
## once and cached: a scene built from a GLB is copied on every use.
extends RefCounted

## tardis-door.mp3 opens with 0.6 s of silence (measured: nothing above -60 dB before it): played from the start the door
## seemed to sound late. Both doors play it FROM here (`AudioStreamPlayer3D.play(from_position)`).
const DOOR_SOUND_START := 0.6

static var _models: Dictionary = {}
static var _sounds: Dictionary = {}


## The scene in the GLB at `path`, a copy the caller owns, or null when it cannot be read.
static func instance_glb(path: String) -> Node3D:
	if not _models.has(path):
		_models[path] = _parse_glb(path)
	var template := _models[path] as Node3D
	return template.duplicate() as Node3D if template != null else null


static func _parse_glb(path: String) -> Node3D:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(bytes, "", state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## The MP3 at `path` (null when it cannot be read), looping or not. A loop and a one-shot are two
## streams: the flag is part of the stream.
static func mp3(path: String, loop: bool = false) -> AudioStreamMP3:
	var key := "%s|%s" % [path, loop]
	if not _sounds.has(key):
		var bytes := FileAccess.get_file_as_bytes(path)
		var stream: AudioStreamMP3 = null
		if not bytes.is_empty():
			stream = AudioStreamMP3.new()
			stream.data = bytes
			stream.loop = loop
		_sounds[key] = stream
	return _sounds[key] as AudioStreamMP3


## Make every MeshInstance3D of `model` a direct child of `into` (PickableHighlight only outlines
## what it finds there), each keeping its place relative to the model, then free what is left of
## `model`. Returns the meshes, by name.
static func adopt_meshes(model: Node3D, into: Node3D) -> Dictionary:
	var adopted := {}
	for mesh: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var xf := relative_transform(mi, model)
		mi.get_parent().remove_child(mi)
		into.add_child(mi)
		mi.transform = xf
		adopted[mi.name] = mi
	model.free()
	return adopted


## `node`'s transform in `root`'s frame, for a tree that is not in the scene (no global_transform there).
static func relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
