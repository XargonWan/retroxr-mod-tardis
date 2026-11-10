## The TARDIS at fixed see-through levels in RetroXR's bedroom, drawn four ways, to find which one the room's
## own transparent things (the window's glass, its blinds) do not break. Needs a window:
##
##   OUT=/some/dir godot --path RetroXR res://mods/xenu.tardis/tests/render_bedroom_variants.tscn
extends Node

const FRONT := 1.7


func _ready() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var room := (load("res://Scenes/BedroomScene.tscn") as PackedScene).instantiate()
	add_child(room)
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
	var rig := room.get_node("PlayerRig") as Node3D
	var eye := rig.global_position + Vector3(0, 1.6, 0)
	var forward := -rig.global_basis.z
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
	var spot := Vector3(eye.x, rig.global_position.y, eye.z) + forward * FRONT
	t.global_transform = Transform3D(Basis(Vector3.UP, atan2(eye.x - spot.x, eye.z - spot.z)), spot)
	t.set_process(false)
	for alpha: float in [0.85, 0.5]:
		for variant: String in ["pass", "nopass", "solid"]:
			t._ghost_off()
			for mi in t._parts:
				mi.transparency = 0.0
			match variant:
				"pass":
					t._show_parts(alpha, false)
				"nopass":
					t._show_parts(alpha, false)
					for mi in t.find_children("*", "MeshInstance3D", false, false):
						for i in (mi as MeshInstance3D).mesh.get_surface_count():
							var first := (mi as MeshInstance3D).get_surface_override_material(i)
							if first is BaseMaterial3D and (first as BaseMaterial3D).next_pass != null:
								(mi as MeshInstance3D).set_surface_override_material(i, (first as BaseMaterial3D).next_pass)
				"late", "later":
					t._show_parts(alpha, false)
					var base := 50 if variant == "late" else 120
					for mi in t.find_children("*", "MeshInstance3D", false, false):
						for i in (mi as MeshInstance3D).mesh.get_surface_count():
							var first := (mi as MeshInstance3D).get_surface_override_material(i)
							if first is BaseMaterial3D and (first as BaseMaterial3D).next_pass != null:
								first.render_priority = base
								((first as BaseMaterial3D).next_pass).render_priority = base + 1
			for k in 6:
				await get_tree().process_frame
			var path := out.path_join("var_%s_%02d.png" % [variant, int(alpha * 100)])
			get_viewport().get_texture().get_image().save_png(path)
			print("[probe] wrote ", path)
	get_tree().quit()
