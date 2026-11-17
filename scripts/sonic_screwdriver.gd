## SonicScrewdriver -- the Doctor's sonic screwdriver, a pickable you hold in your hand.
##
## While it is held, pressing A (X on the left hand) -- or the trigger, or Shift + click on a
## desktop, which is what RetroXR calls "using" a prop -- makes it hum for as long as the
## button is down, and lights its LED if the model has one in the show's canon. Letting go
## stops both. Putting it down while it hums stops it too.
##
## Held for the same time on NOTHING (no device in the cone) it calls the TARDIS into the room, if there
## is not one already (TardisSummon: in front of the player if there is room, else the nearest spot).
## In a console room it does nothing.
##
## It is also a remote control. Held down while its tip points at something RetroXR's TV remote could
## drive (anything in the `remote_target` group, see RemoteTarget: a TV, a VCR, a console deck, a
## mod's device) for TARGET_HOLD seconds without a break, it presses that device's POWER cell, once
## per press: it switches the device on or off. The effect is not instant on purpose. The tip is
## found as the remote finds it: a cone from the tip in VR, the crosshair on a desktop. While it
## aims at a device that device wears the remote's maroon outline.
##
## The model is a GLB read from the mod's files at run time (GLTFDocument), not an imported
## resource: a mod pack made by pack_mod.gd carries source files only, and nothing imported
## exists inside one. The sound is read the same way. Both are cached across spawns.
##
## The meshes are made direct children of this node, because PickableHighlight only outlines
## what it finds there (it looks again after this _ready, deferred).
##
## What it tells the player: RetroXR floats a hint over a held object (HeldHint) with the verbs that are not
## obvious. Using the screwdriver is one of them, and it is not the same on a desktop (Shift + left click, held:
## what RetroXR calls "using" a held prop, DesktopPickup) as in a headset (A, X on the left hand, or the trigger).
##
## Which Doctor's it is: the `model_variant` metadata the SPAWN menu (or a save slot) gave it before it
## entered the room (RetroXR keeps and saves it as the object's "colour"). None, or an id this version
## does not know, is the 10th Doctor's.
extends XRToolsPickable

const Models := preload("res://mods/xenu.tardis/scripts/screwdriver_models.gd")
const Assets := preload("res://mods/xenu.tardis/scripts/mod_assets.gd")
const Summon := preload("res://mods/xenu.tardis/scripts/tardis_summon.gd")
const Travel := preload("res://mods/xenu.tardis/scripts/tardis_travel.gd")

## The hum, read from here. 3 seconds of it, looped for as long as the button is down.
const SOUND_PATH := "res://mods/xenu.tardis/assets/audio/screwdriver.mp3"
## How bright the LED glows when it is on. Emission is HDR: above 1 it blooms where the room
## has glow on.
const LED_ENERGY_ON := 4.0
## A LED whose material is see-through (a glass section) is made this opaque when lit: a blended
## material scales its glow by its alpha, so left at ~0.17 it would not show. An opaque LED (the
## 10th Doctor's emitter dome) is not touched this way.
const LED_ALPHA_ON := 0.75
## How long it must stay on a device, with the button down, before it switches it (was 1.5 s: 40% less).
const TARGET_HOLD := 0.9
## The cone a device must be inside to be aimed at (half-angle, degrees) and the reach, as the TV remote's.
const TARGET_CONE_DEG := 20.0
const TARGET_RANGE := 8.0
## The cell of a device's remote layout it presses: the shared id of its power key.
const POWER_CELL := "power"
## Where its business end is, in its own frame (the model's tip is at -Z).
const TIP := Vector3(0, 0, -0.105)
## Physics layer 21 (index 20): the PointerArea bodies. Layer 1 is the room's walls.
const POINTABLE_MASK := 1 << 20
const WORLD_MASK := 1 << 0
## The ids of the hint's rows (what HeldHint counts as learned).
const USE_DESKTOP := &"sonic_use_desktop"
const USE_VR := &"sonic_use_vr"
const REMOTE_DESKTOP := &"sonic_remote_desktop"
const REMOTE_VR := &"sonic_remote_vr"
## A button on the holding hand's controller counts as pressed past this.
const BUTTON_THRESHOLD := 0.5

## Told when the screwdriver starts or stops sounding (true = starts).
signal activation_changed(on: bool)
## Told when it switched a device (the device, true if it was found and pressed).
signal remote_fired(device: Node3D)
## Told when it called a TARDIS (the one it made).
signal summoned(tardis: Node3D)

