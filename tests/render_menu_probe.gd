## The console's menu as a player sees it: opens it from where the player stands (the rig at the door) and writes
## menu_<id>_front.png (from the eye) and menu_<id>_side.png (from the side, to see what the panel sits in), and
## prints what a ray from the eye to the panel meets on the room's layer 1 (a solid in the way would make it unusable).
##
##   ID=10 OUT=/some/dir godot --path RetroXR res://mods/xenu.tardis/tests/render_menu_probe.tscn
extends Node


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var id := OS.get_environment("ID")
	if id.is_empty():
		id = "1"
	var row := (load("res://mods/xenu.tardis/scripts/console_rooms.gd") as GDScript).call("entry", id) as Dictionary
	var root := (load(str(row["scene"])) as PackedScene).instantiate()
	add_child(root)
	for i in 40:
		await get_tree().process_frame
	var room := root.get_node("ConsoleRoom")
	var rig := root.get_node("PlayerRig") as Node3D
	var eye := rig.global_position + Vector3(0, 1.6, 0)
	var cam := Camera3D.new()
	cam.fov = 80.0
	add_child(cam)
	cam.current = true
	cam.global_position = eye
	cam.look_at(Vector3(0, 1.0, 0))
	if room.console == null:
		print("[menu] NO console on this host (", id, ")")
		get_tree().quit()
		return
	room.console.toggle_options_ui(cam)
	for i in 20:
		await get_tree().process_frame
	var panel := room.console.get_node_or_null("ConsolePanel") as Node3D
	if panel == null:
		print("[menu] no panel was made")
		get_tree().quit()
		return
	print("[menu] panel at %s, visible %s; console radius %.2f height %.2f at %s" % [panel.global_position, panel.visible, room.console.radius, room.console.height, room.console.global_position])
	var q := PhysicsRayQueryParameters3D.create(eye, panel.global_position)
	q.collision_mask = 1
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	print("[menu] ray eye -> panel on layer 1: %s" % ("nothing" if hit.is_empty() else "%s at %s (%s)" % [(hit["collider"] as Node).name, hit["position"], ((hit["collider"] as Node).get_parent().name)]))
	cam.look_at(panel.global_position)
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("menu_%s_front.png" % id))
	cam.global_position = panel.global_position + Vector3(2.2, 0.3, 0)
	cam.look_at(panel.global_position)
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("menu_%s_side.png" % id))
	print("[menu] wrote pictures in ", out)
	get_tree().quit()
