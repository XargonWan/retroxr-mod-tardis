## Suite for the console room and the way in and out of the TARDIS: the table of rooms, the settings
## kept between runs, TardisTravel against a stand-in SceneManager, the room built from its GLB, and
## the console's menu. No headset needed.
##
##   godot --headless --path RetroXR res://mods/xenu.tardis/tests/console_tests.tscn
##
## A SCENE (the TARDIS extends XRToolsPickable: no autoloads under --script). Prints
## `[tardis-tests] N cases, M failed`; non-zero on a failure, zero cases, or a count other than
## EXPECTED_CASES. There are no loops over checks, so EXPECTED_CASES is the number of `_check(` calls.
extends Node

const ConsoleRooms := preload("res://mods/xenu.tardis/scripts/console_rooms.gd")
const Settings := preload("res://mods/xenu.tardis/scripts/tardis_settings.gd")
const Travel := preload("res://mods/xenu.tardis/scripts/tardis_travel.gd")
const FakeManager := preload("res://mods/xenu.tardis/tests/fake_scene_manager.gd")
const TARDIS_SCENE := "res://mods/xenu.tardis/scenes/tardis.tscn"
const ROOM_SCRIPT := "res://mods/xenu.tardis/scripts/console_room.gd"
const MENU_SCENE := "res://mods/xenu.tardis/scenes/console_menu_2d.tscn"
const SCRATCH := "user://test_tardis_settings.json"
const EXPECTED_CASES := 81

var _cases := 0
var _failed := 0


