## Screenshots of a console room as a player sees it, from the real scene (its environment, lights, rig), and what
## a ray from the player's eye to the door meets. Needs a window:
##
##   ID=1 OUT=/some/dir godot --path RetroXR res://mods/xenu.tardis/tests/render_room_probe.tscn
##
## ID is the room's table id (default: the first). Writes room_<id>_<shot>.png and prints the ray tests.
extends Node


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var id := OS.get_environment("ID")
	if id.is_empty():
		id = "1"
	var row := (load("res://mods/xenu.tardis/scripts/console_rooms.gd") as GDScript).call("entry", id) as Dictionary
	var scene := load(str(row["scene"])) as PackedScene
	var root := scene.instantiate()
	add_child(root)
	for i in 40:
		await get_tree().process_frame
	for n in get_tree().root.find_children("*Welcome*", "", true, false):
		if n is Node3D:
			(n as Node3D).visible = false
		elif n is CanvasItem:
			(n as CanvasItem).visible = false
	for n in get_tree().root.find_children("LoadingOverlay*", "", true, false):
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	var room := root.get_node("ConsoleRoom")
	var rig := root.get_node("PlayerRig") as Node3D
	var eye := rig.global_position + Vector3(0, 1.6, 0)
	var door_at: Vector3 = room.door_button.global_position
	print("[probe] room %s: rig %s, door button %s (layer %d)" % [id, rig.global_position, door_at, room.door_button.collision_layer])
	# what the eye meets on the way to the door, by layer: a wall or pillar (1), the door's own button (21)
	for mask: int in [1, 1 << 20]:
		var q := PhysicsRayQueryParameters3D.create(eye, door_at)
		q.collision_mask = mask
		q.collide_with_areas = true
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
		print("[probe]   ray to the door (mask %d): %s" % [mask, "nothing" if hit.is_empty() else "%s at %s" % [(hit["collider"] as Node).name, hit["position"]]])
	var cam := Camera3D.new()
	cam.fov = 80.0
	add_child(cam)
	cam.current = true
	var s: float = room.room_scale
	var shots := {
		"ahead": [eye, Vector3(0, 1.2, 0)],
		"back": [eye, door_at],
		"high": [Vector3(0, 1.7, 0) + Vector3(-2.6, 0.2, 2.6) * maxf(s, 0.8), Vector3(0, 2.2 * maxf(s, 0.8), 0)],
		"console": [Vector3(0, 1.5, 1.6 * maxf(s, 0.8)), Vector3(0, 0.9, 0)],
	}
	for shot: String in shots:
		cam.global_position = shots[shot][0]
		cam.look_at(shots[shot][1])
		for i in 6:
			await get_tree().process_frame
		var path := out.path_join("room_%s_%s.png" % [id, shot])
		get_viewport().get_texture().get_image().save_png(path)
		print("[probe] wrote ", path)
	get_tree().quit()
