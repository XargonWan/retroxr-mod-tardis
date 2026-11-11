## Suite for the TARDIS: how it blinks in, where it lands, the door, being sent away, and the
## screwdriver calling it. No room, headset or controller needed: a floor and some walls are built here.
##
##   godot --headless --path RetroXR res://mods/xenu.tardis/tests/tardis_tests.tscn
##
## A SCENE, like screwdriver_tests (the TARDIS extends XRToolsPickable: no autoloads under --script).
## Prints `[tardis-tests] N cases, M failed`; non-zero on a failure, zero cases, or a count other than
## EXPECTED_CASES (a script error aborts the running function silently). There are no loops over
## checks here, so EXPECTED_CASES is the number of `_check(` calls below.
extends Node

const Summon := preload("res://mods/xenu.tardis/scripts/tardis_summon.gd")
const Exteriors := preload("res://mods/xenu.tardis/scripts/tardis_exteriors.gd")
const TARDIS_SCENE := "res://mods/xenu.tardis/scenes/tardis.tscn"
const SCREWDRIVER_SCENE := "res://mods/xenu.tardis/scenes/sonic_screwdriver.tscn"
const Tardis := preload("res://mods/xenu.tardis/scripts/tardis.gd")
const EXPECTED_CASES := 87

var _cases := 0
var _failed := 0
var _room: Node3D = null


func _ready() -> void:
	_pure()
	await _the_scene()
	await _vr_door()
	await _door_pointer()
	await _deleted()
	await _states()
	await _see_through()
	await _pointed_at()
	await _door()
	await _upright()
	await _landing_spot()
	await _screwdriver_calls_it()
	await _no_room()
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


func _spawn() -> Node:
	var node := (load(TARDIS_SCENE) as PackedScene).instantiate()
	add_child(node)
	return node


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().physics_frame


## A fresh room: a floor at y = 0 (layer 1) and nothing else. Anything added is freed with it.
func _new_room(with_floor: bool = true) -> Node3D:
	if is_instance_valid(_room):
		_room.free()
	_room = Node3D.new()
	add_child(_room)
	if not with_floor:
		return _room
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	cs.shape = box
	floor_body.add_child(cs)
	_room.add_child(floor_body)
	floor_body.position = Vector3(0, -0.1, 0)
	return _room


