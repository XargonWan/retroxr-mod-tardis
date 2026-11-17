## The console rooms this mod ships: one per TARDIS interior. Everything that differs from one to the
## next is here, so a second interior is a row and a GLB.
##
## The ids ("10") and the room ids ("xenu.tardis:console_10") are permanent once anyone has saved in
## a room: RetroXR keeps the room's slots under its id.
##
## A console room is a "secret room": it is not meant to be in the SCENE tab's list, only reached by
## the TARDIS door. RetroXR cannot hide a mod's room yet, so `hidden` is asked for in the room's row
## (ignored by a RetroXR that does not know it) and the card is there until it can.
extends RefCounted

const DEFAULT_ID := "1"
const ROOM_PREFIX := "xenu.tardis:console_"
const SCENE_DIR := "res://mods/xenu.tardis/scenes/"
const MODEL_DIR := "res://mods/xenu.tardis/models/interior/"

## id -> {label, scene, glb, meta (the JSON a converter wrote next to the GLB), collision (the low-poly GLB of
## what is to be bumped into: pillars, console, railings; empty for none), scale (the model is drawn at this
## fraction of its own size), console (radius, height of the console in the model's own metres), door_light
## (the doorway is a dark alcove: light it), floor (the steps, below), solids (the JSON tools/convert_solids.py made: boxes for
## what is solid in the model and not in `collision`, pillars and railings), door_leaves (the doorway has a pair of police box
## doors in it, the exterior's own leaves seen from inside), emission_cap (no emissive material of the model glows more than
## this), menu_out (model metres: how far from the console's middle its menu hangs, 0 = over the console), console_cylinder (false: no cylinder under the console, the solids are its collision), floor_offset (metres: the floor to walk on is this much lower than the model's, negative; 0 for none), seats ([{at (model metres), seat_height, eye_height, width, depth}]: where a player can sit, facing the middle)}.
## The lights of a room are `lights`, below.
const ROOMS := {
	"1": {
		"label": "1st Doctor's Console Room",
		"scene": SCENE_DIR + "console_room_1.tscn",
		"glb": MODEL_DIR + "1.glb",
		"meta": MODEL_DIR + "1.json",
		"collision": "",
		"scale": 1.0,
		"console": Vector2(0.97, 0.97),
		"door_light": false,
		# The way in and out is the hexagonal double door with the six roundels on the -Z wall (measured on the model: the wall there is
		# 4.38 m from the console's axis, the door on that axis at x 0.14, about 2.1 m wide and 2.4 high), not the blue-grey panel on the
		# +Z wall that the converter picked (that one is left as scenery). The player comes in at it and faces the console (+Z).
		"door": {"centre": [0.142, 1.2, -4.379], "size": [2.1, 2.4]},
		"floor": [],
		"solids": "",
		"door_leaves": false,
		# The wooden armchair against the wall, beside the round table (measured on the model: its seat is a square 0.65 m
		# across, 0.47 m high, centred on x -2.97, z 2.875; the room's middle is the way it faces)
		"seats": [{"at": Vector3(-2.97, 0.0, 2.875), "seat_height": 0.47, "eye_height": 1.12, "width": 0.6, "depth": 0.6}],
	},
	"10": {
		"label": "10th Doctor's Console Room",
		"scene": SCENE_DIR + "console_room_10.tscn",
		"glb": MODEL_DIR + "10.glb",
		"meta": MODEL_DIR + "10.json",
		# No collision GLB any more: its hulls were up to 4.4 m wide (the platform's slabs stuck 6 cm out of the lowered floor, the console's
		# blocks reached 3 m from its middle). What is solid is found in the model itself: 10_core.json (the console and the rotor, 10 cm
		# cells, inside r 2.6) and 10_solids.json (the pillars and railings, 25 cm cells, outside it).
		"collision": "",
		# 0.55 made the door 1.40 m high and the console 0.77 m: a player is taller than the doorway and "walks too high". At
		# 0.7 the door is 1.78 m, the console 0.98 m, the room 13 m across.
		"scale": 0.7,
		# The doorway the model really has (measured with rays: the alcove's walls at x -0.37 and 1.10, its top at 2.55, the floor
		# at 0), in the model's own metres: the pair of doors and the light behind them are made to fit it.
		"opening": {"x0": -0.37, "x1": 1.10, "top": 2.55},
		"console": Vector2(1.4, 1.4),
		"door_light": true,
		"solids": [MODEL_DIR + "10_core.json", MODEL_DIR + "10_solids.json"],
		"console_cylinder": false,
		# the console's menu hangs this far from its middle (model metres, toward the player): beyond the console's edge (the solids
		# reach 1.45) and not over its top, where the menu was inside the model and behind a solid
		"menu_out": 2.1,
		"door_leaves": true,
		"emission_cap": 2.0,
		# "walking too high": the walkable floor, its ramps and the bottoms of the pillars' boxes are 5.5 cm under where the model's
		# floor is (the user asked for 5 to 6 cm, twice)
		"floor_offset": -0.055,
		"seats": [],
		# The 10th's floor is in steps (measured on the model): the outer floor at 0, a ring at 0.67 from r = 6 in,
		# a platform at 0.96 from r = 3.5 in. A vertical step of 0.37 m is no way to walk, so the floor a player
		# stands on is a RAMP up each (radius, height) from the outside in, laid ON the lower floor so a foot floats a
		# little over it rather than sinking into the platform. Radii and heights in the model's own metres.
		# (measured again on the model: the ring's edge is at r 5.9 and the platform's at 3.7; the ramps are as narrow as walking
		# up them allows, 0.8 m, so that the floor does not float over the visible one by up to 0.3 m as the first ones did)
		"floor": [[6.6, 0.0], [5.8, 0.67], [4.4, 0.67], [3.6, 0.96], [1.5, 0.96]],
	},
}


