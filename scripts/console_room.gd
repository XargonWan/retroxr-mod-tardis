## ConsoleRoom -- what a TARDIS console room is made of, built when its scene is loaded.
##
## The scene (console_room_<id>.tscn) is only the room's root (RetroXR's XRInit, with the room id), an
## environment and the player's rig at the door. This node reads the GLB tools/convert_interior.py made
## (mod_assets.gd: at run time, so it works from a pack) and the JSON beside it, and adds:
##   * the model, drawn as it is, every material on both sides (decimating the original leaves holes
##     and flipped faces; a part that is seen from behind is better seen than gone),
##   * colliders that say where the player may stand and what they bump into: a flat floor at 0, a ring
##     of wall, a ceiling, the console, and the pillars, console and railings as a low-poly mesh the
##     converter made for it (`collision` in the table), all on physics layer 1 where RetroXR looks,
##   * a few lights (no shadows) and the time rotor going up and down,
##   * the DOOR: a VRButton over it (trigger in VR, click on a desktop) that takes the player back out
##     (TardisTravel.leave),
##   * the CONSOLE: the thing to point at for the TARDIS's menu (ConsoleMenu).
## It is IDLE of any saved state: what the player puts in the room is RetroXR's to save and restore, as
## in any room with slots.
extends Node3D

const Assets := preload("res://mods/xenu.tardis/scripts/mod_assets.gd")
const ConsoleRooms := preload("res://mods/xenu.tardis/scripts/console_rooms.gd")
const Travel := preload("res://mods/xenu.tardis/scripts/tardis_travel.gd")
const ConsoleMenu := preload("res://mods/xenu.tardis/scripts/console_menu.gd")
const DOOR_SOUND := "res://mods/xenu.tardis/assets/audio/tardis-door.mp3"

@export var console_id := ConsoleRooms.DEFAULT_ID

## How long after the door is pressed the player is let out (the door sound has begun).
const LEAVE_DELAY := 0.8
## How far the rotor rises and falls (fractions of its height) and how fast (radians a second).
const ROTOR_TRAVEL := 0.18
const ROTOR_SPEED := 0.9
const WALL_SEGMENTS := 36
## The model's own sizes (its metres): the console's footprint and height.
## The model is drawn at the table's `scale` of its size, and everything built here (floor, walls, collision,
## lights, door, console) follows. The 10th Doctor's room is 19 m across at 1.0, "enormous": at 0.55 it is 10 m
## and the console 1.9 m. The rig in its .tscn stands at the door scaled the same.

## What the room is, from the JSON: {door, rotors, wall_radius_p98, height_range...}. Empty if unread.
var meta: Dictionary = {}
## The table's scale for this room, and the size of its console in the model's own metres.
var room_scale := 1.0
var console_dims := Vector2(1.5, 1.2)
## Set by the tests: what the door does instead of leaving.
var leave_handler := Callable()

var model: Node3D = null
var rotors: Array[Node3D] = []
var door_button: VRButton = null
var console: Node3D = null
var _rotor_rest: Array[float] = []
var _t := 0.0
var _door_sfx: AudioStreamPlayer3D = null


func _ready() -> void:
	var row := ConsoleRooms.entry(console_id)
	room_scale = float(row.get("scale", 1.0))
	console_dims = row.get("console", console_dims) as Vector2
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(row["meta"])))
	meta = parsed as Dictionary if parsed is Dictionary else {}
	_build_model(str(row["glb"]))
	_build_colliders()
	_build_furniture_colliders(str(row.get("collision", "")))
	_build_lights()
	_build_door()
	_build_console()
	set_process(not rotors.is_empty())


func _process(delta: float) -> void:
	_t += delta
	for i in rotors.size():
		var r := rotors[i]
		var height := float((meta.get("rotors", [])[i] as Dictionary)["size"][1])
		r.position.y = _rotor_rest[i] + sin(_t * ROTOR_SPEED + i * 0.8) * ROTOR_TRAVEL * height


func _build_model(glb: String) -> void:
	model = Assets.instance_glb(glb)
	if model == null:
		push_warning("[xenu.tardis] cannot read %s: the console room has no model" % glb)
		model = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * room_scale
	add_child(model)
	for n in model.find_children("Rotor*", "MeshInstance3D", true, false):
		rotors.append(n as Node3D)
		_rotor_rest.append((n as Node3D).position.y)
	_two_sided(model)
	# a room of this many meshes casts no shadows: that is the lights' say, and they have none
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Every material of `root`, drawn on both sides. They are the template's, shared by every copy.
static func _two_sided(root: Node) -> void:
	var seen := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null or seen.has(mesh):
			continue
		seen[mesh] = true
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as BaseMaterial3D
			if m != null:
				m.cull_mode = BaseMaterial3D.CULL_DISABLED