func _block(layer: int, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	_room.add_child(body)
	body.position = at


func _pure() -> void:
	const T := preload("res://mods/xenu.tardis/scripts/tardis.gd")
	_check(T.alpha_at(0.0, 15.0, true) == 0.0 and T.alpha_at(15.0, 15.0, true) == 1.0, "materialising goes from nothing to solid")
	_check(T.alpha_at(0.0, 15.0, false) == 1.0 and T.alpha_at(15.0, 15.0, false) == 0.0, "going: solid at first, gone at the end")
	var early := 0.0
	var late := 0.0
	var worst_step := 0.0
	var prev: float = T.alpha_at(0.0, 15.0, true)
	for i in 300:
		var a: float = T.alpha_at(i * 0.05, 15.0, true)
		worst_step = maxf(worst_step, absf(a - prev))
		prev = a
		if i < 100:
			early += a
		elif i >= 200:
			late += a
	_check(late > early * 1.5, "ever more there: %.1f early, %.1f late" % [early, late])
	_check(worst_step < 0.3, "a switch with a ramp, not an instant on and off: the biggest jump in 0.05 s is %.2f" % worst_step)
	var series: Array[float] = []
	for i in 301:
		series.append(T.alpha_at(i * 0.05, 15.0, true))
	var minima := 0
	var lowest := 1.0
	for i in range(30, 260):  # 1.5 s to 13 s
		lowest = minf(lowest, series[i])
		if series[i] < series[i - 1] and series[i] <= series[i + 1]:
			minima += 1
	_check(minima >= 4, "it pulses as the sound does, a dip every 2 s: %d dips" % minima)
	_check(lowest < 0.1, "it switches almost fully off between the solid tops: lowest %.2f" % lowest)
	var bottom_early := 1.0
	var bottom_late := 1.0
	var best_by_eight := 0.0
	for i in range(0, 260):  # up to 13 s
		if i <= 160:
			best_by_eight = maxf(best_by_eight, series[i])
		if i >= 80 and i < 140:
			bottom_early = minf(bottom_early, series[i])
		elif i >= 140:
			bottom_late = minf(bottom_late, series[i])
	var last_swing := 1.0
	for i in range(246, 276):  # 12.3 s to 13.8 s, the last of it before it is solid for good
		last_swing = minf(last_swing, series[i])
	_check(last_swing > 0.9, "the last transition into solid is a gentle rise, not a pulse: never below %.2f over the last 1.5 s" % last_swing)
	_check(best_by_eight > 0.985, "it swings to fully SOLID by 8 s of 15, well before the end: %.2f" % best_by_eight)
	_check(bottom_early < 0.5 and bottom_late > bottom_early,
		"between the solid tops it is a ghost, ever less of one: %.2f (4-7 s), %.2f (7-13 s)" % [bottom_early, bottom_late])
	_check(T.alpha_at(15.0 * T.SETTLE + 0.01, 15.0, true) == 1.0 and T.alpha_at(15.0 - 15.0 * T.SETTLE - 0.01, 15.0, false) == 1.0,
		"solid from SETTLE of the way, and solid until that far from the end going")
	var ahead := Summon.candidates(Vector2.ZERO, Vector2(0, -1))
	_check(ahead[0].distance_to(Vector2(0, -Summon.FRONT_DISTANCE)) < 0.01, "the first spot tried is the one straight ahead")
	var near_enough := true
	for p: Vector2 in ahead:
		near_enough = near_enough and p.length() >= Summon.MIN_DISTANCE - 0.001
	_check(near_enough, "no spot is closer than MIN_DISTANCE")
	var sound_start: float = preload("res://mods/xenu.tardis/scripts/mod_assets.gd").DOOR_SOUND_START
	_check(sound_start >= 0.5 and sound_start <= 0.75, "the door sound is played from where its 0.6 s of silence ends")
	_check(Summon.score(Vector2(0, -1.7), Vector2.ZERO, Vector2(0, -1)) < Summon.score(Vector2(0, 1.7), Vector2.ZERO, Vector2(0, -1)),
		"ahead beats behind at the same distance")


func _the_scene() -> void:
	var t := _spawn()
	await get_tree().process_frame
	_check(t.has_method("materialize"), "the TARDIS script compiled and is attached")
	_check(t.is_in_group(&"xenu_tardis") and t.is_in_group(&"remote_target"), "in the TARDIS group and the remote's")
	var meshes := t.find_children("*", "MeshInstance3D", false, false)
	_check(meshes.size() >= 4, "its meshes are direct children (the highlight looks there): %d" % meshes.size())
	_check(t.find_child("DoorR", false, false) is MeshInstance3D, "the door leaf is a mesh of its own")
	_check(t.get_node_or_null("DoorButton") != null and t.get_node_or_null("GroundPlacement") != null, "a door button and a ground placement")
	var lit := 0
	for mi: Node in meshes:
		var m3 := mi as MeshInstance3D
		for surf in m3.mesh.get_surface_count():
			var sm := m3.get_surface_override_material(surf) as StandardMaterial3D
			if sm != null and sm.emission_enabled and sm.emission.is_equal_approx(Color.WHITE) and sm.emission_energy_multiplier > 0.2 and sm.emission_energy_multiplier < 1.5:
				lit += 1
	_check(lit >= 3, "the white of the model (windows, POLICE PUBLIC CALL BOX) is lit with a medium emission: %d surfaces" % lit)
	_check(t.remote_layout()[0]["id"] == "power", "the remote's grid has a power key")
	_check(t.get_meta(&"mod_object_type", "") == "xenu.tardis:tardis" and t.is_in_group("spawned")
		and FileAccess.get_file_as_string("res://mods/xenu.tardis/mod_main.gd").contains('TARDIS_TYPE := "xenu.tardis:tardis"'),
		"it carries the type RetroXR saves a mod's object by, and is in the spawned group: it is kept in the slot")
	var pointer := t.get_node("PointerArea") as StaticBody3D
	_check(pointer.position.y > 1.0 and RemoteTarget.of(pointer) == t and pointer.collision_layer == (1 << 20),
		"the screwdriver's target is on layer 21 and its origin is at the body's middle (the cone aims at origins)")
	_check(t.grab_hold_seconds() > 0.0 and t.throw_scale() == 0.0, "taken by holding, never thrown")
	t.queue_free()
	await get_tree().process_frame


## The door as RetroXR's VRDoor (a stand-in here): hung on the leaf, handle where the model's is, pulled open far enough it goes in.
func _vr_door() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.6, 3)
	cam.current = true
	Tardis.door_script_path = "res://mods/xenu.tardis/tests/fake_vr_door.gd"
	var t := _spawn()
	await get_tree().process_frame
	var fake: Node3D = t._vr_door
	var expect_at := Vector3(0.462 - 0.231, t._door.position.y, t._door.position.z)
	_check(fake != null and fake.leaf == t._door and fake.position.is_equal_approx(expect_at) and is_equal_approx(float(fake.width), 0.462),
		"a VRDoor hangs on the leaf, at its bottom middle: %s" % [fake.position if fake != null else "none"])
	_check(fake != null and t.get_node_or_null("DoorButton") == null and (fake.knob_position as Vector2).is_equal_approx(Vector2(0.034 - fake.position.x, 0.945 - fake.position.y)),
		"with a VRDoor there is no button over the front, and the handle is where the model's is")
	var went: Array = []
	t.travel_handler = func() -> void: went.append(true)
	var used: Array = []
	t.door_used.connect(func(_pose: Transform3D) -> void: used.append(true))
	fake.emit_signal("unlatched")
	_check((t.get_node("DoorSfx") as AudioStreamPlayer3D).playing, "the handle turned, the latch lets go: the door creaks")
	fake.emit_signal("door_changed", 10.0, false)
	_check((t.get_node("Inside") as MeshInstance3D).visible and used.is_empty() and went.is_empty(), "open a little: the light behind shows, and nobody goes in yet")
	fake.angle = 35.0
	fake.emit_signal("door_changed", 35.0, false)
	fake.emit_signal("door_changed", 40.0, false)
	await get_tree().create_timer(Tardis.ENTER_DELAY + 0.3).timeout
	_check(went.size() == 1 and used.size() == 1 and fake.closed and not (t.get_node("Inside") as MeshInstance3D).visible,
		"pulled 30 degrees open: in, once, the door shut behind (it is saved shut) and its light off: %d, %d" % [went.size(), used.size()])
	Tardis.door_script_path = Tardis.VR_DOOR_SCRIPT
	t.queue_free()
	cam.queue_free()
	await get_tree().process_frame


