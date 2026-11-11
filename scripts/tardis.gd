## Tardis -- the TARDIS exterior: a big blue box you summon with the sonic screwdriver and can move.
##
## It is handled like an arcade cabinet (it is as big and as awkward to move): taken by HOLDING the
## grab on it for a second, never thrown, set down by aiming at the floor where a yellow rectangle
## shows its base (GroundPlacement), and it STANDS: dropped leaning, it turns upright again. Set
## down, it vanishes and materialises again where it was put, as it does when it is summoned.
##
## MATERIALISING is the classic (measured on a reference clip of the show): it does not move, it forms
## where it stands, switching on and off like a light, almost fully on and almost fully off, once for
## every pulse of landing.mp3 (2 s), the offs ever shorter, until it stays solid a little before the
## sound's peak. See `alpha_at`. Sending it away is the same backwards with takeoff.mp3 (the screwdriver
## held on it for 1.5 s does that: it joins RetroXR's `remote_target` group with a power cell, and the
## screwdriver presses power on whatever it points at). While it is changing it cannot be taken.
##
## HOW IT IS SEEN THROUGH, and still SOLID. While it changes each surface wears a copy of its OWN material
## (so it looks exactly as it does solid, and nothing pops when the copies are taken off) made see-through
## by alpha, with a depth-only pass drawn first. The depth pass leaves only the NEAREST surface of the box
## able to be drawn, so the inside and the far wall never show through the near one: invisible, but
## solid. (Forward+'s `GeometryInstance3D.transparency` showed them, a glass box, and the Quest's mobile
## renderer ignores it. A screen-space dither with a `discard` did not leak in a test render, but did in the
## game.) The originals are put back once it is solid.
##
## SAVED. It is registered as an object (TYPE) and in the "spawned" group, so RetroXR keeps it in the
## room's save slot like a cabinet, once it has the type stamped on it (`_init`: whoever makes it, the
## summon, the way back out of a console room or the SPAWN menu). It stays until it is sent away.
##
## THE DOOR is a VRButton over the front (a fingertip with the trigger in VR, the reticle's click on a
## desktop). Pressed, the door opens a crack and shuts again, with tardis-door.mp3, and the player's
## position is kept in `Tardis.entry` (not saved: it is gone when the game is). Taking the player
## into a console room is the next piece; for now the door only does what it does and says it
## (`door_used`).
##
## Its model is a GLB read at run time (mod_assets.gd), the meshes made direct children so that
## PickableHighlight outlines them. The door leaf is the mesh the exterior's table names; its origin
## is on the hinge, so the door turns by rotating it about Y.
extends XRToolsPickable

const Exteriors := preload("res://mods/xenu.tardis/scripts/tardis_exteriors.gd")
const Assets := preload("res://mods/xenu.tardis/scripts/mod_assets.gd")
const Travel := preload("res://mods/xenu.tardis/scripts/tardis_travel.gd")
const Look := preload("res://mods/xenu.tardis/scripts/tardis_look.gd")
const DoorPointer := preload("res://mods/xenu.tardis/scripts/door_pointer.gd")

const GROUP := &"xenu_tardis"
## The type RetroXR saves it under (permanent) and the metadata its persistence reads it from
## (ScenePersistence.MOD_TYPE_META, written out: that class cannot be loaded without the engine's extensions).
const TYPE := "xenu.tardis:tardis"
const MOD_TYPE_META := &"mod_object_type"
const LANDING_SOUND := "res://mods/xenu.tardis/assets/audio/landing.mp3"
const TAKEOFF_SOUND := "res://mods/xenu.tardis/assets/audio/takeoff.mp3"
const DOOR_SOUND := "res://mods/xenu.tardis/assets/audio/tardis-door.mp3"