func _ready() -> void:
	_table()
	_settings()
	_forgotten()
	await _travel()
	await _console_room()
	await _menu()
	await _panel()
	_registration()
	print("[tardis-tests] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[tardis-tests] FAIL ran %d cases, expected %d: a case aborted, or EXPECTED_CASES is stale" % [_cases, EXPECTED_CASES])
		_failed += 1
	get_tree().quit(1 if _failed > 0 or _cases == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[tardis-tests] FAIL ", what)


func _table() -> void:
	_check(float(ConsoleRooms.ROOMS["1"]["door"]["centre"][2]) < 0.0 and float(ConsoleRooms.ROOMS["10"].get("opening", {}).get("top", 0.0)) > 0.0,
		"the 1st Doctor's way out is the hexagonal door on the -Z wall (the table's), the 10th's keeps the converter's on +Z")
	_check(ConsoleRooms.resolve_id("nope") == "1" and ConsoleRooms.DEFAULT_ID == "1", "an unknown console room is the default, the 1st Doctor's")
	_check(ConsoleRooms.room_id_of("10") == "xenu.tardis:console_10" and ConsoleRooms.id_of_room("xenu.tardis:console_10") == "10",
		"a room id is permanent and goes both ways")
	_check(ConsoleRooms.is_console_room("xenu.tardis:console_10") and ConsoleRooms.is_console_room("xenu.tardis:console_1")
		and not ConsoleRooms.is_console_room("bedroom") and not ConsoleRooms.is_console_room("xenu.tardis:console_99"), "what is a console room")
	var cyan := false
	var amber := false
	var white := 0
	for l: Array in ConsoleRooms.lights("10"):
		var c := l[1] as Color
		cyan = cyan or (c.b > c.r + 0.3 and c.g > 0.8)
		amber = amber or (c.r > c.b + 0.5 and c.g > 0.6)
	for l: Array in ConsoleRooms.lights("1"):
		var c := l[1] as Color
		white += 1 if c.r > 0.85 and c.g > 0.85 and c.b > 0.75 else 0
	_check(cyan and amber and white >= 9, "each room has the lights of its photographs: the 10th's cyan rotor and amber roundels, the 1st's many white lights (%d)" % white)


func _settings() -> void:
	Settings.path = SCRATCH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	_check(Settings.console() == "1" and Settings.exterior() == "default", "no file: the defaults")
	Settings.set_console("10")
	Settings.set_exterior("default")
	_check(FileAccess.file_exists(SCRATCH) and Settings.console() == "10", "a choice is kept in a file")
	_check(Settings.hum(), "the console rooms hum until the player says otherwise")
	Settings.set_hum(false)
	_check(not Settings.hum() and Settings.console() == "10", "the hum is switched off and kept, and the console room with it")
	Settings.set_console("1")
	Settings.set_console("10")
	_check(not Settings.hum(), "choosing a console room does not switch the hum back on")
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string('{"console": "gone", "exterior": "gone"}')
	f.close()
	_check(Settings.console() == "1" and Settings.exterior() == "default", "an id that is not known reads as the default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.path = Settings.PATH


func _forgotten() -> void:
	# a deleted TARDIS is not put back when the player comes out of a console room
	var gone := Node3D.new()
	add_child(gone)
	gone.position = Vector3(2, 0, -1)
	Travel.origin = {"room": "bedroom", "tardis": Transform3D(Basis.IDENTITY, Vector3(5, 0, 5))}
	Travel.forget(gone)
	_check(Travel.origin.has("tardis"), "deleting some other TARDIS leaves the one entered where it was")
	Travel.origin = {"room": "bedroom", "tardis": Transform3D(Basis.IDENTITY, Vector3(2, 0, -1))}
	Travel.forget(gone)
	_check(not Travel.origin.has("tardis") and Travel.origin["room"] == "bedroom", "deleting the one entered forgets it, and keeps the room to go back to")
	gone.free()
	Travel.origin = {}


func _travel() -> void:
	Travel.origin = {}
	var mgr := FakeManager.new()
	add_child(mgr)
	var rig := Node3D.new()
	rig.name = "PlayerRig"
	add_child(rig)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(1, 1.6, 2)
	cam.current = true
	var tardis := (load(TARDIS_SCENE) as PackedScene).instantiate() as Node3D
	add_child(tardis)
	tardis.global_transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(2, 0, -1))
	await get_tree().process_frame
	Settings.path = SCRATCH
	_check(Travel.enter(tardis, mgr) and mgr.changes == ["xenu.tardis:console_1"], "the door asks SceneManager for the console room (the default is the 1st Doctor's)")
	_check(Travel.origin["room"] == "bedroom" and (Travel.origin["tardis"] as Transform3D).is_equal_approx(tardis.global_transform)
		and (Travel.origin["head"] as Transform3D).origin.is_equal_approx(cam.global_position), "the room, the TARDIS and the head are kept")
	var front := tardis.global_basis.z
	var pose := Travel.step_out_pose(tardis.global_transform)
	_check(pose.origin.is_equal_approx(tardis.global_position + front * Travel.STEP_OUT) and (-pose.basis.z).dot(front) > 0.999,
		"out of the door: in front of it, facing away from it")
	_check(not Travel.in_console_room(mgr), "in the bedroom is not in a console room")
	mgr.current_scene_id = "xenu.tardis:console_10"
	_check(Travel.in_console_room(mgr), "in the console room is")
	# out: the TARDIS is gone from the room (a clean slot is not saved), so one is put back where it was
	tardis.free()
	await get_tree().process_frame
	_check(Travel.leave(self, mgr) and mgr.changes.back() == "bedroom", "the console room's door asks for the room they came from")
	mgr.scene_content_ready.emit("some other room")
	_check(get_tree().get_nodes_in_group(&"xenu_tardis").is_empty() and rig.transform == Transform3D.IDENTITY, "a different room arriving moves nobody")
	mgr.scene_content_ready.emit("bedroom")
	var back := get_tree().get_nodes_in_group(&"xenu_tardis")
	_check(back.size() == 1 and (back[0] as Node3D).global_transform.is_equal_approx(Travel.origin["tardis"]), "the TARDIS stands where it did")
	_check(rig.transform.is_equal_approx(Travel.step_out_pose(Travel.origin["tardis"])), "and the player steps out of it")
	# a TARDIS the slot kept, since moved: the player steps out of that one, and there is still one
	(back[0] as Node3D).global_position = Vector3(-3, 0, 4)
	rig.transform = Transform3D.IDENTITY
	Travel.leave(self, mgr)
	mgr.scene_content_ready.emit("bedroom")
	_check(get_tree().get_nodes_in_group(&"xenu_tardis").size() == 1 and rig.position.distance_to(Vector3(-3, 0, 4)) > 1.0
		and rig.position.distance_to(Vector3(-3, 0, 4)) < 2.0, "the TARDIS that is there is the one stepped out of")
	# nothing kept (the game was restarted inside): the platform's default room, and nobody is placed
	Travel.origin = {}
	rig.transform = Transform3D.IDENTITY
	Travel.leave(self, mgr)
	_check(mgr.changes.back() == "arcade", "nothing kept: the default room")
	mgr.scene_content_ready.emit("arcade")
	_check(rig.transform == Transform3D.IDENTITY, "nothing kept: nobody is moved")
	for n in get_tree().get_nodes_in_group(&"xenu_tardis"):
		n.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.path = Settings.PATH
	mgr.free()
	rig.free()
	cam.free()
	await get_tree().process_frame


func _console_room() -> void:
	for id: String in ConsoleRooms.ids():
		await _one_room(id)


func _one_room(id: String) -> void:
	var row := ConsoleRooms.entry(id)
	var room := Node3D.new()
	room.set_script(load(ROOM_SCRIPT))
	room.set("console_id", id)
	add_child(room)
	await get_tree().process_frame
	_check(room.hum != null and room.hum.playing and (room.hum.stream as AudioStreamMP3).loop and is_equal_approx(db_to_linear(room.hum.volume_db), 0.9),
		"room %s: the interior hum is playing, looping, at 90%% of its volume" % id)
	room.set_hum(false)
	var silent: bool = not room.hum.playing
	room.set_hum(true)
	_check(silent and room.hum.playing, "room %s: the hum goes off and comes back on with the menu's switch" % id)
	var meshes := room.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() >= 3, "room %s: the model is there: %d meshes" % [id, meshes.size()])
	_check(room.rotors.size() == 2, "room %s: the time rotor is found" % id)
	var body := room.get_node_or_null("RoomBody") as StaticBody3D
	_check(body != null and body.collision_layer == 1 and body.get_child_count() > 38, "room %s: a floor, a ceiling, a ring of wall and the console to stand on: on layer 1" % id)
	var furniture := room.get_node_or_null("FurnitureBody") as StaticBody3D
	var has_hulls := not str(row["collision"]).is_empty()
	_check(not has_hulls or (furniture != null and furniture.collision_layer == 1 and furniture.get_child_count() >= 5 and furniture.get_child(0).shape is ConvexPolygonShape3D),
		"room %s: what has a collision mesh can be bumped into" % id)
	_check(is_equal_approx(room.model.scale.x, float(row["scale"])) and is_equal_approx(room.room_scale, float(row["scale"])), "room %s: drawn at its table's scale (x%.2f)" % [id, room.room_scale])
	var reach := 0.0
	if has_hulls:
		for cs in furniture.get_children():
			if not ((cs as CollisionShape3D).shape is ConvexPolygonShape3D):
				continue
			for p: Vector3 in ((cs as CollisionShape3D).shape as ConvexPolygonShape3D).points:
				reach = maxf(reach, (p + (cs as CollisionShape3D).position).length())
	var floor_body := room.get_node_or_null("RoomBody") as StaticBody3D
	var floor_cs := floor_body.get_child(0) as CollisionShape3D
	var floor_top := floor_cs.position.y + (floor_cs.shape as CylinderShape3D).height / 2.0
	_check(absf(floor_top - float(row.get("floor_offset", 0.0))) < 0.001, "room %s: the floor to walk on is at the table's height (%.3f)" % [id, floor_top])
	var boxes := 0
	var tallest := 0.0
	if furniture != null:
		for cs in furniture.get_children():
			if (cs as CollisionShape3D).shape is BoxShape3D:
				boxes += 1
				tallest = maxf(tallest, ((cs as CollisionShape3D).shape as BoxShape3D).size.y)
	_check(str(row.get("solids", "")).is_empty() or (boxes > 100 and tallest > 1.0), "room %s: the pillars and railings are solid: %d boxes, the tallest %.1f m" % [id, boxes, tallest])
	var leaves: bool = room.get_node_or_null("DoorLeafRight") != null and room.get_node_or_null("DoorLeafLeft") != null
	_check(leaves == bool(row.get("door_leaves", false)), "room %s: the way out is a pair of police box doors where the table says so (%s)" % [id, str(leaves)])
	_check(room.seats.size() == (row.get("seats", []) as Array).size(), "room %s: what can be sat on is there: %d seats" % [id, room.seats.size()])
	var wall: float = float(room.meta["wall_radius_p98"]) * room.room_scale
	_check(not has_hulls or (reach > 1.0 and reach <= wall + 1.0), "room %s: its collision is scaled with it: reaches %.1f m, the wall is at %.1f" % [id, reach, wall])
	var door_c: Array = room.meta["door"]["centre"]
	_check(room.door_button.position.distance_to(Vector3(door_c[0], door_c[1], door_c[2]) * room.room_scale + Vector3(0, 0, (-1.0 if float(door_c[2]) > 0.0 else 1.0) * 0.3 * room.room_scale)) < 0.01,
		"room %s: the door's button is where the scaled door is" % id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var door_p: Vector3 = room.door_button.global_position
	var q := PhysicsRayQueryParameters3D.create(Vector3(door_p.x, 1.6, door_p.z - 1.3), door_p)
	q.collision_mask = 1 | (1 << 20)
	q.collide_with_areas = true
	var seen := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	_check(not seen.is_empty() and seen["collider"] == room.door_button,
		"room %s: from where the player stands nothing is between the eye and the door's button (it meets %s)" % [id, "nothing" if seen.is_empty() else str((seen["collider"] as Node).name)])
	# the click itself: RetroXR's own desktop resolver, which stops at the first solid thing it does not know
	var click := InteractionResolver.resolve_desktop(get_viewport().world_3d.direct_space_state,
		Vector3(door_p.x, 1.6, door_p.z - 1.3), door_p + Vector3(0, 0, 0.05), null)
	_check(click.is_valid() and click.kind == InteractionTarget.KIND_BUTTON and click.action_node == room.door_button,
		"room %s: a click aimed at the door is the door's button, by RetroXR's own resolver (it gets %s)" % [id, str(click.kind)])
	var floor_ok := true
	var floor_seen := ""
	var rs: float = room.room_scale
	var wall_r: float = float(room.meta["wall_radius_p98"])
	for r: float in [2.5, 3.9, 5.0, 6.4, 7.5]:
		if (r + 0.3) > wall_r:
			continue
		for k in 8:
			var a := TAU * k / 8.0 + 0.3
			var from: Vector3 = Vector3(cos(a), 0, sin(a)) * r * rs + Vector3(0, 3.0, 0)
			var rq := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -6.0, 0))
			rq.collision_mask = 1
			var rh := get_viewport().world_3d.direct_space_state.intersect_ray(rq)
			if rh.is_empty() or (rh["collider"] as Node).name != "RoomBody":
				continue  # a pillar, say, is in the way here
			var want: float = ConsoleRooms.floor_height(id, r) * rs
			if absf((rh["position"] as Vector3).y - want) > 0.03:
				floor_ok = false
				floor_seen = "r %.1f: floor at %.2f, wanted %.2f" % [r, (rh["position"] as Vector3).y, want]
	_check(floor_ok, "room %s: the floor a player stands on is the table's profile, ramps over the steps (%s)" % [id, floor_seen if not floor_ok else "all radii"])
	var one_sided := 0
	for mi in meshes:
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			if mat != null and mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
				one_sided += 1
	_check(one_sided == 0, "room %s: every material is drawn on both sides (%d are not)" % [id, one_sided])
	_check(room.door_button != null and room.door_button.require_trigger and room.find_children("*", "OmniLight3D", false, false).size() == ConsoleRooms.lights(id).size()
		and (room.get_node_or_null("DoorLight") != null) == (bool(row["door_light"]) and not bool(row.get("door_leaves", false))),
		"room %s: a door to press, the lights of its table, and a light in the doorway where the table says" % id)
	_check(room.console.has_method("toggle_options_ui") and room.console.pointer.collision_layer == (1 << 20), "room %s: the console can be pointed at and has a menu" % id)
	var rest: float = room.rotors[0].position.y
	room._process(1.0)
	_check(not is_equal_approx(room.rotors[0].position.y, rest), "room %s: the rotor moves" % id)
	var left: Array = []
	room.leave_handler = func() -> void: left.append(true)
	room.press_door()
	await get_tree().create_timer(room.LEAVE_DELAY + 0.3).timeout
	_check(left.size() == 1, "room %s: the door lets the player out once" % id)
	var stuff_a := Node3D.new()
	stuff_a.add_to_group("spawned")
	add_child(stuff_a)
	var stuff_b := Node3D.new()
	stuff_b.add_to_group("spawned")
	add_child(stuff_b)
	_check(room.reset_room() == 2 and stuff_a.is_queued_for_deletion() and stuff_b.is_queued_for_deletion() and not room.is_queued_for_deletion(),
		"room %s: reset takes out what was put in, and only that" % id)
	room.free()
	await get_tree().process_frame