## The fallback door (no VRDoor): what the laser presses, with the trigger or A, never with a hand that holds something.
func _door_pointer() -> void:
	var t := _spawn()
	await get_tree().process_frame
	var ptr := t.get_node_or_null("DoorPointer") as StaticBody3D
	_check(ptr != null and ptr.collision_layer == (1 << 20), "without a VRDoor the door has a body on the pointable layer: a headset's laser sees a body, not the button's area")
	var presses: Array = []
	ptr.connect("pressed", func() -> void: presses.append(true))
	var hand := Node3D.new()
	add_child(hand)
	var a_value := [0.0]
	var busy := [false]
	ptr.read_a = func(_p: Node3D) -> float: return a_value[0]
	ptr.hand_busy = func(_p: Node3D) -> bool: return busy[0]
	var Ev := XRToolsPointerEvent
	ptr.pointer_event(Ev.new(Ev.Type.PRESSED, hand, ptr, Vector3.ZERO, Vector3.ZERO))
	_check(presses.size() == 1, "the laser's trigger pressed on it opens the door")
	ptr.pointer_event(Ev.new(Ev.Type.ENTERED, hand, ptr, Vector3.ZERO, Vector3.ZERO))
	a_value[0] = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check(presses.size() == 2, "A pressed with the laser on it opens it too, once, not every frame it is held")
	a_value[0] = 0.0
	await get_tree().process_frame
	a_value[0] = 1.0
	await get_tree().process_frame
	_check(presses.size() == 3, "let go and pressed again: again")
	busy[0] = true
	ptr.pointer_event(Ev.new(Ev.Type.PRESSED, hand, ptr, Vector3.ZERO, Vector3.ZERO))
	a_value[0] = 0.0
	await get_tree().process_frame
	a_value[0] = 1.0
	await get_tree().process_frame
	_check(presses.size() == 3, "a hand that holds something (the screwdriver aimed at the TARDIS) neither opens the door with the trigger nor with A")
	ptr.pointer_event(Ev.new(Ev.Type.EXITED, hand, ptr, Vector3.ZERO, Vector3.ZERO))
	busy[0] = false
	a_value[0] = 0.0
	await get_tree().process_frame
	a_value[0] = 1.0
	await get_tree().process_frame
	_check(presses.size() == 3, "A with the laser off the door does nothing")
	ptr.emit_signal("pressed")
	_check(t._door_busy, "the door's body opens it as the button does")
	hand.queue_free()
	t.queue_free()
	await get_tree().process_frame


