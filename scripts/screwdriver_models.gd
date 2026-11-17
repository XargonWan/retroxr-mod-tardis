## The sonic screwdrivers this mod ships: what each is called, where its GLB and scene are, and
## what its light does. Pure data and lookups (no nodes), so the headless suite can check it.
##
## The ids are the Doctors' numbers ("10", "11"...): never rename one; they are what is saved.
##
## ONE OBJECT, "Sonic Screwdriver", whose Doctors are its colours: pressed it spawns the 10th Doctor's
## (the first of `variant_rows()`), held it asks which, as a console that comes in colours does. The
## id picked is given to the object as `model_variant` before it enters the room and is saved with it.
## That needs RetroXR to offer `variants` on a mod object's row (SpawnCatalog.objects); one that does not
## ignores them and offers the 10th Doctor's alone.
##
## Each GLB is made by tools/build_models.py from the original in src.local/: the same orientation
## for all (the business end toward -Z, the origin on the grip, metres), the light's mesh named
## "Led", and inside the Quest 3's budget (see README.txt).
extends RefCounted

const DEFAULT_ID := "10"
const MODEL_DIR := "res://mods/xenu.tardis/models/screwdriver/"
## The type string written into save slots: permanent.
const TYPE := "xenu.tardis:sonic_screwdriver"
const SCENE := "res://mods/xenu.tardis/scenes/sonic_screwdriver.tscn"
const LABEL := "Sonic Screwdriver"

## id -> {label, led (it has a light in the show's canon AND a mesh to light), led_color, brighten (a multiplier on the model's
## colours: a texture that reads black in a dim room), metallic_max (a cap on how metallic it is: without reflections in the
## room a metal surface shows its colour only as black)}.
## A `led` model's GLB has a mesh named "Led". The 2nd to 5th and the 12th have no light in the show
## or no part of the model to light.
const MODELS := {
	"2": {"label": "2nd Doctor's Screwdriver", "led": false},
	"3": {"label": "3rd Doctor's Screwdriver", "led": false},
	"4": {"label": "4th Doctor's Screwdriver", "led": false},
	"5": {"label": "5th Doctor's Screwdriver", "led": false},
	"10": {"label": "10th Doctor's Screwdriver", "led": true, "led_color": Color(0.25, 0.5, 1.0)},
	"11": {"label": "11th Doctor's Screwdriver", "led": true, "led_color": Color(0.3, 1.0, 0.75)},
	"12": {"label": "12th Doctor's Screwdriver", "led": false, "brighten": 2.2},
	"13": {"label": "13th Doctor's Screwdriver", "led": true, "led_color": Color(1.0, 0.6, 0.2), "brighten": 1.2, "metallic_max": 0.1},
}


## The row for `id`, or the default's when `id` is empty or unknown.
static func entry(id: String) -> Dictionary:
	var row: Dictionary = MODELS.get(id, MODELS[DEFAULT_ID])
	return row


## The id that `entry(id)` actually answers for.
static func resolve_id(id: String) -> String:
	return id if MODELS.has(id) else DEFAULT_ID


static func glb_of(id: String) -> String:
	return MODEL_DIR + resolve_id(id) + ".glb"


## Ids in the order of the picker: the default first.
static func ids() -> Array:
	var out: Array = [DEFAULT_ID]
	for id: String in MODELS:
		if id != DEFAULT_ID:
			out.append(id)
	return out


## "10th" for a button of the object's menu: the label's first word. The page is 340 px wide and a button of "10th Doctor"
## took a third of it, so the eighth Doctor was off the edge.
static func short_label(id: String) -> String:
	return str(entry(id)["label"]).get_slice(" ", 0)


## How many buttons one row of the object's menu holds.
const MENU_ROW := 4


## The Doctors for the object's menu, by number and MENU_ROW to a row: [{caption, ids}].
static func menu_rows() -> Array:
	var ids: Array = MODELS.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var rows: Array = []
	for start in range(0, ids.size(), MENU_ROW):
		var chunk := ids.slice(start, start + MENU_ROW)
		rows.append({"caption": "Doctor: %s to %s" % [short_label(chunk[0]), short_label(chunk[-1])], "ids": chunk})
	return rows


## The rows the hold-to-choose picker takes ({id, label, color}); the first is the default.
static func variant_rows() -> Array:
	var rows: Array = []
	for id: String in ids():
		var row: Dictionary = MODELS[id]
		rows.append({"id": id, "label": row["label"], "color": row.get("led_color", Color(0.7, 0.7, 0.72))})
	return rows
