## Suite for the sonic screwdriver: no room, headset or controller needed.
##
##   godot --headless --path RetroXR res://mods/xenu.tardis/tests/screwdriver_tests.tscn
##
## A SCENE and not a `--script` SceneTree, on purpose: the screwdriver extends XRToolsPickable,
## whose dependencies are autoloads (QualityManager, XRToolsUserSettings...), and a `--script` run
## has none. There the script FAILS TO COMPILE, every spawn is a bare RigidBody3D and a suite that
## does not look would still print "0 failed". Hence `_spawn` checks the script really loaded.
##
## Prints `[tardis-tests] N cases, M failed` and exits non-zero on a failure OR when it ran zero
## cases, so a script that does not compile cannot pass.
extends Node

const Models := preload("res://mods/xenu.tardis/scripts/screwdriver_models.gd")
const SCENE := "res://mods/xenu.tardis/scenes/sonic_screwdriver.tscn"
## The Quest 3 draws this with the rest of a room: a toy this long has no business over this.
const MAX_TRIS := 6000
## Cases a complete run makes. A function that dies half way (a script error aborts it) would
## still print `0 failed`, so a short count fails the run.
## The base cases, and what each model adds (see _every_model).
const BASE_CASES := 56
const PER_MODEL_CASES := 9
var EXPECTED_CASES := BASE_CASES + PER_MODEL_CASES * Models.MODELS.size()

var _cases := 0
var _failed := 0


func _ready() -> void:
	_manifest()
	_models_table()
	await _registration()
	await _spawn_default()
	await _spawn_unknown_variant()
	await _use_cycle()
	await _drop_while_humming()
	await _every_model()
	await _two_screwdrivers_light_alone()
	await _remote_control()
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
	var scene := load(SCENE) as PackedScene
	var node := scene.instantiate()
	add_child(node)
	_check(node.has_method("begin_use"), "the screwdriver's script compiled and is attached")
	return node


func _manifest() -> void:
	var m := JSON.parse_string(FileAccess.get_file_as_string("res://mods/xenu.tardis/mod.json")) as Dictionary
	_check(m != null and m.get("id") == "xenu.tardis", "mod.json id")
	_check(str(m.get("entry", "")) == "res://mods/xenu.tardis/mod_main.gd", "mod.json entry")
	_check(int(m.get("api_version", 0)) == 1, "mod.json api_version")
	_check(m.get("claims", ["x"]) == [], "mod claims nothing outside its folder")
	_check(str(m.get("description", "")).contains("Shift + click") and str(m.get("description", "")).contains("trigger"),
		"the mod's description tells how to use the screwdriver on a desktop and in a headset")


func _models_table() -> void:
	_check(Models.resolve_id("") == "10", "no id is the 10th Doctor's")
	_check(Models.resolve_id("nope") == "10", "unknown id falls back to the 10th Doctor's")
	_check(Models.variant_rows()[0]["id"] == "10", "the default is the first swatch")
	_check(Models.TYPE == "xenu.tardis:sonic_screwdriver" and Models.SCENE == SCENE, "the one screwdriver keeps the type the mod started with")
	var rows_ok := Models.variant_rows().size() == Models.MODELS.size()
	for row: Dictionary in Models.variant_rows():
		rows_ok = rows_ok and row.has("id") and str(row["label"]).length() > 0 and row["color"] is Color and Models.MODELS.has(row["id"])
	_check(rows_ok, "the picker offers every Doctor, each with an id, a label and a colour")
	for id: String in Models.MODELS:
		var bytes := FileAccess.get_file_as_bytes(Models.glb_of(id))
		_check(not bytes.is_empty(), "GLB of %s is readable" % id)