## How long it takes to become solid, and to go. The sounds are 19 s: the first part of each is the
## switching on and off, so it runs for most of it and the rest is the sound's tail.
const MATERIALIZE_SECONDS := 15.0
const DEMATERIALIZE_SECONDS := 15.0
## One pulse, as landing.mp3's (its envelope repeats every 2.0 s), and when in it the box is most there
## (the reference clip's sound is loudest as the box is faintest, half a pulse on).
const PULSE_PERIOD := 2.0
const PULSE_PEAK_AT := 0.5
## Only so that it does not pop in at the very first frame: from nothing to its faint start over this long.
const INTRO_SECONDS := 0.6
## Solid at this fraction of the time (the clip: 7.4 s of the 8.3 s the sound takes to peak).
const SETTLE := 0.92
## It switches between almost fully on and almost fully off, as in the clip (there it is fully solid at
## 4.0, 5.5, 6.0 and 7.5 s of 8.3 and a ghost between): each pulse's TOP starts at PEAK_START and reaches full
## by PEAK_FULL_AT of the way; each pulse's BOTTOM starts at TROUGH_START and rises (to the power
## TROUGH_CURVE, so it stays low for long) to solid at the end.
const PEAK_START := 0.9
const PEAK_FULL_AT := 0.3
const TROUGH_START := 0.0
const TROUGH_CURVE := 3.0
## The pulse is not a sine: it dwells at the top and at the bottom and switches between (a smoothstep
## between these two levels of it: the nearer they are, the more like a switch).
const PULSE_LOW := 0.22
const PULSE_HIGH := 0.7
## From this fraction of the way the swings are smoothed out towards solid, so that the LAST transition,
## into solid for good, is a gentle rise and not a pulse: it must not be noticed.
const TAIL_FROM := 0.8
## The door when it is "a crack open", and the times of that: opening, held, closing.
const AJAR_DEGREES := 28.0
const AJAR_OPEN_SECONDS := 0.4
const AJAR_HOLD_SECONDS := 0.5
const AJAR_CLOSE_SECONDS := 0.4

## Standing it upright again: the fraction of the tilt corrected each second, and the most it turns at
## (radians a second), an arcade cabinet's numbers. Under UPRIGHT_EPS it rests.
const RIGHT_RATE := 5.0
const RIGHT_MAX := 3.0
const UPRIGHT_EPS := 0.0035
## A delete this soon (seconds) into the landing a drop began still takes off from where it stood before it was taken: the bin
## takes a moment to notice it (1.5 s was not enough: it took off from the bin).
const RETURN_WINDOW := 6.0
## It counts as having stood somewhere after this many seconds there, not held and not changing.
const REST_AFTER := 0.8
## RetroXR's door that opens (a knob to turn and a leaf to pull, in a hand; a press from a desk or a laser). Loaded by path: an older
## RetroXR has none, and the door is then the button it always was.
const VR_DOOR_SCRIPT := "res://Scripts/Objects/room/vr_door.gd"
## Where the VRDoor script is looked for: the suite points it at a stand-in (the real one needs the engine's extensions).
static var door_script_path := VR_DOOR_SCRIPT
## Pulled this far open (degrees), the player goes in; and the leaf is seen to open a moment first.
const ENTER_DEGREES := 30.0
const ENTER_DELAY := 0.35
const CENTER_OF_MASS_Y := 0.6

enum State { SOLID, MATERIALIZING, DEMATERIALIZING }

## Told when the door was pressed (the pose of the player's head then).
signal door_used(player_pose: Transform3D)
## Told when it has become solid, and when it has gone.
signal materialized
signal gone

## Where the player was when they last pressed a TARDIS's door: {pose, floor_y}. Kept for the
## console room to bring them back to, for as long as the game runs; never saved.
static var entry: Dictionary = {}

## Its exterior (a key of Exteriors.EXTERIORS).
@export var exterior := Exteriors.DEFAULT_ID

## What happens once the door has opened a crack: empty is TardisTravel.enter (into the console room).
## The tests put their own here.
var travel_handler := Callable()