func _menu() -> void:
	var ui := (load(MENU_SCENE) as PackedScene).instantiate() as Control
	add_child(ui)
	await get_tree().process_frame
	ui.populate("10", "default")
	await get_tree().process_frame
	var buttons: Array = ui.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return not (b as Button).text.is_empty())
	var chosen: Array = []
	ui.console_chosen.connect(func(id: String) -> void: chosen.append("console:" + id))
	ui.exterior_chosen.connect(func(id: String) -> void: chosen.append("exterior:" + id))
	var confirmed: Array = []
	ui.reset_confirmed.connect(func() -> void: confirmed.append(true))
	var by_text := func(part: String) -> Button:
		for b: Button in buttons:
			if b.text.contains(part):
				return b
		return null
	_check(buttons.size() >= 3 and by_text.call("Console Room") != null and by_text.call("Police Box") != null and by_text.call("Reset") != null,
		"the menu offers a console room, an exterior and a reset")
	(by_text.call("10th") as Button).pressed.emit()
	(by_text.call("Police Box") as Button).pressed.emit()
	_check(chosen == ["console:10", "exterior:default"], "a choice says which: %s" % [chosen])
	var left: Array = []
	ui.leave_requested.connect(func() -> void: left.append(true))
	(by_text.call("Leave the TARDIS") as Button).pressed.emit()
	_check(left.size() == 1, "the menu has a way out, whatever becomes of the door")
	var hum_said: Array = []
	ui.hum_toggled.connect(func(on: bool) -> void: hum_said.append(on))
	(by_text.call("Interior hum") as Button).pressed.emit()
	_check(hum_said == [false], "the menu switches the hum: it was on, so it asks for off: %s" % [hum_said])
	var reset := by_text.call("Reset") as Button
	reset.pressed.emit()
	_check(confirmed.is_empty() and reset.text.begins_with("Really"), "reset asks again")
	reset.pressed.emit()
	_check(confirmed.size() == 1, "and does it when asked twice")
	ui.queue_free()
	await get_tree().process_frame