## What it does to call the TARDIS; empty is TardisSummon.summon. The tests put their own here.
var summon_handler := Callable()

## Which model it wears (a key of Models.MODELS), after the fallback to the default.
var model_id := Models.DEFAULT_ID

var _active := false
var _trigger_down := false
## What the object's menu titles itself (ObjectOptionsPanel reads `display_name`; without it, the node's name: "SonicScrewdriver").
var display_name := "Sonic Screwdriver"
var _model: Node3D = null
## The meshes the model put on this node: what a change of Doctor takes off again.
var _model_meshes: Array[MeshInstance3D] = []
var _hint: HeldHint = null
var _led: MeshInstance3D = null
var _led_mat: StandardMaterial3D = null
var _led_off_color := Color.WHITE
var _led_on_color := Color.WHITE
var _sound: AudioStreamPlayer3D = null
var _aimed: Node3D = null
var _logged_hold := false
var _aim_time := 0.0
var _fired := false


func _ready() -> void:
	super()
	model_id = Models.resolve_id(str(get_meta(&"model_variant", "")))
	_build_model()
	_build_sound()
	action_pressed.connect(_on_action_pressed)
	action_released.connect(_on_action_released)
	dropped.connect(_on_dropped)
	_teach_verbs()
	set_process(false)
	picked_up.connect(func(_p: Variant) -> void: set_process(true))
	# the object's menu is made on its first press, whenever that is: its meshes must never reach the outline
	child_entered_tree.connect(func(c: Node) -> void:
		if c.name == &"ObjectOptionsPanel":
			_keep_menu_out_of_outline.call_deferred())


## The rows of the hint over it: how to use it, and what it does aimed at something, on each platform.
func _teach_verbs() -> void:
	_hint = HeldHint.for_node(self)
	if _hint == null:
		return
	var vr_use: Array = ["quest_button_{ax}_outline"]
	_hint.add_row(USE_DESKTOP, HeldHint.PLATFORM_DESKTOP, ["keyboard_shift_outline", "mouse_left_outline"],
		"Hold {g} to use it: it hums and lights up", HeldHint.WHEN_HELD)
	_hint.add_row(USE_VR, HeldHint.PLATFORM_VR, vr_use, "Hold {g}, or the trigger, to use it: it hums and lights up", HeldHint.WHEN_HELD)
	_hint.add_row(REMOTE_DESKTOP, HeldHint.PLATFORM_DESKTOP, ["keyboard_shift_outline", "mouse_left_outline"],
		"Hold {g} for a second on a device or the TARDIS to switch it, on nothing to call the TARDIS", HeldHint.WHEN_HELD)
	_hint.add_row(REMOTE_VR, HeldHint.PLATFORM_VR, vr_use,
		"Hold {g} for a second on a device or the TARDIS to switch it, on nothing to call the TARDIS", HeldHint.WHEN_HELD)


## The verb was used: HeldHint stops showing a row that has been learned.
func _note_used(remote: bool) -> void:
	if _hint == null:
		return
	var by := get_picked_up_by()
	var desktop := by != null and by.is_in_group("desktop_hand")
	_hint.note_used((REMOTE_DESKTOP if desktop else REMOTE_VR) if remote else (USE_DESKTOP if desktop else USE_VR))


## True while it is humming.
func is_active() -> bool:
	return _active


## Press / release by hand of the program: what the trigger and the A button do. The tests call
## these; so can anything that wants the screwdriver to sound without a controller.
func begin_use() -> void:
	_set_active(true)


func end_use() -> void:
	_set_active(false)


func _process(delta: float) -> void:
	if not is_picked_up():
		return
	var ctrl := get_picked_up_by_controller()
	if ctrl != null and not _logged_hold:
		# said once a hold, so that a report from a headset says how the screwdriver sits in the hand
		_logged_hold = true
		print("[xenu.tardis] screwdriver held in a headset: its tip is %.0f degrees off the hand's forward" % rad_to_deg((-global_transform.basis.z).angle_to(-ctrl.global_transform.basis.z)))
	var a_down := ctrl != null and ctrl.get_float("ax_button") > BUTTON_THRESHOLD
	_set_active(_trigger_down or a_down)
	advance(delta)