func _deleted() -> void:
	# What RetroXR's Vanish has taken (the bin, the item menu's Delete, the SCENE tab) is marked, and shrinks for a few frames
	var t := _spawn()
	await get_tree().process_frame
	t.set_meta("vanishing", true)
	t.materialize()
	_check(t.state == t.State.SOLID, "being shrunk away by RetroXR: it does not land again")
	t.queue_free()
	await get_tree().process_frame
	# RetroXR's delete asks an object that has drop_and_free to do the removing: the TARDIS takes off, with its sound
	var d := _spawn()
	await get_tree().process_frame
	d.drop_and_free()
	_check(d.state == d.State.DEMATERIALIZING and (d.get_node("Sfx") as AudioStreamPlayer3D).playing and not d.is_queued_for_deletion(),
		"deleted: it takes off, with the take-off sound, and is not freed at once")
	d._on_dropped()
	await get_tree().process_frame
	_check(d.state == d.State.DEMATERIALIZING, "dropped into the bin: the take-off is not overwritten by a landing")
	# carried off to the bin and deleted there: it takes off from where it stood, not from the bin
	var home := Transform3D(Basis.IDENTITY, Vector3(4, 0, -2))
	var c := _spawn()
	await get_tree().process_frame
	c.gravity_scale = 0.0
	c.global_transform = home
	await get_tree().create_timer(1.6).timeout  # it stands there long enough to count as where it stood
	c.global_position = Vector3(-6, 1, 5)  # carried to the bin and let go of: not held now, but not for long enough to count as a rest
	await get_tree().physics_frame
	await get_tree().physics_frame
	c.drop_and_free()
	_check(c.state == c.State.DEMATERIALIZING and c.global_position.distance_to(home.origin) < 0.05, "deleted away from where it stood: it takes off from where it stood: %s" % [c.global_position])
	c.free()
	d.advance(20.0)
	_check(d.is_queued_for_deletion(), "and it is freed when it has gone")


func _states() -> void:
	var t := _spawn()
	await get_tree().process_frame
	_check(t.state == t.State.SOLID and t.enabled, "loaded, it is simply there")
	var landed: Array = []
	t.materialized.connect(func() -> void: landed.append(true))
	t.materialize()
	_check(t.state == t.State.MATERIALIZING and not t.enabled and t.freeze, "landing: it cannot be taken")
	_check(not t.remote_cell_enabled("power"), "landing: the screwdriver's power key is greyed")
	_check((t.get_node("Sfx") as AudioStreamPlayer3D).playing, "landing: the landing sound plays")
	t.advance(7.0)
	t.advance(9.0)
	_check(t.state == t.State.SOLID and t.enabled and not t.freeze and landed.size() == 1, "landed: solid, takeable")
	var solid := true
	for mi in t.find_children("*", "MeshInstance3D", false, false):
		var lit_by_door := mi.name == &"Inside" or mi.name == &"Doorway"  # drawn only while the door is open
		solid = solid and ((mi as MeshInstance3D).visible != lit_by_door) and (mi as MeshInstance3D).transparency == 0.0
	_check(solid, "landed: every part is drawn, fully, and the light behind the shut door is not")
	t.dematerialize()
	t.advance(7.5)
	var ghosts := 0
	for mi in t.find_children("*", "MeshInstance3D", false, false):
		if (mi as MeshInstance3D).visible:
			ghosts += 1
	_check(t.is_ghosted() and ghosts > 0, "half way through going: see-through, parts still drawn (%d)" % ghosts)
	t.advance(8.0)
	await get_tree().process_frame
	t = _spawn()
	await get_tree().process_frame
	var left: Array = []
	t.gone.connect(func() -> void: left.append(true))
	t.remote_activate("power")
	_check(t.state == t.State.DEMATERIALIZING, "the remote's power key sends it away")
	t.advance(20.0)
	_check(left.size() == 1 and t.is_queued_for_deletion(), "gone: it leaves the room")
	await get_tree().process_frame