var state: State = State.SOLID
## It is on its way out (sent away or deleted): it is not to be put back.
var _leaving := false
## Where it stood, solid and not held, the last time it did: what it takes off from if it is deleted soon after being
## carried off (to the bin), not from where the hand let go of it. `_has_rest` once it has stood.
var _rest_pose := Transform3D.IDENTITY
var _has_rest := false
var _calm := 0.0
var _calm_at := Vector3.ZERO
var _t := 0.0
var _duration := 0.0
var _parts: Array[MeshInstance3D] = []
var _door: MeshInstance3D = null
var _door_busy := false
## The VRDoor on the leaf, when RetroXR has one.
var _vr_door: Node3D = null
var _sfx: AudioStreamPlayer3D = null
var _door_sfx: AudioStreamPlayer3D = null
var _button: VRButton = null
var _signal_held := false
var _placer: Node = null
## Whether the white light behind the door is drawn: only while the door is open. Shut, a crack of the seam between the leaves
## let it leak through as a line of dots.
var _light_on := false
var _inside: MeshInstance3D = null
var _core: MeshInstance3D = null
var _doorway: MeshInstance3D = null
## What the ghost dressed: {mi, surface, original}; and the see-through copies with their own alpha: {material, base}.
var _ghosted: Array[Dictionary] = []
var _ghost_fades: Array[Dictionary] = []

static var _version := ""

## What the TARDIS reports about itself while it changes, for whoever has to find out why it looks as it does on a
## machine they cannot see: the player's game writes it, a log under the mod's own user folder (the game's own log is
## rotated by every start, and shared with any probe).
const DEBUG_LOG := "user://mods/xenu.tardis/ghost_debug.log"
const DEBUG_MAX_BYTES := 200000
var _debug_next := 0.0

func _init() -> void:
	set_meta(MOD_TYPE_META, TYPE)
	RemoteTarget.join(self)


## The parts exist before PickableHighlight (a child) readies and looks for its parent's meshes.
func _enter_tree() -> void:
	add_to_group(GROUP)
	if not _parts.is_empty():
		return
	_build_model()


func _ready() -> void:
	super()
	print("[xenu.tardis %s] a TARDIS is in the room" % mod_version())
	_sfx = _player("Sfx")
	_door_sfx = _player("DoorSfx")
	_build_door_control()
	_placer = GroundPlacement.new()
	_placer.name = "GroundPlacement"
	_placer.host = self
	_placer.set_footprint(Exteriors.entry(exterior)["footprint"] as Vector2)
	add_child(_placer)
	grabbed.connect(func(_p: Variant = null, _by: Variant = null) -> void: _signal_held = true)
	dropped.connect(_on_dropped)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, CENTER_OF_MASS_Y, 0.0)
	angular_damp = maxf(angular_damp, 2.0)
	set_process(false)


# ── how it is handled (as a cabinet) ──────────────────────────────────────────

## Taken by holding the grab on it for this long (HoldToGrab asks every pickable).
func grab_hold_seconds() -> float:
	return HoldToGrab.DEFAULT_SECONDS


## It is set down where the hand let go of it, never thrown across the room.
func throw_scale() -> float:
	return 0.0


func _is_held() -> bool:
	if _signal_held or is_picked_up():
		return true
	# the laser holds without a GrabDriver: the layer it moved to is the tell
	return collision_layer == picked_up_layer and collision_layer != original_collision_layer


func _physics_process(delta: float) -> void:
	if _is_held() or freeze:
		_calm = 0.0
		return
	if state == State.SOLID:
		# It has stood where it is for REST_AFTER: only then is it "where it stood". The bin (the menu's, the room's) deletes what
		# is let go over it a moment after the hand lets go, and in that moment the TARDIS is not held: recording its pose at once
		# made "where it stood" the pose over the bin.
		if global_position.distance_to(_calm_at) > 0.02:
			_calm = 0.0  # it has moved: the count starts again from here
			_calm_at = global_position
		_calm += delta
		if _calm >= REST_AFTER:
			_rest_pose = global_transform
			_has_rest = true
	# Not held: it tends to STAND. Dropped leaning, it turns back upright about the horizontal.
	# Its heading is left alone: the player's to choose.
	var axis := global_basis.y.cross(Vector3.UP)
	var tilt := asin(clampf(axis.length(), 0.0, 1.0))
	if tilt < UPRIGHT_EPS:
		return
	var turn := minf(tilt * RIGHT_RATE, RIGHT_MAX)
	var yaw_part := Vector3.UP * angular_velocity.dot(Vector3.UP)
	angular_velocity = yaw_part + axis.normalized() * turn


## Deleted (the storage box, the item menu's Delete, the SCENE tab) or on its way out: RetroXR's Vanish marks the
## node and shrinks it before freeing it, and for those few frames it is still in the tree. It must do nothing
## then: not land again (a drop into the bin fires `dropped` first), not become solid, not be put back.
func _being_deleted() -> bool:
	return is_queued_for_deletion() or Vanish.is_vanishing(self)