## One step of the remote part: find what the tip points at (whenever it is held, so the device wears the remote's
## outline as soon as it is aimed at, not only while the button is down), and, with the button down, switch it once it
## has been aimed at for TARGET_HOLD seconds. _process calls it; the tests call it with the time they want.
func advance(delta: float) -> void:
	var device := _scan_target()
	if device != _aimed:
		_set_aimed(device)
		_aim_time = 0.0
		_fired = false
	if not _active:
		_aim_time = 0.0  # the hold counts from the press, without a break
		_fired = false
		return
	if _fired:
		return
	_aim_time += delta
	if _aim_time < TARGET_HOLD:
		return
	_fired = true
	_note_used(true)
	if device != null:
		if _press_power(device):
			remote_fired.emit(device)
	else:
		_call_tardis()


## Held on nothing for long enough: call the TARDIS (once: there is one TARDIS in a room).
func _call_tardis() -> void:
	# a console room is inside the TARDIS: there is nothing to call, and nothing happens
	if Travel.in_console_room(Travel.manager_of(self)):
		return
	if summon_handler.is_valid():
		summon_handler.call()
		return
	var tardis := Summon.summon(self)
	if tardis != null:
		summoned.emit(tardis)


func _on_action_pressed(_p: Variant) -> void:
	_trigger_down = true
	_set_active(true)


func _on_action_released(_p: Variant) -> void:
	_trigger_down = false
	if not _a_held():
		_set_active(false)


func _on_dropped(_p: Variant) -> void:
	_logged_hold = false
	_trigger_down = false
	set_process(false)
	_set_active(false)
	_set_aimed(null)  # put down, it aims at nothing


func _a_held() -> bool:
	var ctrl := get_picked_up_by_controller()
	return ctrl != null and ctrl.get_float("ax_button") > BUTTON_THRESHOLD


func _set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if on:
		_note_used(false)
	if _sound != null:
		if on:
			_sound.play()
		else:
			_sound.stop()
	_apply_led(on)
	if not on:
		_aim_time = 0.0
		_fired = false
	activation_changed.emit(on)


# ── the remote ────────────────────────────────────────────────────────────────

## Press the device's power key through its own remote layout, the way the TV remote does (RemoteTarget
## is the game's contract: what its own button does, so a save and netplay hear of it). False when
## it has no power key, or it is greyed out now.
func _press_power(device: Node3D) -> bool:
	for cell: Variant in RemoteTarget.layout(device):
		if str((cell as Dictionary).get("id", "")) == POWER_CELL:
			if not RemoteTarget.cell_enabled(device, POWER_CELL):
				return false
			RemoteTarget.activate(device, POWER_CELL)
			return true
	return false


## The maroon outline the remote gives what it aims at.
func _set_aimed(device: Node3D) -> void:
	if is_instance_valid(_aimed):
		_highlight(_aimed, false)
	_aimed = device
	if device != null:
		_highlight(device, true)


static func _highlight(device: Node3D, on: bool) -> void:
	var hl := device.find_child("PickableHighlight", false, false)
	if hl != null and hl.has_method("set_remote_target"):
		hl.call("set_remote_target", on)


## What the tip points at: on a desktop the crosshair's ray (a mouse has no hand to aim with), in VR
## a cone from the tip, as the TV remote does.
func _scan_target() -> Node3D:
	var by := get_picked_up_by()
	if by != null and by.is_in_group("desktop_hand"):
		var cam := get_viewport().get_camera_3d()
		if not is_instance_valid(cam):
			return null
		return _ray_device(cam.global_position, -cam.global_transform.basis.z)
	var tip := global_transform * TIP
	var found := _cone_device(tip, -global_transform.basis.z)
	if found != null:
		return found
	# Held across the fist (a pickable with no grab point stays as it was taken), the tip does not point where the hand does: the
	# hand's own forward, from the hand, is tried next, as the laser would aim
	var hand: Variant = _hand_aim()
	if hand is Transform3D:
		return _cone_device((hand as Transform3D).origin, -(hand as Transform3D).basis.z)
	return null


## The holding controller's pose in the world (a Transform3D), or null when there is none. Test seam: `hand_aim`.
var hand_aim := Callable()


func _hand_aim() -> Variant:
	if hand_aim.is_valid():
		return hand_aim.call()
	var ctrl := get_picked_up_by_controller()
	return ctrl.global_transform if ctrl != null else null


func _own_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	var pointer := get_node_or_null("PointerArea") as CollisionObject3D
	if pointer != null:
		rids.append(pointer.get_rid())
	return rids


func _ray_device(from: Vector3, dir: Vector3) -> Node3D:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * TARGET_RANGE)
	q.collision_mask = POINTABLE_MASK
	q.exclude = _own_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return null if hit.is_empty() else RemoteTarget.of(hit["collider"] as Node)