## See-through while it changes: a copy of each surface's own material in alpha, behind a depth-only pass.
func _see_through() -> void:
	var t := _spawn()
	await get_tree().process_frame
	var before: Array = []
	for mi in t.find_children("*", "MeshInstance3D", false, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			before.append((mi as MeshInstance3D).get_surface_override_material(i))
	t.materialize()
	t.advance(3.5)
	var covered := 0
	var surfaces := 0
	var with_depth_pass := 0
	var inside_hidden := false
	for mi in t.find_children("*", "MeshInstance3D", false, false):
		var m := mi as MeshInstance3D
		if m.name == "Inside" or m.name == "Doorway":
			inside_hidden = (not m.visible) and (m.name == "Inside" or inside_hidden)
			continue
		if m.name == "Core":  # the dark core of the shut door is not part of the ghost: it waits for solid
			continue
		for i in m.mesh.get_surface_count():
			surfaces += 1
			var first := m.get_surface_override_material(i)
			if first is BaseMaterial3D and (first as BaseMaterial3D).next_pass != null:
				covered += 1
				var shown := (first as BaseMaterial3D).next_pass as BaseMaterial3D
				if shown != null and shown.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
						and first.render_priority < shown.render_priority and shown.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED:
					with_depth_pass += 1
	_check(t.is_ghosted() and covered == surfaces and surfaces >= 8, "see-through: every surface is dressed (%d of %d)" % [covered, surfaces])
	_check(with_depth_pass == surfaces, "see-through: each has a depth pass drawn before its blended copy (%d of %d): only the nearest surface can show" % [with_depth_pass, surfaces])
	var same := true
	var ratio := -1.0
	for fade in t._ghost_fades:
		var base := (fade["base"] as Color).a
		var now := ((fade["material"] as BaseMaterial3D).albedo_color).a
		if base > 0.0:
			var r := now / base
			ratio = r if ratio < 0.0 else ratio
			same = same and is_equal_approx(r, ratio)
	_check(t._ghost_fades.size() >= 3 and same and ratio > 0.0 and ratio < 1.0,
		"see-through: every surface is at the SAME fraction (%.2f) of its own opacity: none more present than another" % ratio)
	_check(inside_hidden, "see-through: the box behind the door waits until it is solid")
	t.advance(12.0)
	var back := true
	var k := 0
	for mi in t.find_children("*", "MeshInstance3D", false, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			back = back and (mi as MeshInstance3D).get_surface_override_material(i) == before[k]
			k += 1
	_check(not t.is_ghosted() and back and not (t.get_node("Inside") as MeshInstance3D).visible and not (t.get_node("Doorway") as MeshInstance3D).visible,
		"see-through: solid, the model's own materials are back, and the light behind the shut door does not leak")
	t.queue_free()
	await get_tree().process_frame


## The screwdriver aimed at a TARDIS from a hand's height, in a cone from its tip, sends it away.
func _pointed_at() -> void:
	_new_room()
	var t := _spawn()
	t.global_position = Vector3(0, 0, -1.7)
	var sd := (load(SCREWDRIVER_SCENE) as PackedScene).instantiate()
	add_child(sd)
	sd.freeze = true
	sd.global_position = Vector3(0, 1.3, 0)
	await _frames()
	sd.begin_use()
	sd.advance(0.1)
	sd.advance(0.7)
	_check(t.state == t.State.SOLID, "aimed at the TARDIS 0.8 s: not yet")
	sd.advance(0.6)
	_check(t.state == t.State.DEMATERIALIZING, "aimed level at its middle for 1.5 s from a hand's height: it is sent away")
	sd.end_use()
	sd.queue_free()
	t.free()
	await get_tree().process_frame


func _door() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.6, 3)
	cam.current = true
	var t := _spawn()
	await get_tree().process_frame
	var used: Array = []
	t.door_used.connect(func(pose: Transform3D) -> void: used.append(pose))
	var went: Array = []
	t.travel_handler = func() -> void: went.append(true)
	t.materialize()
	t.press_door()
	_check(used.is_empty() and t.door_degrees() == 0.0, "the door ignores a press while it lands")
	t.advance(20.0)
	t.press_door()
	await get_tree().create_timer(0.55).timeout
	_check(absf(t.door_degrees() - t.AJAR_DEGREES) < 3.0, "the door opens a crack: %.1f degrees" % t.door_degrees())
	_check((t.get_node("Inside") as MeshInstance3D).visible and (t.get_node("Doorway") as MeshInstance3D).visible, "the light behind the door shows while the door is open")
	_check(used.size() == 1 and absf((used[0] as Transform3D).origin.y - 1.6) < 0.01, "the player's place was told")
	_check(t.entry.has("pose") and (t.entry["pose"] as Transform3D).origin.is_equal_approx(cam.global_position), "and kept")
	t.press_door()
	_check(used.size() == 1, "a press while it moves is ignored")
	await get_tree().create_timer(1.1).timeout
	_check(absf(t.door_degrees()) < 0.5, "the door shuts again: %.1f degrees" % t.door_degrees())
	_check(went.size() == 1, "and the player was taken in, once")
	_check(not (t.get_node("Inside") as MeshInstance3D).visible and not (t.get_node("Doorway") as MeshInstance3D).visible, "shut, the light behind the door is gone: none leaks through the seam")
	_check((t.get_node("Core") as MeshInstance3D).visible, "shut, a dark core is in the shell: a crack at the door's edge cannot show the far wall's white")
	t.queue_free()
	cam.queue_free()
	await get_tree().process_frame


func _upright() -> void:
	_new_room()
	var t := _spawn()
	t.global_position = Vector3(0, 3, 0)
	t.rotation_degrees = Vector3(40, 30, 0)
	var start: float = t.global_basis.y.angle_to(Vector3.UP)
	await _frames(40)
	var now: float = t.global_basis.y.angle_to(Vector3.UP)
	_check(now < start * 0.5, "dropped leaning, it turns upright again: %.0f -> %.0f degrees" % [rad_to_deg(start), rad_to_deg(now)])
	var placer := t.get_node("GroundPlacement")
	_check(placer.footprint.is_equal_approx(Exteriors.entry("default")["footprint"] as Vector2), "its yellow rectangle is the size of its base")
	t.queue_free()
	await get_tree().process_frame


func _landing_spot() -> void:
	_new_room()
	await _frames()
	var space := get_viewport().world_3d.direct_space_state
	var eye := Vector3(0, 1.6, 0)
	var spot := Summon.find_spot(space, eye, Vector3(0, 0, -1), 0.0)
	_check(not spot.is_empty() and (spot["position"] as Vector3).distance_to(Vector3(0, 0, -Summon.FRONT_DISTANCE)) < 0.01,
		"room to spare: it lands straight ahead, %.1f m off: %s" % [Summon.FRONT_DISTANCE, spot.get("position")])
	_check(absf(float(spot["yaw"])) < 0.01, "and turned to face the player")
	_block(4, Vector3(1.0, 1.0, 1.0), Vector3(0, 0.5, -Summon.FRONT_DISTANCE))
	await _frames()
	var moved := Summon.find_spot(space, eye, Vector3(0, 0, -1), 0.0)
	var p: Vector3 = moved["position"]
	_check(not moved.is_empty() and Vector2(p.x, p.z).distance_to(Vector2(0, -Summon.FRONT_DISTANCE)) > 1.0, "something in the way: it lands elsewhere: %s" % [p])
	_check(Vector2(p.x, p.z).length() <= Summon.SEARCH_RADIUS and p.y == 0.0, "still on the floor, in reach")
	_block(1, Vector3(40, 3, 0.4), Vector3(0, 1.5, -1.9))
	await _frames()
	var walled := Summon.find_spot(space, eye, Vector3(0, 0, -1), 0.0)
	_check(not walled.is_empty() and (walled["position"] as Vector3).z > -1.9, "a wall ahead: it does not land behind it: %s" % [walled.get("position")])
	_new_room()
	_block(1, Vector3(40, 0.2, 40), Vector3(0, 1.0, 0))
	await _frames()
	_check(Summon.find_spot(space, Vector3(0, 0.9, 0), Vector3(0, 0, -1), 0.0).is_empty(), "no room at all (a ceiling at 1 m): no spot")
	_new_room(false)
	await _frames()
	_check(Summon.find_spot(space, eye, Vector3(0, 0, -1), 0.0).is_empty(), "no floor (outside the map): no spot")


func _screwdriver_calls_it() -> void:
	_new_room()
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.6, 0)
	cam.current = true
	var sd := (load(SCREWDRIVER_SCENE) as PackedScene).instantiate()
	add_child(sd)
	sd.freeze = true
	sd.global_position = Vector3(0.2, 1.2, -0.3)
	await _frames()
	var made: Array = []
	sd.summoned.connect(func(t: Node3D) -> void: made.append(t))
	sd.begin_use()
	sd.advance(0.1)
	sd.advance(0.7)
	_check(made.is_empty(), "held 0.8 s on nothing: not yet")
	sd.advance(0.6)
	_check(made.size() == 1, "held 1.4 s on nothing: the TARDIS is called")
	var t: Node3D = made[0]
	_check(t.get_meta(&"mod_object_type", "") == "xenu.tardis:tardis" and t.is_in_group("spawned"),
		"the TARDIS it called is saved like a cabinet until it is sent away")
	_check(t.global_position.distance_to(Vector3(0, 0, -Summon.FRONT_DISTANCE)) < 0.01 and t.state == t.State.MATERIALIZING,
		"it lands %.1f m ahead of the player, materialising: %s" % [Summon.FRONT_DISTANCE, t.global_position])
	sd.advance(5.0)
	_check(made.size() == 1, "held on: not called twice")
	sd.end_use()
	sd.begin_use()
	sd.advance(0.1)
	sd.advance(2.0)
	_check(made.size() == 1 and get_tree().get_nodes_in_group(&"xenu_tardis").size() == 1, "one TARDIS to a room")
	t.free()
	sd.end_use()
	sd.queue_free()
	cam.queue_free()
	await get_tree().process_frame