func _exit_tree() -> void:
	# What was deleted or sent away is not to come back with the player from a console room (TardisTravel.arrive puts
	# one back only where the room's slot did not keep it)
	if _being_deleted() or _leaving:
		Travel.forget(self)


## RetroXR's delete (the bin, the item menu, the SCENE tab: Trash.delete_with_dependents) calls this on an object that has
## it instead of shrinking it away like the rest. The TARDIS does what it does when it is sent away: it dematerialises, with
## the take-off sound, and is freed at the end.
func drop_and_free() -> void:
	# carried to the bin (or deleted soon after being put down): it goes from where it stood before it was taken
	var back := _rest_pose
	var go_back := _has_rest and (state == State.SOLID or (state == State.MATERIALIZING and _t < RETURN_WINDOW))
	print("[xenu.tardis %s] deleted: %s, %.1f s into it, was standing at %s, now at %s: %s" % [mod_version(),
		State.keys()[state], _t, _rest_pose.origin, global_position, "takes off from where it stood" if go_back else "takes off from here"])
	if _signal_held or is_picked_up():
		drop()
	dematerialize()
	if go_back:
		global_transform = back
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


## Put down: it goes, and comes back where it was put (GroundPlacement stands it first, deferred).
func _on_dropped(_p: Variant = null) -> void:
	_signal_held = false
	if state == State.SOLID and not _being_deleted():
		_land_if_solid.call_deferred()


## The landing after a drop, a frame later: GroundPlacement has stood it up, and a delete that came with the drop (the bin) has
## already started the take-off, which must not be overwritten by a landing.
func _land_if_solid() -> void:
	if state == State.SOLID and not _leaving:
		_begin(State.MATERIALIZING, MATERIALIZE_SECONDS, LANDING_SOUND)


# ── materialising ─────────────────────────────────────────────────────────────

## Land: blink in over MATERIALIZE_SECONDS, with the landing sound. A TARDIS loaded from a save does
## not call this: it is simply there.
func materialize() -> void:
	_begin(State.MATERIALIZING, MATERIALIZE_SECONDS, LANDING_SOUND)


## Go: blink out, with the takeoff sound, then leave the room.
func dematerialize() -> void:
	if state == State.DEMATERIALIZING:
		return
	_leaving = true
	_begin(State.DEMATERIALIZING, DEMATERIALIZE_SECONDS, TAKEOFF_SOUND)


## The version of this mod as its mod.json says, so that a log tells which build was running.
static func mod_version() -> String:
	if _version.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://mods/xenu.tardis/mod.json"))
		_version = str((parsed as Dictionary).get("version", "?")) if parsed is Dictionary else "?"
	return _version


func _begin(new_state: State, seconds: float, sound: String) -> void:
	if not is_inside_tree() or _being_deleted():
		return
	print("[xenu.tardis %s] TARDIS %s" % [mod_version(), "materialising" if new_state == State.MATERIALIZING else "dematerialising"])
	state = new_state
	_calm = 0.0
	_t = 0.0
	_duration = seconds
	enabled = false
	freeze = true
	_show_parts(alpha_at(0.0, seconds, new_state == State.MATERIALIZING), false)
	_debug_next = 0.0
	_debug("begin")
	_sfx.stream = Assets.mp3(sound)
	_sfx.play()
	set_process(true)


## How much of it is there `t` seconds into a materialisation of `duration` (`appearing`), or into the
## reverse: 0 is gone, 1 is solid. It swings between a ghost and SOLID (PULSE_PERIOD), the solid tops
## coming early and the ghostly bottoms rising until the two meet at SETTLE of the way. Going is the same
## played backwards. Pure, and continuous: no jump to or from solid.
static func alpha_at(t: float, duration: float, appearing: bool) -> float:
	if not appearing:
		return alpha_at(maxf(duration - t, 0.0), duration, true)
	if t >= duration * SETTLE:
		return 1.0
	var u := clampf(t / (duration * SETTLE), 0.0, 1.0)
	var top_u := clampf(u / PEAK_FULL_AT, 0.0, 1.0)
	var top := lerpf(PEAK_START, 1.0, top_u * top_u * (3.0 - 2.0 * top_u))
	var bottom := lerpf(TROUGH_START, 1.0, pow(u, TROUGH_CURVE))
	var pulse := smoothstep(PULSE_LOW, PULSE_HIGH, 0.5 + 0.5 * cos(TAU * (t - PULSE_PEAK_AT) / PULSE_PERIOD))
	var shown := lerpf(lerpf(bottom, top, pulse), 1.0, smoothstep(TAIL_FROM, 1.0, u))
	var k := clampf(t / INTRO_SECONDS, 0.0, 1.0)
	return shown * k * k * (3.0 - 2.0 * k)