## The device nearest the cone's centre, in range, with a clear line to it. This is TVRemote._cone_pick as RetroXR has it
## now: the devices are walked off RemoteTarget's group (a sphere query returns at most so many shapes, and every key in a
## room is on the pointable layer, so a device past the cap was never seen), aimed at their IR window when they name one
## (RemoteTarget.receiver; a remote behind that window's face does not reach it), else at their pointable bodies.
func _cone_device(from: Vector3, dir: Vector3) -> Node3D:
	var min_dp := cos(deg_to_rad(TARGET_CONE_DEG))
	var near: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(RemoteTarget.GROUP):
		var dev := node as Node3D
		if dev == null or not dev.is_inside_tree() or not RemoteTarget.is_target(dev) or dev.is_ancestor_of(self):
			continue
		var pts: Array[Vector3] = []
		var rx: Variant = RemoteTarget.receiver(dev)
		if rx is Transform3D:
			var window := rx as Transform3D
			if window.basis.z.dot(from - window.origin) <= 0.0:
				continue  # behind its window: the cabinet is between the two
			pts.append(window.origin)
		else:
			for body: CollisionObject3D in _pointables(dev):
				pts.append(body.global_position)
		var best := {}
		for pt: Vector3 in pts:
			var to := pt - from
			var dist := to.length()
			if dist > TARGET_RANGE or dist < 0.0001:
				continue
			var dp := dir.dot(to / dist)
			if dp >= min_dp and (best.is_empty() or dp > float(best["dp"])):
				best = {"dev": dev, "pt": pt, "dp": dp}
		if not best.is_empty():
			near.append(best)
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dp"]) > float(b["dp"]))
	for c: Dictionary in near:
		if not _occluded(from, c["pt"]):
			return c["dev"]
	return null


## A device's own bodies on the pointable layer (21), not a nested device's: what the remote aims at on a device that
## names no IR receiver. Asked every frame a screwdriver is held, so the walk is not repeated for POINTABLES_TTL_MS.
const POINTABLES_META := &"_remote_pointables"
const POINTABLES_TTL_MS := 2000

static func _pointables(dev: Node3D) -> Array:
	var now := Time.get_ticks_msec()
	if dev.has_meta(POINTABLES_META):
		var kept: Array = dev.get_meta(POINTABLES_META)
		if now - int(kept[0]) < POINTABLES_TTL_MS:
			return (kept[1] as Array).filter(func(b: Variant) -> bool:
				return is_instance_valid(b) and (b as Node).is_inside_tree())
	var found: Array = []
	var bodies: Array[Node] = dev.find_children("*", "CollisionObject3D", true, false)
	if dev is CollisionObject3D:
		bodies.append(dev)
	for n: Node in bodies:
		var body := n as CollisionObject3D
		if body.collision_layer & POINTABLE_MASK and RemoteTarget.of(body) == dev:
			found.append(body)
	dev.set_meta(POINTABLES_META, [now, found])
	return found


