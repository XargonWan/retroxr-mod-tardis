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
## (the doorway is a dark alcove: light it)}. The lights of a room are `lights`, below.
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
		"floor": [],
	},
	"10": {
		"label": "10th Doctor's Console Room",
		"scene": SCENE_DIR + "console_room_10.tscn",
		"glb": MODEL_DIR + "10.glb",
		"meta": MODEL_DIR + "10.json",
		"collision": MODEL_DIR + "10_collision.glb",
		"scale": 0.55,
		"console": Vector2(1.75, 1.4),
		"door_light": true,
		# The 10th's floor is in steps (measured on the model): the outer floor at 0, a ring at 0.67 from r = 6 in,
		# a platform at 0.96 from r = 3.5 in. A vertical step of 0.37 m is no way to walk, so the floor a player
		# stands on is a RAMP up each (radius, height) from the outside in, laid ON the lower floor so a foot floats a
		# little over it rather than sinking into the platform. Radii and heights in the model's own metres.
		"floor": [[7.0, 0.0], [5.8, 0.67], [4.6, 0.67], [3.6, 0.96], [1.5, 0.96]],
	},
}


## The lights of a room: [position (the model's own metres), colour, energy, range]. They are what the photographs of
## the sets show. The 10th Doctor's (2005-2010) is DARK: the light is the yellow-amber roundels in the walls, a
## cyan glow from the time rotor and from under the console, a warm wash along the top of the walls. The 1st
## Doctor's (1963) is a bright white room, its roundels lit from behind in a cool white, the rotor's bulb warm.
static func lights(id: String) -> Array:
	var out: Array = []
	if resolve_id(id) == "10":
		out.append([Vector3(0, 2.6, 0), Color(0.35, 0.95, 0.9), 2.2, 11.0])
		out.append([Vector3(0, 1.2, 0), Color(0.25, 0.9, 0.85), 1.2, 6.0])
		out.append([Vector3(0, 7.0, 0), Color(1.0, 0.78, 0.3), 0.6, 14.0])
		for i in 6:
			var a := TAU * i / 6.0 + 0.3
			out.append([Vector3(cos(a) * 7.0, 3.0, sin(a) * 7.0), Color(1.0, 0.72, 0.18), 1.1, 9.0])
	else:
		out.append([Vector3(0, 2.4, 0), Color(1.0, 0.92, 0.78), 1.0, 10.0])
		out.append([Vector3(0, 5.0, 0), Color(1.0, 1.0, 1.0), 0.55, 12.0])
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			out.append([Vector3(cos(a) * 3.4, 1.8, sin(a) * 3.4), Color(0.9, 0.93, 1.0), 0.45, 7.0])
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
