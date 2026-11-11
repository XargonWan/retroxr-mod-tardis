## The TARDIS exteriors this mod ships. Only one so far, but a console room's menu is to offer a
## choice ("cambiare exterior"), so everything that differs from one to the next lives here and the
## TARDIS reads it: its model, the door leaf's name, how far the door opens and the size of its base.
##
## The ids are permanent once anyone has saved a room with one. Each GLB is made by
## tools/convert_tardis.py: origin on the floor in the middle of the base, the front toward +Z,
## the door leaf ("DoorR", its origin on the hinge, so turning it about Y swings it) a direct child.
extends RefCounted

const DEFAULT_ID := "default"
const MODEL_DIR := "res://mods/xenu.tardis/models/tardis/"

## id -> {label, glb, door, door_open_deg, glow_materials + glow_energy (the white parts that are lit), footprint (metres, front to back and across), height,
## inside (the white box behind the open door: size and centre, wholly inside the shell's inner walls at +-0.394
## so that nothing of the model is between it and the doorway)}.
const EXTERIORS := {
	"default": {
		"label": "Police Box",
		"glb": MODEL_DIR + "default.glb",
		"door": "DoorR",
		"door_open_deg": 100.0,
		# The white of the model (the window panes and the lettering of POLICE PUBLIC CALL BOX are Material.001, the door's
		# panes Material.005) is lit as the lantern is, but gently: an emission of this energy, white.
		"glow_materials": ["Material.001", "Material.005"],
		"glow_energy": 0.5,
		# The model's own blue stays as it is: it was painted lighter once (tardis_look.gd can: a `paint` table, material name ->
		# colour) and the user preferred the original.
		# A dark core inside the shell while the door is shut (from the floor to 1.72 m, under the sign: at the roof, 2.05, its top showed
		# through the corners as black blocks): a crack at an edge of the door must show dark, never the white
		# panes of the far wall. It is gone while the door is open (the white light behind it is what shows then).
		"core_size": Vector3(0.7, 1.57, 0.7),
		"core_center": Vector3(0.0, 0.935, 0.0),
		"footprint": Vector2(1.1, 1.1),
		"height": 2.3,
		"inside_size": Vector3(0.7, 1.63, 0.7),
		"inside_center": Vector3(0.0, 0.905, 0.0),
		# a flush pane of light in the doorway (the right leaf's opening: x 0 to 0.46, y 0.07 to 1.77, behind the
		# leaf at z 0.39-0.46): whatever the angle or how far the door is open, what is seen in it is light
		"doorway_center": Vector3(0.236, 0.92, 0.375),
		"doorway_size": Vector2(0.4, 1.68),
	},
}


static func entry(id: String) -> Dictionary:
	var row: Dictionary = EXTERIORS.get(id, EXTERIORS[DEFAULT_ID])
	return row


static func resolve_id(id: String) -> String:
	return id if EXTERIORS.has(id) else DEFAULT_ID
