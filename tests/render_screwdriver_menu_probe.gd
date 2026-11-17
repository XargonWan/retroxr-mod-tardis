## The screwdriver's object menu (ObjectOptionsPanel, the one RetroXR gives an object) as a player sees it, and what a
## change of Doctor does to it. Needs a window. Writes into OUT: sd_1_menu.png (open), sd_2_after.png (a Doctor picked, ID),
## sd_3_reopened.png (closed and opened again), sd_4_held.png (the held outline on), and prints each step.
##
##   ID=13 OUT=/some/dir godot --path RetroXR res://mods/xenu.tardis/tests/render_screwdriver_menu_probe.tscn
extends Node


func _shot(cam: Camera3D, out: String, name: String, frames: int = 12) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("[menu] wrote ", name)


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var id := OS.get_environment("ID")
	if id.is_empty():
		id = "13"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.45, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.75, 0.7)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-50, 30, 0)
	var sd := (load("res://mods/xenu.tardis/scenes/sonic_screwdriver.tscn") as PackedScene).instantiate() as RigidBody3D
	add_child(sd)
	sd.freeze = true
	sd.global_position = Vector3(0, 0, -0.6)
	sd.rotation_degrees = Vector3(0, 0, 90)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 0.45, 0.15)
	cam.look_at(Vector3(0, 0.12, -0.6))
	for i in 60:
		await get_tree().process_frame
	# RetroXR's own start-up card covers the window until a room is "ready": there is none here, so it is hidden
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		print("[menu] canvas layer ", n.get_path(), " layer ", (n as CanvasLayer).layer)
		(n as CanvasLayer).visible = false
	var overlay := get_tree().root.get_node_or_null("LoadingOverlay")
	if overlay != null:
		overlay.queue_free()
	for n in get_tree().root.find_children("*Welcome*", "", true, false):
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	ObjectOptionsPanel.toggle_for(sd, cam)
	await _shot(cam, out, "sd_1_menu.png", 30)
	var panel := sd.get_node_or_null("ObjectOptionsPanel") as Node3D
	print("[menu] open: panel %s, visible %s" % [panel, panel.visible if panel else "-"])
	sd.options_choose(1, ["10", "11", "12", "13"].find(id) if id in ["10", "11", "12", "13"] else 0)
	if id in ["2", "3", "4", "5"]:
		sd.options_choose(0, ["2", "3", "4", "5"].find(id))
	print("[menu] now wears ", sd.model_id, " meshes ", sd.find_children("*", "MeshInstance3D", false, false).size())
	await _shot(cam, out, "sd_2_after.png", 30)
	print("[menu] after the pick: panel visible %s" % [panel.visible if is_instance_valid(panel) else "gone"])
	ObjectOptionsPanel.toggle_for(sd, cam)
	await _shot(cam, out, "sd_3_toggled.png", 20)
	print("[menu] toggled: panel visible %s" % [panel.visible if is_instance_valid(panel) else "gone"])
	ObjectOptionsPanel.toggle_for(sd, cam)
	await _shot(cam, out, "sd_3_reopened.png", 30)
	print("[menu] toggled again: panel visible %s" % [panel.visible if is_instance_valid(panel) else "gone"])
	ObjectOptionsPanel.toggle_for(sd, cam)
	for i in 10:
		await get_tree().process_frame
	var hl := sd.get_node("PickableHighlight")
	hl.call("_on_grabbed", sd, null)
	await _shot(cam, out, "sd_4_held.png", 20)
	get_tree().quit()