func _occluded(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = WORLD_MASK
	q.exclude = _own_rids()
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ── model ─────────────────────────────────────────────────────────────────────

func _build_model() -> void:
	var row := Models.entry(model_id)
	_model = Assets.instance_glb(Models.glb_of(model_id))
	if _model == null:
		push_warning("[xenu.tardis] cannot read %s: the screwdriver has no model" % Models.glb_of(model_id))
		return
	var adopted := Assets.adopt_meshes(_model, self)
	for mesh: Variant in adopted.values():
		_model_meshes.append(mesh as MeshInstance3D)
	_model = null
	_apply_look(row)
	if bool(row["led"]):
		_led = find_child("Led", false, false) as MeshInstance3D
		if _led != null:
			_prepare_led(row["led_color"] as Color)


# ── which Doctor's it is, changed in the game ─────────────────────────────────

## Wear `id`'s model now (an id this version does not know is the default's). The id is kept as `model_variant`
## metadata, which is what RetroXR saves with the object, so a save slot brings the Doctor back. The LED follows
## the new model, lit if the screwdriver is humming.
func set_model(id: String) -> void:
	id = Models.resolve_id(id)
	if id == model_id and not _model_meshes.is_empty():
		return
	for mi: MeshInstance3D in _model_meshes:
		if is_instance_valid(mi):
			remove_child(mi)
			mi.queue_free()
	_model_meshes.clear()
	_led = null
	_led_mat = null
	model_id = id
	set_meta(&"model_variant", id)
	_build_model()
	_apply_led(_active)
	var kept_out := _keep_menu_out_of_outline()
	var highlight := find_child("PickableHighlight", false, false)
	if highlight != null and highlight.has_method("rebuild_overlays"):
		highlight.call("rebuild_overlays")
	print("[xenu.tardis] screwdriver is now the %s (%d of its menu's meshes kept out of the outline)" % [Models.entry(id)["label"], kept_out])


## The outline is drawn from every mesh under this node, and the object's menu is a child of it (its page and its resize
## grip are meshes): outlined, they were counted in the menu's own "how tall is the object under me" measure, which then
## lifted the menu a little more every frame it was up, out of sight in about a second. The menu's meshes are left out of
## the outline (RetroXR's `outline_exclude`). Returns how many.
func _keep_menu_out_of_outline() -> int:
	var kept_out := 0
	for panel: Node in find_children("ObjectOptionsPanel", "Node3D", false, false):
		for mesh: Node in panel.find_children("*", "MeshInstance3D", true, false):
			mesh.add_to_group(&"outline_exclude")
			kept_out += 1
	return kept_out


## The object's own menu (RetroXR's ObjectOptionsPanel: point at it and press the left thumbstick in a headset, Tab on a
## desktop) lists the Doctors: the SPAWN menu offers a mod's object one look only (its row cannot be held to choose yet), so
## this is how the others are reached.
func options_choices() -> Array:
	var rows: Array = []
	for group: Dictionary in Models.menu_rows():
		var ids: Array = group["ids"]
		var items: Array = []
		for id: String in ids:
			items.append(Models.short_label(id))
		rows.append({"caption": group["caption"], "items": items, "selected": ids.find(model_id)})
	return rows


func options_choose(row: int, item: int) -> void:
	var groups := Models.menu_rows()
	if row < 0 or row >= groups.size():
		return
	var ids: Array = (groups[row] as Dictionary)["ids"]
	if item >= 0 and item < ids.size():
		set_model(ids[item])


## What the table says about how bright a model reads: its materials are copied (the shared ones belong to the cached
## template) and their colour multiplied and their metal capped. The LED's mesh is left to `_prepare_led`.
func _apply_look(row: Dictionary) -> void:
	var brighten := float(row.get("brighten", 1.0))
	var metal_max := float(row.get("metallic_max", 1.0))
	if is_equal_approx(brighten, 1.0) and metal_max >= 1.0:
		return
	for mi: MeshInstance3D in _model_meshes:
		if mi.name == &"Led" or mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var own := mi.mesh.surface_get_material(surface) as StandardMaterial3D
			if own == null:
				continue
			var copy := own.duplicate() as StandardMaterial3D
			# albedo is a multiplier on the texture: above 1 is allowed, and this is what lifts a dark one
			copy.albedo_color = Color(copy.albedo_color.r * brighten, copy.albedo_color.g * brighten, copy.albedo_color.b * brighten, copy.albedo_color.a)
			copy.metallic = minf(copy.metallic, metal_max)
			mi.set_surface_override_material(surface, copy)


## The LED's own material, with its glow switched off to begin with. It is a copy: the shared
## one belongs to the cached template, and every screwdriver in the room lights on its own.
func _prepare_led(color: Color) -> void:
	var own := _led.mesh.surface_get_material(0) as StandardMaterial3D
	_led_mat = own.duplicate() as StandardMaterial3D if own != null else StandardMaterial3D.new()
	_led_off_color = _led_mat.albedo_color
	var see_through := _led_mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	_led_on_color = Color(color.r, color.g, color.b, LED_ALPHA_ON if see_through else 1.0)
	# The model's metal reads black without reflections (a dark room, the Quest): a dome that is
	# meant to be blue must show its colour with the light off.
	_led_mat.metallic = minf(_led_mat.metallic, 0.2)
	_led_mat.emission_enabled = true
	_led_mat.emission = color
	_led_mat.emission_energy_multiplier = 0.0
	_led.set_surface_override_material(0, _led_mat)


func _apply_led(on: bool) -> void:
	if _led_mat != null:
		_led_mat.emission_energy_multiplier = LED_ENERGY_ON if on else 0.0
		_led_mat.albedo_color = _led_on_color if on else _led_off_color


# ── sound ─────────────────────────────────────────────────────────────────────

func _build_sound() -> void:
	_sound = AudioStreamPlayer3D.new()
	_sound.name = "Hum"
	_sound.stream = Assets.mp3(SOUND_PATH, true)
	_sound.unit_size = 2.0
	_sound.max_distance = 12.0
	# At the tip, where the sound is made.
	_sound.position = Vector3(0, 0, -0.1)
	add_child(_sound)