## How many lights a room may have: the Quest's mobile renderer lights every pixel with every omni that reaches it (8 at most), and
## the room's lights reach all of it. Ten of them made both rooms very slow in a headset (2026-11-12).
const MAX_LIGHTS := 4


## The lights of a room: [position (the model's own metres), colour, energy, range]. They are what the photographs of
## the sets show. The 10th Doctor's (2005-2010) is DARK: the light is the yellow-amber roundels in the walls, a
## cyan glow from the time rotor and from under the console, a warm wash along the top of the walls. The 1st
## Doctor's (1963) is a bright white room, its roundels lit from behind in a cool white, the rotor's bulb warm.
static func lights(id: String) -> Array:
	var out: Array = []
	if resolve_id(id) == "10":
		# FOUR lights, not ten: the Quest's mobile renderer lights every pixel with up to 8 omnis per object and these overlap the whole
		# room, so each light cut is a cut of every pixel's work. The six roundel lights became two, farther apart, twice as strong.
		out.append([Vector3(0, 2.6, 0), Color(0.35, 0.95, 0.9), 0.5, 11.0])
		for i in 2:
			var a := PI * i + 0.3
			out.append([Vector3(cos(a) * 5.5, 3.0, sin(a) * 5.5), Color(1.0, 0.72, 0.18), 2.0, 12.0])
		# a soft amber light in front of the way out, so that its doors are not a black hole (in model metres)
		out.append([Vector3(0.36, 1.8, 7.9), Color(1.0, 0.8, 0.45), 0.5, 3.5])
	else:
		# the room's own light is its ambient (console_room_1.tscn); the lamps only shape it: strong ones burnt the floor white round them
		out.append([Vector3(0, 2.4, 0), Color(1.0, 0.92, 0.78), 0.45, 10.0])
		out.append([Vector3(0, 5.0, 0), Color(1.0, 1.0, 1.0), 0.25, 12.0])
		for i in 2:
			var a := PI * i + PI / 8.0
			out.append([Vector3(cos(a) * 3.2, 1.8, sin(a) * 3.2), Color(0.9, 0.93, 1.0), 0.3, 8.0])
	return out


## The height of the floor a player stands on at radius `r` (the model's own metres, from the console's middle):
## 0 where the table lists no `floor`, else the table's profile, joined with straight lines.
static func floor_height(id: String, r: float) -> float:
	var profile: Array = entry(id).get("floor", [])
	if profile.is_empty() or r >= float((profile[0] as Array)[0]):
		return 0.0
	for i in range(1, profile.size()):
		var outer := profile[i - 1] as Array
		var inner := profile[i] as Array
		if r >= float(inner[0]):
			var span := float(outer[0]) - float(inner[0])
			var k := (float(outer[0]) - r) / span if span > 0.0 else 1.0
			return lerpf(float(outer[1]), float(inner[1]), k)
	return float((profile[profile.size() - 1] as Array)[1])


static func entry(id: String) -> Dictionary:
	var row: Dictionary = ROOMS.get(id, ROOMS[DEFAULT_ID])
	return row


static func resolve_id(id: String) -> String:
	return id if ROOMS.has(id) else DEFAULT_ID


static func room_id_of(id: String) -> String:
	return ROOM_PREFIX + resolve_id(id)


## The table id of a room id ("xenu.tardis:console_10" -> "10"), or "" when it is not one of ours.
static func id_of_room(room_id: String) -> String:
	if not room_id.begins_with(ROOM_PREFIX):
		return ""
	var id := room_id.trim_prefix(ROOM_PREFIX)
	return id if ROOMS.has(id) else ""


static func is_console_room(room_id: String) -> bool:
	return not id_of_room(room_id).is_empty()


static func ids() -> Array:
	return ROOMS.keys()
