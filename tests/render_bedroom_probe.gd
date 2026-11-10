## The TARDIS landing in RetroXR's own bedroom (the empty room, as a player sees it), one frame every
## STEP seconds of the animation, from where the screwdriver's summon would stand the player. Needs a window:
##
##   OUT=/some/dir godot --path RetroXR res://mods/xenu.tardis/tests/render_bedroom_probe.tscn
##
## Writes bed_000.png ... and `bed_alpha.txt` (time, alpha the curve says), for tools/analyse_landing.py.
extends Node

const STEP := 0.125
const SECONDS := 15.0
const FRONT := 1.7
## What to land: "materialize" (default) or "dematerialize"; the room: BedroomScene unless ROOM says another.
const DEFAULT_ROOM := "res://Scenes/BedroomScene.tscn"


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var room_path := OS.get_environment("ROOM")
	var room := (load(room_path if not room_path.is_empty() else DEFAULT_ROOM) as PackedScene).instantiate()
	add_child(room)
	for i in 40:
		await get_tree().process_frame
	# what a player who has switched the welcome page off does not see: the page, the loading overlay
	for n in get_tree().root.find_children("*Welcome*", "", true, false):
		print("[probe] hiding ", n.get_path())
		if n is Node3D:
			(n as Node3D).visible = false
		elif n is CanvasItem:
			(n as CanvasItem).visible = false
	for n in get_tree().root.find_children("LoadingOverlay*", "", true, false):
		print("[probe] hiding ", n.get_path())
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	var rig := room.get_node_or_null("PlayerRig") as Node3D
	var eye := (rig.global_position if rig != null else Vector3.ZERO) + Vector3(0, 1.6, 0)
	var forward := -(rig.global_basis.z if rig != null else Vector3.BACK)
	forward.y = 0.0
	forward = forward.normalized()
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.global_position = eye
	cam.look_at(eye + forward + Vector3(0, -0.12, 0))
	cam.current = true
	var t := (load("res://mods/xenu.tardis/scenes/tardis.tscn") as PackedScene).instantiate()
	t.freeze = true
	add_child(t)
	var spot := Vector3(eye.x, rig.global_position.y if rig != null else 0.0, eye.z) + forward * FRONT
	t.global_transform = Transform3D(Basis(Vector3.UP, atan2(eye.x - spot.x, eye.z - spot.z)), spot)
	var going := OS.get_environment("GOING") == "1"
	(t.dematerialize if going else t.materialize).call()
	t.set_process(false)  # the probe steps the animation itself
	var log := FileAccess.open(out.path_join("bed_alpha.txt"), FileAccess.WRITE)
	var n := int(SECONDS / STEP)
	for i in n + 1:
		for k in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("bed_%03d.png" % i))
		log.store_line("%.3f %.4f" % [i * STEP, t.alpha_at(i * STEP, 15.0, not going)])
		t.advance(STEP)
	log.close()
	print("[probe] wrote %d frames to %s" % [n + 1, out])
	get_tree().quit()
