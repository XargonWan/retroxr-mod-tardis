## TARDIS XR -- a RetroXR mod.
##
## Adds the Sonic Screwdriver to the SPAWN menu's Objects tab: one row, the Doctors' models its colours
## (the 10th Doctor's by default, then the 2nd, 3rd, 4th, 5th, 11th, 12th and 13th). The TARDIS,
## console rooms and the rest come later.
##
## Also the TARDIS exterior: summoned by the screwdriver, and on the SPAWN menu's Objects tab too.
##
## The type strings are written into save slots; each is permanent once anyone has used it. They
## come from screwdriver_models.gd.
extends RetroMod

const Models := preload("res://mods/xenu.tardis/scripts/screwdriver_models.gd")
const ConsoleRooms := preload("res://mods/xenu.tardis/scripts/console_rooms.gd")

## The TARDIS exterior. Its type string is written into save slots: permanent once anyone has used it.
const TARDIS_TYPE := "xenu.tardis:tardis"  # = Tardis.TYPE
const TARDIS_SCENE := "res://mods/xenu.tardis/scenes/tardis.tscn"


func register(api: ModApi) -> void:
	api.log_line("registering; console rooms: %s" % str(ConsoleRooms.ids()))
	# One screwdriver; the Doctors are its colours (hold its row to choose).
	api.register_object(Models.TYPE, Models.SCENE, {"label": Models.LABEL, "variants": Models.variant_rows()})
	api.register_object(TARDIS_TYPE, TARDIS_SCENE, {"label": "TARDIS"})
	# One console room per interior. They are "secret": reached by the TARDIS door and not meant for the
	# SCENE tab, so `hidden` is asked for (a RetroXR that does not know it ignores it and lists them).
	# has_slots: what the player puts in one is saved and restored like in any room.
	for id: String in ConsoleRooms.ids():
		var row := ConsoleRooms.entry(id)
		api.register_room({"id": ConsoleRooms.room_id_of(id), "path": row["scene"],
			"menu_title": row["label"], "title": str(row["label"]).to_upper(),
			"has_slots": true, "hidden": true})