func _body(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	return body


func _shape(body: StaticBody3D, shape: Shape3D, at: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = at
	body.add_child(cs)


func _build_colliders() -> void:
	var radius := float(meta.get("wall_radius_p98", 9.4)) * room_scale
	var heights: Array = meta.get("height_range", [-0.7, 9.0])
	var top := float(heights[1]) * room_scale
	var room := _body("RoomBody")
	room.add_to_group(&"poster_flat")
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = radius + 0.6
	floor_shape.height = 0.4
	_shape(room, floor_shape, Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0)))
	var ceiling := CylinderShape3D.new()
	ceiling.radius = radius + 0.6
	ceiling.height = 0.4
	_shape(room, ceiling, Transform3D(Basis.IDENTITY, Vector3(0, top + 0.2, 0)))
	# a ring of wall: boxes along the circle, a little outside the walls' reach, tall as the room
	var arc := TAU * radius / WALL_SEGMENTS
	var wall_h := maxf(top, 3.0)
	for i in WALL_SEGMENTS:
		var a := TAU * i / WALL_SEGMENTS
		var box := BoxShape3D.new()
		box.size = Vector3(arc + 0.3, wall_h, 0.6)
		var basis := Basis(Vector3.UP, -a + PI / 2.0)
		_shape(room, box, Transform3D(basis, Vector3(cos(a), 0, sin(a)) * (radius + 0.3) + Vector3(0, wall_h / 2.0, 0)))
	_build_floor(room)
	var cons := CylinderShape3D.new()
	cons.radius = console_dims.x * room_scale
	cons.height = console_dims.y * room_scale
	_shape(room, cons, Transform3D(Basis.IDENTITY, Vector3(0, console_dims.y * room_scale / 2.0, 0)))


## The floor a player stands on where the model's is not at 0: a surface through the table's profile, ramps over
## each step (see ConsoleRooms.ROOMS). A mesh, not a heightmap: a heightmap shape needs a scale on its node, which
## the physics does not trust. `backface_collision` so that nothing can drop through it from underneath.
func _build_floor(body: StaticBody3D) -> void:
	var profile: Array = ConsoleRooms.entry(console_id).get("floor", [])
	if profile.size() < 2:
		return
	var faces := PackedVector3Array()
	var segments := 48
	for i in range(1, profile.size()):
		var outer := profile[i - 1] as Array
		var inner := profile[i] as Array
		for k in segments:
			var a0 := TAU * k / segments
			var a1 := TAU * (k + 1) / segments
			var p00 := Vector3(cos(a0), 0, sin(a0)) * float(outer[0]) * room_scale + Vector3(0, float(outer[1]) * room_scale, 0)
			var p01 := Vector3(cos(a1), 0, sin(a1)) * float(outer[0]) * room_scale + Vector3(0, float(outer[1]) * room_scale, 0)
			var p10 := Vector3(cos(a0), 0, sin(a0)) * float(inner[0]) * room_scale + Vector3(0, float(inner[1]) * room_scale, 0)
			var p11 := Vector3(cos(a1), 0, sin(a1)) * float(inner[0]) * room_scale + Vector3(0, float(inner[1]) * room_scale, 0)
			faces.append_array([p00, p10, p01, p01, p10, p11])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	_shape(body, shape, Transform3D.IDENTITY)


