## Screenshots of the TARDIS in the engine: the door shut, ajar, wide, and and the landing in steps.
## Needs a window (no --headless):
##
##   OUT=/some/dir godot --path RetroXR res://mods/xenu.tardis/tests/render_tardis_probe.tscn
extends Node


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 900)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.36, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	vp.add_child(sun)
	var t := (load("res://mods/xenu.tardis/scenes/tardis.tscn") as PackedScene).instantiate()
	t.freeze = true
	vp.add_child(t)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.position = Vector3(2.2, 1.7, 3.6)
	cam.look_at(Vector3(0, 1.1, 0))
	var shots := [["closed", 0.0], ["ajar", 28.0], ["wide", 100.0]]
	for shot in shots:
		(t._door as MeshInstance3D).rotation.y = deg_to_rad(shot[1])
		for i in 4:
			await get_tree().process_frame
		vp.get_texture().get_image().save_png(out.path_join("tardis_%s.png" % shot[0]))
		print("[probe] wrote ", out.path_join("tardis_%s.png" % shot[0]))
	(t._door as MeshInstance3D).rotation.y = 0.0
	# the landing, in steps (the dither is the same on every renderer)
	t.materialize()
	var at := 0.0
	for sec: float in [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 11.5, 14.0]:
		t.advance(sec - at)
		at = sec
		for i in 4:
			await get_tree().process_frame
		var name := "fade_%04.1f" % sec
		vp.get_texture().get_image().save_png(out.path_join(name + ".png"))
		print("[probe] wrote ", out.path_join(name + ".png"), " alpha ", t.alpha_at(sec, t._duration, true))
	get_tree().quit()