## Advance the materialising by `delta` seconds: _process does it, the tests do it by the second.
func advance(delta: float) -> void:
	if state == State.SOLID:
		return
	if _being_deleted():
		set_process(false)
		return
	_t += delta
	var appearing := state == State.MATERIALIZING
	_show_parts(alpha_at(_t, _duration, appearing), appearing and _t >= _duration * SETTLE)
	if _t >= _debug_next:
		_debug("step")
		_debug_next = _t + 2.0
	if _t < _duration:
		return
	set_process(false)
	if appearing:
		state = State.SOLID
		enabled = true
		freeze = false
		_show_parts(1.0, true)
		materialized.emit()
	else:
		gone.emit()
		queue_free()


func _process(delta: float) -> void:
	advance(delta)


## Draw every part `alpha` there (1 is as solid as it looks, 0 is not drawn at all: a part that cannot be
## seen is not sent). `solid`: it is done, the model's own materials go back.
func _show_parts(alpha: float, solid: bool) -> void:
	if solid:
		_ghost_off()
	else:
		_ghost_to(alpha)
	for mi in _parts:
		# the white box behind the open door is one flat material: it is there when the box is solid
		mi.visible = alpha > 0.01 and _part_shown(mi, solid)


## Whether a part is drawn when the TARDIS is (solid or not): the light behind the door only while the door is open and the TARDIS
## solid, the dark core in its place while the door is shut, the rest always.
func _part_shown(mi: MeshInstance3D, solid: bool) -> bool:
	if mi == _inside or mi == _doorway:
		return solid and _light_on
	if mi == _core:
		return solid and not _light_on
	return true


## The ghost at `alpha`: every surface on its see-through copy (made once), all at the same alpha: no
## surface is more present than another.
func _ghost_to(alpha: float) -> void:
	if _ghosted.is_empty():
		_dress_ghosts()
	for fade in _ghost_fades:
		var base := fade["base"] as Color
		(fade["material"] as BaseMaterial3D).albedo_color = Color(base.r, base.g, base.b, base.a * alpha)


## The depth-only pass: draws nothing and writes depth, and sorts before the blended copy (render_priority). A
## StandardMaterial3D, not a shader of our own: nothing the renderer has to be asked to compile from a string.
static func _depth_pass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.disable_fog = true
	m.disable_receive_shadows = true
	m.render_priority = -1
	return m


func _dress_ghosts() -> void:
	for mi in _parts:
		if mi == _inside or mi == _doorway or mi == _core or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var own := mi.get_surface_override_material(i)
			var src := (own if own != null else mi.mesh.surface_get_material(i)) as BaseMaterial3D
			if src == null:
				continue
			var shown := src.duplicate() as BaseMaterial3D
			shown.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			shown.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			shown.render_priority = 0
			var first := _depth_pass()
			first.next_pass = shown
			_ghosted.append({"mi": mi, "surface": i, "original": own, "first": first})
			_ghost_fades.append({"material": shown, "base": src.albedo_color})
			mi.set_surface_override_material(i, first)


## Put every surface's own material back (the solid TARDIS is the model as it was made).
func _ghost_off() -> void:
	if _ghosted.is_empty():
		return
	for entry in _ghosted:
		var mi := entry["mi"] as MeshInstance3D
		if is_instance_valid(mi):
			mi.set_surface_override_material(int(entry["surface"]), entry["original"] as Material)
	_ghosted.clear()
	_ghost_fades.clear()