## The things to bump into, from the converter's GLB: one convex hull per pillar and part of the console.
func _build_furniture_colliders(glb: String) -> void:
	if glb.is_empty():
		return
	var proxy := Assets.instance_glb(glb)
	if proxy == null:
		push_warning("[xenu.tardis] cannot read %s: the pillars and the console have no collision" % glb)
		return
	var furniture := _body("FurnitureBody")
	# what stands in the doorway is no furniture: a hull over it blocks the pointer's ray to the door's button
	var keep_clear := AABB()
	var door: Dictionary = meta.get("door", {})
	if not door.is_empty():
		var c: Array = door["centre"]
		var at := Vector3(float(c[0]), float(c[1]), float(c[2])) * room_scale
		keep_clear = AABB(at - Vector3(0.9, 1.4, 1.2) * room_scale, Vector3(1.8, 2.8, 2.4) * room_scale)
	for mi in proxy.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var shape := m.mesh.create_convex_shape(true, false) as ConvexPolygonShape3D
		if shape != null:
			# a shape's own scale is not trusted by the physics: scale its points, keep only the place
			var xf := Assets.relative_transform(m, proxy)
			var pts := PackedVector3Array()
			for p in shape.points:
				pts.append(xf.basis * p * room_scale)
			shape.points = pts
			var hull := AABB(pts[0] + xf.origin * room_scale, Vector3.ZERO)
			for p in pts:
				hull = hull.expand(p + xf.origin * room_scale)
			if keep_clear.size != Vector3.ZERO and keep_clear.intersects(hull):
				continue
			_shape(furniture, shape, Transform3D(Basis.IDENTITY, xf.origin * room_scale))
	proxy.free()


func _build_lights() -> void:
	var quality := get_node_or_null("/root/QualityManager")
	for s: Array in ConsoleRooms.lights(console_id):
		var l := OmniLight3D.new()
		l.position = (s[0] as Vector3) * room_scale
		l.light_color = s[1]
		l.light_energy = s[2]
		l.omni_range = float(s[3]) * room_scale
		l.shadow_enabled = false
		l.add_to_group("no_shadow")
		add_child(l)
		if quality != null:
			quality.configure_light(l)


func _build_door() -> void:
	var door: Dictionary = meta.get("door", {})
	if door.is_empty():
		return
	var c: Array = door["centre"]
	var at := Vector3(float(c[0]), float(c[1]), float(c[2])) * room_scale
	_door_sfx = AudioStreamPlayer3D.new()
	_door_sfx.name = "DoorSfx"
	_door_sfx.unit_size = 4.0
	_door_sfx.max_distance = 30.0
	_door_sfx.position = at
	add_child(_door_sfx)
	door_button = VRButton.new()
	door_button.name = "DoorButton"
	door_button.require_trigger = true
	door_button.interact_margin = 0.08
	door_button.depress_depth = 0.0
	# the button's +Y is its face: out of the door, into the room (-Z)
	door_button.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), at + Vector3(0, 0, -0.3 * room_scale))
	var cap := MeshInstance3D.new()
	cap.name = "ButtonMesh"
	var plate := BoxMesh.new()
	plate.size = Vector3(1.2, 0.01, 2.2) * room_scale
	cap.mesh = plate
	cap.visible = false
	door_button.add_child(cap)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 0.2, 2.3) * room_scale
	cs.shape = box
	door_button.add_child(cs)
	add_child(door_button)
	door_button.button_pressed.connect(press_door)
	if bool(ConsoleRooms.entry(console_id).get("door_light", false)):
		# a doorway that is a dark alcove is no door: a white light fills it (the way out is into the light)
		var glow := MeshInstance3D.new()
		glow.name = "DoorLight"
		var quad := QuadMesh.new()
		quad.size = Vector2(1.25, 2.25) * room_scale
		glow.mesh = quad
		var lit := StandardMaterial3D.new()
		lit.albedo_color = Color(2.5, 2.5, 2.5)
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lit.cull_mode = BaseMaterial3D.CULL_DISABLED
		glow.material_override = lit
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.transform = Transform3D(Basis(Vector3.UP, PI), at + Vector3(0, 0, -0.12 * room_scale))
		add_child(glow)


## The door was pressed: it sounds, and a moment later the player is let out.
func press_door() -> void:
	if _door_sfx != null:
		_door_sfx.stream = Assets.mp3(DOOR_SOUND)
		_door_sfx.play()
	get_tree().create_timer(LEAVE_DELAY).timeout.connect(_leave)


func _leave() -> void:
	if leave_handler.is_valid():
		leave_handler.call()
	else:
		Travel.leave(self)


func _build_console() -> void:
	console = ConsoleMenu.new()
	console.name = "Console"
	add_child(console)
	console.setup(console_dims.x * room_scale, console_dims.y * room_scale)


## Take everything the player put in the room out of it: what RetroXR saves in a slot is what is in
## the "spawned" group, and none of the room's own parts is. Returns how many things went.
func reset_room() -> int:
	var gone := 0
	for n in get_tree().get_nodes_in_group("spawned"):
		if n is Node and not is_ancestor_of(n) and n != self:
			(n as Node).queue_free()
			gone += 1
	return gone
