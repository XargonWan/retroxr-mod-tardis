## Every screwdriver side by side in one light, to compare how bright each reads (the 13th was reported too dark), plain
## and with the held outline on. Needs a window. Writes look_plain.png and look_held.png into OUT.
##
##   OUT=/some/dir godot --path RetroXR --xr-mode off res://mods/xenu.tardis/tests/render_screwdriver_look_probe.tscn
extends Node


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
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
	var ids: Array = (load("res://mods/xenu.tardis/scripts/screwdriver_models.gd") as GDScript).call("ids")
	var scene := load("res://mods/xenu.tardis/scenes/sonic_screwdriver.tscn") as PackedScene
	var all: Array[RigidBody3D] = []
	for i in ids.size():
		var sd := scene.instantiate() as RigidBody3D
		sd.set_meta(&"model_variant", ids[i])
		add_child(sd)
		sd.freeze = true
		# lying along the picture (the tip to the left), one under the other
		sd.global_basis = Basis(Vector3.UP, deg_to_rad(90))
		sd.global_position = Vector3(0, 0, (i - (ids.size() - 1) / 2.0) * 0.045)
		all.append(sd)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.42
	cam.global_position = Vector3(0, 0.6, 0)
	cam.look_at(Vector3.ZERO, Vector3.BACK)
	for i in 60:
		await get_tree().process_frame
	var overlay := get_tree().root.get_node_or_null("LoadingOverlay")
	if overlay != null:
		overlay.queue_free()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("look_plain.png"))
	for sd in all:
		sd.get_node("PickableHighlight").call("_on_grabbed", sd, sd)
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("look_held.png"))
	print("[look] wrote look_plain.png and look_held.png in ", out)
	get_tree().quit()
