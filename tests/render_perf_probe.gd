## What a console room costs to draw, from the real scene: the renderer's own counters (draw calls, triangles, video memory)
## from the player's eye, looking ahead and back, plus what the room is made of (meshes, triangles, materials, lights, the biggest
## textures). Needs a window; the Quest runs the mobile renderer, so also try `--rendering-method mobile`:
##
##   ID=10 godot --path RetroXR --rendering-method mobile res://mods/xenu.tardis/tests/render_perf_probe.tscn
##
## ID is the room's table id (default: the first). Prints `[perf] ...` lines; nothing is written.
extends Node


func _ready() -> void:
	var id := OS.get_environment("ID")
	if id.is_empty():
		id = "1"
	var row := (load("res://mods/xenu.tardis/scripts/console_rooms.gd") as GDScript).call("entry", id) as Dictionary
	var root := (load(str(row["scene"])) as PackedScene).instantiate()
	var t0 := Time.get_ticks_msec()
	add_child(root)
	print("[perf] the room is built in %d ms (model, colliders, lights, console)" % (Time.get_ticks_msec() - t0))
	for i in 40:
		await get_tree().process_frame
	var room := root.get_node("ConsoleRoom")
	var rig := root.get_node("PlayerRig") as Node3D
	print("[perf] room %s, renderer %s" % [id, RenderingServer.get_current_rendering_method()])
	_census(root)
	# experiments: HIDE=model hides the room's model, HIDE=lights frees its lights, HIDE=glow turns the glow off
	for what in OS.get_environment("HIDE").split(","):
		match what:
			"model":
				(room.model as Node3D).visible = false
			"lights":
				for l in root.find_children("*", "Light3D", true, false):
					l.free()
			"cullback", "vertex", "nospec":
				var seen := {}
				for mi in (room.model as Node3D).find_children("*", "MeshInstance3D", true, false):
					var mesh := (mi as MeshInstance3D).mesh
					for i in mesh.get_surface_count():
						var m := mesh.surface_get_material(i) as BaseMaterial3D
						if m == null or seen.has(m):
							continue
						seen[m] = true
						match what:
							"cullback":
								m.cull_mode = BaseMaterial3D.CULL_BACK
							"vertex":
								m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
							"nospec":
								m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
								m.metallic = 0.0
								m.roughness = 1.0
			"glow":
				for w in root.find_children("*", "WorldEnvironment", true, false):
					(w as WorldEnvironment).environment.glow_enabled = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var cam := Camera3D.new()
	cam.fov = 90.0
	add_child(cam)
	cam.current = true
	var eye := rig.global_position + Vector3(0, 1.6, 0)
	var c: Array = (room.meta.get("door", {}) as Dictionary).get("centre", [0, 1.2, 0])
	var door_at := Vector3(float(c[0]), float(c[1]), float(c[2])) * float(room.room_scale)
	var total_gpu := 0.0
	var shots := {"ahead": Vector3(0, 1.2, 0), "back": door_at, "left": eye + Vector3(-4, 0, 0), "right": eye + Vector3(4, 0, 0)}
	for shot: String in shots:
		cam.global_position = eye
		cam.look_at(shots[shot])
		for i in 8:
			await get_tree().process_frame
		var gpu := 0.0
		var cpu := 0.0
		for i in 30:
			await get_tree().process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		print("[perf] view %-6s script+scene process %.2f ms, physics process %.2f ms, fps %d, nodes %d, physics bodies %d" % [shot,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])
		total_gpu += gpu / 30.0
		print("[perf] view %-6s frame: gpu %.2f ms, render cpu %.2f ms" % [shot, gpu / 30.0, cpu / 30.0])
		print("[perf] view %-6s draw calls %4d  objects %4d  triangles %7d" % [shot,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	print("[perf] MEAN gpu %.2f ms over %d views (HIDE=%s)" % [total_gpu / shots.size(), shots.size(), OS.get_environment("HIDE")])
	print("[perf] video memory %.0f MB (textures %.0f MB, buffers %.0f MB)" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0])
	get_tree().quit()


## What the room is made of, counted in the scene tree.
func _census(root: Node) -> void:
	var meshes := 0
	var surfaces := 0
	var tris := 0
	var seen_mat := {}
	var blend := 0
	var two_sided := 0
	var textures := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		meshes += 1
		for s in mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			tris += (idx as PackedInt32Array).size() / 3 if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var m := mesh.surface_get_material(s)
			if m != null and not seen_mat.has(m):
				seen_mat[m] = true
				var b := m as BaseMaterial3D
				if b != null:
					if OS.get_environment("MATS") == "1":
						print("[perf]   material %-24s albedo %s normal %s orm %s%s" % [b.resource_name, _dims(b.albedo_texture), _dims(b.normal_texture), _dims(b.orm_texture), " BLEND" if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else ""])
					blend += 1 if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0
					two_sided += 1 if b.cull_mode == BaseMaterial3D.CULL_DISABLED else 0
					for t: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_EMISSION]:
						var tex := b.get_texture(t as BaseMaterial3D.TextureParam)
						if tex != null:
							textures[tex] = true
	var lights := root.find_children("*", "Light3D", true, false)
	var omni := 0
	for l in lights:
		omni += 1 if l is OmniLight3D else 0
	print("[perf] meshes %d, surfaces %d, triangles %d, materials %d (alpha %d, two-sided %d), lights %d (omni %d)" % [meshes, surfaces, tris, seen_mat.size(), blend, two_sided, lights.size(), omni])
	var biggest := []
	var bytes := 0
	for tex: Texture2D in textures:
		var img := tex.get_image()
		if img == null:
			continue
		var b := img.get_data_size()
		bytes += b
		biggest.append([b, "%dx%d fmt %d" % [img.get_width(), img.get_height(), img.get_format()]])
	biggest.sort()
	biggest.reverse()
	print("[perf] textures %d, %.0f MB as loaded (CPU copy, no mips); biggest: %s" % [textures.size(), bytes / 1048576.0, biggest.slice(0, 5)])


func _dims(t: Texture2D) -> String:
	return "-" if t == null else "%dx%d" % [t.get_width(), t.get_height()]
