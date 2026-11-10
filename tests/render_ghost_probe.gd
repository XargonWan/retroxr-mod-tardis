## Close front views of the TARDIS held at fixed see-through levels, in front of a checkered wall, to see
## whether anything behind its front shows through. Needs a window:
##
##   OUT=/some/dir godot --path RetroXR res://mods/xenu.tardis/tests/render_ghost_probe.tscn
extends Node


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 900)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.5, 0.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	vp.add_child(sun)
	var wall := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(6, 4)
	wall.mesh = quad
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.9, 0.55, 0.2)
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall.material_override = wm
	vp.add_child(wall)
	wall.position = Vector3(0, 1.5, -1.5)
	var t := (load("res://mods/xenu.tardis/scenes/tardis.tscn") as PackedScene).instantiate()
	t.freeze = true
	vp.add_child(t)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 1.4, 2.0)
	cam.look_at(Vector3(0, 1.2, 0))
	cam.fov = 60
	# the ghost at 100% against the model's own materials: any difference is a pop when it ends
	t._show_parts(1.0, false)
	for i in 4:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png(out.path_join("ghost_full.png"))
	t._ghost_off()
	for i in 4:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png(out.path_join("ghost_solid.png"))
	print("[probe] wrote ghost_full / ghost_solid")
	for keep: float in [0.3, 0.6, 0.85]:
		t._show_parts(keep, false)
		for i in 4:
			await get_tree().process_frame
		var path := out.path_join("ghost_%02d.png" % int(keep * 100))
		vp.get_texture().get_image().save_png(path)
		print("[probe] wrote ", path)
	# the same ghost without the depth pass (the blended copies alone): what the pass removes
	t._show_parts(0.6, false)
	for mi in t.find_children("*", "MeshInstance3D", false, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var first := (mi as MeshInstance3D).get_surface_override_material(i)
			if first is BaseMaterial3D and (first as BaseMaterial3D).next_pass != null:
				(mi as MeshInstance3D).set_surface_override_material(i, (first as BaseMaterial3D).next_pass)
	for i in 4:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png(out.path_join("ghost_nopass.png"))
	print("[probe] wrote ghost_nopass")
	get_tree().quit()