## Append what this TARDIS looks like to the renderer to DEBUG_LOG: the version and the renderer; whether each
## surface still wears the ghost this script put on it (something else may take a material back); the alpha the blended
## copies have; and any mesh that is drawn and is not one of the model's parts (an outline, an overlay).
func _debug(tag: String) -> void:
	DirAccess.make_dir_recursive_absolute(DEBUG_LOG.get_base_dir())
	var f: FileAccess = null
	if FileAccess.file_exists(DEBUG_LOG) and FileAccess.get_file_as_bytes(DEBUG_LOG).size() < DEBUG_MAX_BYTES:
		f = FileAccess.open(DEBUG_LOG, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	if f == null:
		f = FileAccess.open(DEBUG_LOG, FileAccess.WRITE)
	if f == null:
		return
	var worn := 0
	var depth_ok := 0
	var alpha_seen := -1.0
	for entry in _ghosted:
		var mi := entry["mi"] as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		var first := entry["first"] as BaseMaterial3D
		if mi.get_surface_override_material(int(entry["surface"])) == first:
			worn += 1
		if first != null and first.next_pass is BaseMaterial3D and first.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS:
			depth_ok += 1
			alpha_seen = (first.next_pass as BaseMaterial3D).albedo_color.a
	var shifted := 0
	var strangers: PackedStringArray = []
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.transparency != 0.0:
			shifted += 1
		if m.is_visible_in_tree() and not _parts.has(m) and m.get_parent() != null and not str(m.get_path()).contains("Button"):
			strangers.append(str(m.name))
	f.seek_end()
	f.store_line("[%s] %s v%s state=%s t=%.2f/%.1f alpha_now=%.3f | %s, %s | ghost: %d surfaces, %d still worn, %d with a depth pass, copy alpha %.3f | %d meshes with instance transparency | other meshes drawn: %s" % [
		Time.get_datetime_string_from_system(), tag, mod_version(), State.keys()[state], _t, _duration,
		alpha_at(_t, _duration, state != State.DEMATERIALIZING), RenderingServer.get_current_rendering_method(),
		Engine.get_version_info().get("string", "?"), _ghosted.size(), worn, depth_ok, alpha_seen, shifted,
		", ".join(strangers) if not strangers.is_empty() else "none"])
	f.close()


## Whether the see-through copies are on now, for the tests.
func is_ghosted() -> bool:
	return not _ghosted.is_empty()


# ── the remote (the sonic screwdriver sends it away) ──────────────────────────

func remote_layout() -> Array:
	return [{"id": "power", "glyph": "power", "col": 0, "row": 0, "span": 3}]


func remote_activate(id: String) -> void:
	if id == "power":
		dematerialize()


## Greyed while it changes: a screwdriver pointed at a TARDIS that is arriving does nothing.
func remote_cell_enabled(_id: String) -> bool:
	return state == State.SOLID


# ── the door ──────────────────────────────────────────────────────────────────

## The door was pressed: it opens a crack, the player's place is kept and they are taken into the
## console room (TardisTravel.enter), and it shuts. Ignored while it is changing or already moving.
func press_door() -> void:
	if state != State.SOLID or _door_busy or _door == null or _being_deleted():
		return
	_door_busy = true
	_record_entry()
	_play_door_sound()
	_set_light(true)
	var tw := create_tween()
	tw.tween_property(_door, "rotation:y", deg_to_rad(AJAR_DEGREES), AJAR_OPEN_SECONDS)
	tw.tween_interval(AJAR_HOLD_SECONDS)
	tw.tween_callback(_go_in)
	tw.tween_property(_door, "rotation:y", 0.0, AJAR_CLOSE_SECONDS)
	tw.finished.connect(func() -> void:
		_door_busy = false
		_set_light(false))


## Keep where the player stands (and tell it), for the console room to bring them back to.
func _record_entry() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var pose := cam.global_transform
		entry = {"pose": pose, "floor_y": preload("res://mods/xenu.tardis/scripts/tardis_summon.gd").floor_y(cam)}
		door_used.emit(pose)


func _play_door_sound() -> void:
	_door_sfx.stream = Assets.mp3(DOOR_SOUND)
	_door_sfx.play(Assets.DOOR_SOUND_START)


## The door control: RetroXR's VRDoor on the leaf when there is one, else the button over the front.
func _build_door_control() -> void:
	if not _build_vr_door():
		_build_door_button()


## A VRDoor on the leaf: the handle taken in a hand, turned with the wrist and pulled; a press from a desk or a laser swings it open.
## False when RetroXR has no VRDoor (or it will not build here): the caller makes the button.
func _build_vr_door() -> bool:
	if _door == null:
		return false
	var script := load(door_script_path) as GDScript
	if script == null or not script.can_instantiate():
		return false
	var leaf: Dictionary = Exteriors.entry(exterior).get("leaf", {})
	if leaf.is_empty():
		return false
	var width := float(leaf["width"])
	var hinge := _door.position  # the leaf's origin is on its hinge, the leaf running -x from it
	var door := Node3D.new()
	door.name = "VRDoor"
	door.set_script(script)
	door.position = Vector3(hinge.x - width / 2.0, hinge.y, hinge.z)  # bottom middle of the leaf, +Z out of the front
	door.set("hinge_side", 0)  # POSITIVE_X: the hinge is at the leaf's +x edge
	door.set("swing", 0)  # TOWARD_POSITIVE_Z: it opens outward
	door.set("open_deg", float(Exteriors.entry(exterior)["door_open_deg"]))
	door.set("self_closing", true)  # let go and it eases shut
	door.set("leaf_collision", false)
	door.set("width", width)
	door.set("height", float(leaf["height"]))
	door.set("thickness", float(leaf["thickness"]))
	door.set("bottom_gap", 0.0)
	var knob: Vector2 = leaf["knob"]
	door.set("knob_position", Vector2(knob.x - door.position.x, knob.y - door.position.y))
	door.set("log_name", "tardis")
	add_child(door)
	_vr_door = door
	# the model's own leaf hangs on it (the plain one it built is hidden); the handle is the model's white dot, so its
	# grab is an empty node at that place and the brass knob it would draw is hidden
	door.call("dress_leaf", _door)
	var grab := Node3D.new()
	grab.name = "HandleGrab"
	add_child(grab)
	grab.position = Vector3(knob.x, knob.y, hinge.z)
	door.call("dress_opener", grab)
	door.connect("unlatched", _on_door_unlatched)
	door.connect("door_changed", _on_door_changed)
	return true


## The latch let go (the handle turned, or the door pressed): it creaks, and what is inside shows.
func _on_door_unlatched() -> void:
	if state == State.SOLID:
		_play_door_sound()


## The door moved. The light behind it is on while it is open; pulled far enough, in the player goes.
func _on_door_changed(degrees: float, latched: bool) -> void:
	var open := degrees > 1.0 or not latched
	if open != _light_on:
		_set_light(open)
	if state == State.SOLID and not latched and degrees >= ENTER_DEGREES and not _door_busy and not _being_deleted():
		_enter_through_door()


## Pulled open far enough: the player's place is kept, the door seen open for a moment, then shut (so it is saved shut) and in.
func _enter_through_door() -> void:
	_door_busy = true
	_record_entry()
	await get_tree().create_timer(ENTER_DELAY).timeout
	if _vr_door != null and is_instance_valid(_vr_door):
		_vr_door.call("close", false)
	_set_light(false)
	_go_in()
	_door_busy = false


## Draw (or not) the light behind the door, now.
func _set_light(on: bool) -> void:
	_light_on = on
	if state == State.SOLID:
		_show_parts(1.0, true)


## The door has been open a moment: in. (The TARDIS is gone with its room; the door shuts on nobody.)
func _go_in() -> void:
	if travel_handler.is_valid():
		travel_handler.call()
	else:
		Travel.enter(self)


## How far the door is open now, in degrees.
func door_degrees() -> float:
	if _vr_door != null and is_instance_valid(_vr_door):
		return float(_vr_door.call("get_angle_deg"))
	return rad_to_deg(_door.rotation.y) if _door != null else 0.0


# ── building it ───────────────────────────────────────────────────────────────

func _build_model() -> void:
	var row := Exteriors.entry(exterior)
	var model := Assets.instance_glb(str(row["glb"]))
	if model == null:
		push_warning("[xenu.tardis] cannot read %s: the TARDIS has no model" % row["glb"])
		return
	var meshes := Assets.adopt_meshes(model, self)
	_door = meshes.get(str(row["door"])) as MeshInstance3D
	if _door != null:
		_two_sided(_door)
	for name: String in meshes:
		_parts.append(meshes[name] as MeshInstance3D)
		Look.dress(meshes[name] as MeshInstance3D, row)
	# The inside, seen through the open door: not the shell's dark inner walls but a white light, "bigger on
	# the inside" -- a box drawn from within, small enough to stand wholly inside them (HDR white: it blooms
	# where the room has glow on).
	var inside := MeshInstance3D.new()
	inside.name = "Inside"
	var box := BoxMesh.new()
	box.size = row["inside_size"] as Vector3
	inside.mesh = box
	inside.position = row["inside_center"] as Vector3
	var light := StandardMaterial3D.new()
	light.albedo_color = Color(2.5, 2.5, 2.5)
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.cull_mode = BaseMaterial3D.CULL_FRONT
	inside.material_override = light
	inside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inside.add_to_group("outline_exclude")
	inside.visible = false  # only while the door is open: a TARDIS made solid (a save, the way back) never runs _show_parts
	add_child(inside)
	_inside = inside
	_parts.append(inside)
	# ... and a pane of the same light in the doorway itself, so that it is all that can be seen there
	var pane := MeshInstance3D.new()
	pane.name = "Doorway"
	var quad := QuadMesh.new()
	quad.size = row["doorway_size"] as Vector2
	pane.mesh = quad
	pane.position = row["doorway_center"] as Vector3
	var pane_light := light.duplicate() as StandardMaterial3D
	pane_light.cull_mode = BaseMaterial3D.CULL_DISABLED
	pane.material_override = pane_light
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pane.add_to_group("outline_exclude")
	pane.visible = false
	add_child(pane)
	_doorway = pane
	# ... and, shut, a dark core in the shell: a crack at the edge of the door cannot show the far wall's white panes
	var core := MeshInstance3D.new()
	core.name = "Core"
	var core_box := BoxMesh.new()
	core_box.size = row["core_size"] as Vector3
	core.mesh = core_box
	core.position = row["core_center"] as Vector3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.01, 0.015, 0.04)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = dark
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.add_to_group("outline_exclude")
	add_child(core)
	_core = core
	_parts.append(pane)
	_parts.append(core)


