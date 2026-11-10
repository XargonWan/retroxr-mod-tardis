## Writes two screenshots of the screwdriver in the engine, off and lit, for a human to look at.
## Needs a window (no --headless):
##
##   OUT=/some/dir godot --path RetroXR res://mods/xenu.tardis/tests/render_probe.tscn
extends Node

const SCENE := "res://mods/xenu.tardis/scenes/sonic_screwdriver.tscn"


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 500)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	var sd := (load(SCENE) as PackedScene).instantiate()
	sd.freeze = true
	vp.add_child(sd)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.position = Vector3(0.08, 0.04, -0.2)
	cam.look_at(Vector3(0, 0, -0.09))
	for state in ["off", "on"]:
		if state == "on":
			sd.begin_use()
		for i in 4:
			await get_tree().process_frame
		var img := vp.get_texture().get_image()
		img.save_png(out.path_join("screwdriver_%s.png" % state))
		print("[probe] wrote ", out.path_join("screwdriver_%s.png" % state))
	get_tree().quit()