func _panel() -> void:
	var console := Node3D.new()
	add_child(console)
	const Panel := preload("res://mods/xenu.tardis/scripts/console_panel.gd")
	Panel.toggle_for(console, null)
	for i in 3:
		await get_tree().process_frame
	var panel := console.get_node_or_null("ConsolePanel")
	_check(panel != null and panel.visible, "pointing at the console opens its menu as a panel")
	Panel.toggle_for(console, null)
	_check(not panel.visible, "and again closes it")
	console.free()
	# it floats over the console's top, on the player's side (not out in the room)
	var on_it := preload("res://mods/xenu.tardis/scripts/console_menu.gd").new()
	add_child(on_it)
	on_it.setup(1.0, 0.8)
	var head := Camera3D.new()
	add_child(head)
	head.position = Vector3(0, 1.6, 4)
	Panel.toggle_for(on_it, head)
	for i in 3:
		await get_tree().process_frame
	var shown := on_it.get_node("ConsolePanel") as Node3D
	_check(shown.global_position.distance_to(Vector3(0, 0.8 + Panel.HOVER, 0.5)) < 0.01, "the menu floats on the console, toward the player: %s" % shown.global_position)
	_check(on_it.pointer.collision_layer == 0, "with the menu up the console's pointing cylinder lets the ray through to it")
	Panel.toggle_for(on_it, head)
	_check(on_it.pointer.collision_layer == (1 << 20), "and the console can be pointed at again once the menu is shut")
	on_it.free()
	head.free()
	await get_tree().process_frame


func _registration() -> void:
	var src := FileAccess.get_file_as_string("res://mods/xenu.tardis/mod_main.gd")
	_check(src.contains("api.register_room(") and src.contains("ConsoleRooms.room_id_of(id)") and src.contains('"hidden": true'),
		"mod_main.gd registers each console room, asking to be hidden from the SCENE tab")