## The leaf is seen from behind when it is open, and a leaf is one skin: draw both sides.
static func _two_sided(mi: MeshInstance3D) -> void:
	for s in mi.mesh.get_surface_count():
		var own := mi.mesh.surface_get_material(s) as StandardMaterial3D
		if own == null:
			continue
		var both := own.duplicate() as StandardMaterial3D
		both.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.set_surface_override_material(s, both)


## A VRButton over both leaves, a hand's breadth proud of them, pressed by trigger (a fingertip
## brushing the door must not open it).
func _build_door_button() -> void:
	var row := Exteriors.entry(exterior)
	var fp := row["footprint"] as Vector2
	# What the laser can press (the button below is an area, which a headset's laser cannot see): the trigger or A, aimed at the door
	var at := Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(0.0, 0.95, fp.y / 2.0 + 0.02))
	var pointer := DoorPointer.make(Vector3(0.9, 0.12, 1.75), at)
	add_child(pointer)
	pointer.connect("pressed", press_door)
	_button = VRButton.new()
	_button.name = "DoorButton"
	_button.require_trigger = true
	_button.interact_margin = 0.06
	_button.depress_depth = 0.0
	# the button's own +Y is the face of the door: out of the front (+Z)
	_button.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN),
		Vector3(0.0, 0.95, fp.y / 2.0 + 0.02))
	var cap := MeshInstance3D.new()
	cap.name = "ButtonMesh"
	var plate := BoxMesh.new()
	plate.size = Vector3(0.84, 0.01, 1.7)
	cap.mesh = plate
	cap.visible = false
	_button.add_child(cap)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.12, 1.75)
	shape.shape = box
	_button.add_child(shape)
	add_child(_button)
	_button.button_pressed.connect(press_door)


func _player(player_name: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = player_name
	p.unit_size = 4.0
	p.max_distance = 25.0
	add_child(p)
	return p