func _spawn_default() -> void:
	var sd := _spawn()
	await get_tree().process_frame
	_check(sd.model_id == "10", "default model id")
	var meshes := sd.find_children("*", "MeshInstance3D", false, false)
	_check(meshes.size() >= 2, "meshes are direct children (the highlight looks there): %d" % meshes.size())
	var tris := 0
	for m: Node in meshes:
		var mesh := (m as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_check(tris > 0 and tris <= MAX_TRIS, "triangle budget: %d <= %d" % [tris, MAX_TRIS])
	_check(sd.find_child("Led", false, false) is MeshInstance3D, "the LED mesh is there")
	var aabb := AABB()
	for m: Node in meshes:
		aabb = aabb.merge((m as MeshInstance3D).get_aabb()) if aabb.size != Vector3.ZERO else (m as MeshInstance3D).get_aabb()
	_check(absf(aabb.size.z - 0.17) < 0.01, "17 cm long, along Z: %.3f" % aabb.size.z)
	_check(aabb.position.z < -0.09 and aabb.end.z > 0.05, "grip at the origin, tip at -Z: %s" % aabb)
	_check(sd.get_node("Hum").stream != null, "the hum is loaded")
	_check(not sd.is_active(), "off at spawn")
	var hint := sd.get_node_or_null("HeldHint")
	var rows: Array = hint.get("_rows") if hint != null else []
	var by_id := {}
	for r: Array in rows:
		by_id[r[0]] = r
	var desk: Array = by_id.get(&"sonic_use_desktop", [])
	var vr: Array = by_id.get(&"sonic_use_vr", [])
	_check(not desk.is_empty() and desk[2] == ["keyboard_shift_outline", "mouse_left_outline"] and int(desk[1]) == HeldHint.PLATFORM_DESKTOP,
		"the hint over a held screwdriver says Shift + click on a desktop")
	_check(not vr.is_empty() and (vr[2] as Array)[0] == "quest_button_{ax}_outline" and int(vr[1]) == HeldHint.PLATFORM_VR and str(vr[3]).contains("trigger")
		and by_id.has(&"sonic_remote_desktop") and by_id.has(&"sonic_remote_vr"),
		"and the A / X button or the trigger in a headset, and what it does aimed at something")
	sd.queue_free()
	await get_tree().process_frame


func _spawn_unknown_variant() -> void:
	var scene := load(SCENE) as PackedScene
	var node := scene.instantiate()
	node.set_meta(&"model_variant", "from-the-future")
	add_child(node)
	await get_tree().process_frame
	_check(node.model_id == "10", "an unknown variant wears the default")
	node.queue_free()
	await get_tree().process_frame


func _led_energy(sd: Node) -> float:
	var led := sd.find_child("Led", false, false) as MeshInstance3D
	var mat := led.get_surface_override_material(0) as StandardMaterial3D
	return mat.emission_energy_multiplier if mat != null and mat.emission_enabled else -1.0


func _use_cycle() -> void:
	var sd := _spawn()
	await get_tree().process_frame
	var hum := sd.get_node("Hum") as AudioStreamPlayer3D
	var seen: Array = []
	sd.activation_changed.connect(func(on: bool) -> void: seen.append(on))
	_check(_led_energy(sd) == 0.0, "LED dark while off")
	sd.begin_use()
	_check(sd.is_active() and hum.playing, "pressed: active and humming")
	_check(_led_energy(sd) > 1.0, "pressed: LED lit (%s)" % _led_energy(sd))
	sd.begin_use()
	_check(seen == [true], "a second press says nothing new")
	sd.end_use()
	_check(not sd.is_active() and not hum.playing, "released: silent")
	_check(_led_energy(sd) == 0.0, "released: LED dark")
	_check(seen == [true, false], "told on and off once each: %s" % [seen])
	# What a trigger does, through the pickable's own signals.
	sd.action_pressed.emit(sd)
	_check(sd.is_active(), "trigger press (action_pressed) starts it")
	sd.action_released.emit(sd)
	_check(not sd.is_active(), "trigger release stops it")
	sd.queue_free()
	await get_tree().process_frame


func _drop_while_humming() -> void:
	var sd := _spawn()
	await get_tree().process_frame
	sd.begin_use()
	sd.dropped.emit(sd)
	_check(not sd.is_active() and not (sd.get_node("Hum") as AudioStreamPlayer3D).playing,
		"put down while humming: stops")
	sd.queue_free()
	await get_tree().process_frame


func _two_screwdrivers_light_alone() -> void:
	var a := _spawn()
	var b := _spawn()
	await get_tree().process_frame
	a.begin_use()
	_check(_led_energy(a) > 1.0 and _led_energy(b) == 0.0, "one screwdriver's light is not the other's")
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


## Registration is NOT driven here: ModApi, SpawnCatalog and ScenePersistence do not compile where the
## game's native extensions cannot load (a Linux host with an old glibc), and a call into them aborts
## the function silently. What is checked is the text of mod_main.gd; the real thing is checked by
## enabling the mod in RetroXR (MODS tab) and looking for "Sonic Screwdriver" on SPAWN > Objects.
func _registration() -> void:
	var src := FileAccess.get_file_as_string("res://mods/xenu.tardis/mod_main.gd")
	_check(src.contains("api.register_object(Models.TYPE, Models.SCENE,"), "mod_main.gd registers the one screwdriver")
	_check(src.contains('"variants": Models.variant_rows()'), "its Doctors are its colours (hold the row to choose)")
	_check(src.contains('"label": Models.LABEL') and Models.LABEL == "Sonic Screwdriver", "its row is called just Sonic Screwdriver (else it is not on the menu, or has a long name)")


## A device placed `dist` metres in front of the screwdriver's tip (its -Z), on the pointable layer.
func _device(sd: Node3D, dist: float) -> Node3D:
	var d := (load("res://mods/xenu.tardis/tests/fake_remote_device.gd") as GDScript).new() as Node3D
	add_child(d)
	d.global_position = sd.global_position + Vector3(0, 0, -dist)
	return d


func _physics_settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


## The screwdriver as a remote: held on a device for 1.5 s, it presses its power key once.
func _remote_control() -> void:
	var sd := _spawn()
	sd.freeze = true
	sd.global_position = Vector3(0, 0, 0)
	var dev := _device(sd, 2.0)
	var fired: Array = []
	sd.remote_fired.connect(func(d: Node3D) -> void: fired.append(d))
	# Held on nothing it calls the TARDIS: not here (tardis_tests.gd does that for real).
	var calls: Array = []
	sd.summon_handler = func() -> void: calls.append(true)
	await _physics_settle()

	# Not on: nothing aims, nothing is switched.
	sd.advance(5.0)
	_check(dev.presses.is_empty() and dev.outlined == null, "off: it does not touch what it points at")

	sd.begin_use()
	sd.advance(0.1)
	_check(dev.outlined == true, "on, pointing at a device: it wears the remote's outline")
	sd.advance(1.0)
	_check(dev.presses.is_empty(), "1.1 s on it: not yet (the effect is not instant)")
	sd.advance(0.5)
	_check(dev.presses == ["power"] and fired == [dev], "1.6 s on it: power pressed once: %s" % [dev.presses])
	sd.advance(5.0)
	_check(dev.presses.size() == 1, "kept down: still once, not a flicker")
	sd.end_use()
	_check(dev.outlined == false, "let go: the outline goes")
	sd.begin_use()
	sd.advance(1.6)
	_check(dev.presses.size() == 2, "pressed again: it switches again (on, then off)")
	sd.end_use()

	# A break in the aim starts the count again.
	dev.presses.clear()
	sd.begin_use()
	sd.advance(1.0)
	sd.rotation_degrees = Vector3(0, 90, 0)
	await _physics_settle()
	sd.advance(0.2)
	_check(dev.outlined == false, "pointed away: the outline goes")
	sd.rotation_degrees = Vector3.ZERO
	await _physics_settle()
	sd.advance(1.0)
	_check(dev.presses.is_empty(), "1.0 s, a break, 1.0 s: the break reset the count")
	sd.advance(0.6)
	_check(dev.presses.size() == 1, "1.6 s unbroken after it: pressed")
	sd.end_use()

	# What it cannot switch.
	dev.presses.clear()
	dev.power_enabled = false
	sd.begin_use()
	sd.advance(0.1)
	sd.advance(2.0)
	_check(dev.presses.is_empty() and fired.size() == 3, "a power key that is greyed out is not pressed")
	sd.end_use()
	dev.power_enabled = true
	dev.cells = [{"id": "vol_up", "glyph": "vol_up", "col": 0, "row": 0}]
	sd.begin_use()
	sd.advance(0.1)
	sd.advance(2.0)
	_check(dev.presses.is_empty(), "a device with no power key is left alone")
	sd.end_use()
	dev.cells = [{"id": "power", "glyph": "power", "col": 0, "row": 0, "span": 3}]

	# A wall between: it is not aimed at.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.1)
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = Vector3(0, 0, -1.0)
	await _physics_settle()
	sd.begin_use()
	sd.advance(0.1)
	sd.advance(2.0)
	_check(dev.presses.is_empty() and dev.outlined == false, "behind a wall: not aimed at")
	sd.end_use()
	wall.free()

	# Too far.
	dev.global_position = Vector3(0, 0, -(sd.TARGET_RANGE + 2.0))
	await _physics_settle()
	sd.begin_use()
	sd.advance(0.1)
	sd.advance(2.0)
	_check(dev.presses.is_empty(), "out of range: not aimed at")
	sd.end_use()

	# Nothing in the cone: using it alone does nothing but hum, and calls the TARDIS.
	dev.queue_free()
	await get_tree().process_frame
	calls.clear()
	sd.begin_use()
	sd.advance(3.0)
	_check(sd.is_active() and fired.size() == 3 and calls.size() == 1, "pointing at nothing for 3 s: it hums, and calls the TARDIS once")
	sd.end_use()
	sd.queue_free()
	await get_tree().process_frame


## Every Doctor's screwdriver, spawned from its own scene: the right model, inside the budget, the
## same frame (about 17 cm, the tip toward -Z, the grip at the origin), a LED where the table says.
func _every_model() -> void:
	for id: String in Models.ids():
		var scene := load(SCENE) as PackedScene
		_check(scene != null, "%s: its scene loads" % id)
		var sd := scene.instantiate()
		# what the SPAWN menu does for a colour: the id, given before it enters the room
		sd.set_meta(&"model_variant", id)
		add_child(sd)
		await get_tree().process_frame
		_check(sd.model_id == id, "%s: it wears its own model (%s)" % [id, sd.model_id])
		var meshes := sd.find_children("*", "MeshInstance3D", false, false)
		var tris := 0
		var aabb := AABB()
		var first := true
		for m: Node in meshes:
			var mi := m as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			aabb = mi.get_aabb() if first else aabb.merge(mi.get_aabb())
			first = false
		_check(tris > 0 and tris <= MAX_TRIS, "%s: triangle budget %d <= %d" % [id, tris, MAX_TRIS])
		_check(meshes.size() <= 8, "%s: few draw calls (%d meshes)" % [id, meshes.size()])
		_check(aabb.size.z > 0.10 and aabb.size.z < 0.21, "%s: a hand-sized length: %.3f m" % [id, aabb.size.z])
		_check(-aabb.position.z > aabb.end.z, "%s: the tip is toward -Z (%s)" % [id, aabb])
		var has_led := sd.find_child("Led", false, false) != null
		_check(has_led == bool(Models.MODELS[id]["led"]), "%s: a Led mesh exactly when the table says" % id)
		sd.begin_use()
		_check(sd.is_active() and (not has_led or _led_energy(sd) > 1.0), "%s: it hums, and lights if it can" % id)
		sd.end_use()
		sd.queue_free()
		await get_tree().process_frame
