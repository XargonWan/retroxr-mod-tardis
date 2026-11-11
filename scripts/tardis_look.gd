## How an exterior's materials are dressed, shared by the TARDIS itself and by the doors seen from inside a console room.
##
## The model's blue is a dark, greyish navy that is near black in a room, and its white (the windows, the lettering of
## POLICE PUBLIC CALL BOX, the notice) is plain white: lit, they are the TARDIS of the show. The exterior's row in
## tardis_exteriors.gd says which materials: `glow_materials` (white, given an emission of `glow_energy`) and `paint`
## (material name -> a lighter colour; `paint_glow`, an emission, is there but the table leaves it out: it flattens the panels).
## A copy of the surface's own material goes on the mesh as its override: the model's cached material is shared by every
## TARDIS, and the see-through ghost starts from the override, so it keeps the dress.
extends RefCounted


static func dress(mi: MeshInstance3D, row: Dictionary) -> void:
	if mi.mesh == null:
		return
	var glow_names: Array = row.get("glow_materials", [])
	var glow := float(row.get("glow_energy", 0.0))
	var paint: Dictionary = row.get("paint", {})
	var paint_glow := float(row.get("paint_glow", 0.0))
	for s in mi.mesh.get_surface_count():
		var own := mi.get_surface_override_material(s)
		var src := (own if own != null else mi.mesh.surface_get_material(s)) as StandardMaterial3D
		if src == null:
			continue
		var material_name := src.resource_name
		var is_glow := glow > 0.0 and glow_names.has(material_name)
		var is_paint := paint.has(material_name)
		if not is_glow and not is_paint:
			continue
		var m := src.duplicate() as StandardMaterial3D
		if is_paint:
			var colour: Color = paint[material_name]
			m.albedo_color = colour
			if paint_glow > 0.0:
				m.emission_enabled = true
				m.emission = colour
				m.emission_energy_multiplier = paint_glow
		if is_glow:
			m.emission_enabled = true
			m.emission = Color.WHITE
			m.emission_energy_multiplier = glow
		mi.set_surface_override_material(s, m)
