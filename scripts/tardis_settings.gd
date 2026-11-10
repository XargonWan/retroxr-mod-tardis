## What the player chose, kept between runs: which console room the TARDIS takes them to, and which
## exterior it wears. A small JSON file under user://mods/xenu.tardis/ (nothing secret in it).
##
## Both are ids of a table (console_rooms.gd, tardis_exteriors.gd). An id this version does not know
## (a mod removed, a file edited) reads as the default.
extends RefCounted

const PATH := "user://mods/xenu.tardis/settings.json"
const ConsoleRooms := preload("res://mods/xenu.tardis/scripts/console_rooms.gd")
const Exteriors := preload("res://mods/xenu.tardis/scripts/tardis_exteriors.gd")

## Where the settings are read from and written to; the tests point this at a scratch file.
static var path := PATH


static func load_settings() -> Dictionary:
	var out := {"console": ConsoleRooms.DEFAULT_ID, "exterior": Exteriors.DEFAULT_ID}
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		out["console"] = ConsoleRooms.resolve_id(str((parsed as Dictionary).get("console", "")))
		out["exterior"] = Exteriors.resolve_id(str((parsed as Dictionary).get("exterior", "")))
	return out


static func save_settings(console: String, exterior: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[xenu.tardis] cannot write %s" % path)
		return
	f.store_string(JSON.stringify({"console": ConsoleRooms.resolve_id(console),
		"exterior": Exteriors.resolve_id(exterior)}, "  "))


static func console() -> String:
	return str(load_settings()["console"])


static func exterior() -> String:
	return str(load_settings()["exterior"])


static func set_console(id: String) -> void:
	save_settings(id, exterior())


static func set_exterior(id: String) -> void:
	save_settings(console(), id)