func _no_room() -> void:
	_new_room()
	_block(1, Vector3(40, 0.2, 40), Vector3(0, 1.0, 0))
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 0.9, 0)
	cam.current = true
	var sd := (load(SCREWDRIVER_SCENE) as PackedScene).instantiate()
	add_child(sd)
	sd.freeze = true
	sd.global_position = Vector3(0, 0.8, -0.3)
	await _frames()
	var made: Array = []
	sd.summoned.connect(func(t: Node3D) -> void: made.append(t))
	sd.begin_use()
	sd.advance(0.1)
	sd.advance(2.0)
	_check(made.is_empty() and get_tree().get_nodes_in_group(&"xenu_tardis").is_empty(), "no room: nothing lands")
	var failed := get_tree().current_scene.find_child("TardisFailed", true, false)
	if failed == null:
		failed = find_child("TardisFailed", true, false)
	_check(failed != null, "no room: the landing sound starts and is cut off by the distortion")
	var landing_p := failed.get_node("Landing") as AudioStreamPlayer3D
	var fizzle_p := failed.get_node("Fizzle") as AudioStreamPlayer3D
	_check(landing_p.playing and not fizzle_p.playing, "no room: the landing sound has begun, the fizzle has not")
	await get_tree().create_timer(Summon.FAIL_CUT_SECONDS + 0.3).timeout
	_check(not landing_p.playing and fizzle_p.playing, "no room: then a fizzle cuts the landing sound off")
	_check(Summon.distortion().data.size() > 10000, "the fizzle is a sound of its own")
	sd.end_use()
	sd.queue_free()
	cam.queue_free()
	await get_tree().process_frame
