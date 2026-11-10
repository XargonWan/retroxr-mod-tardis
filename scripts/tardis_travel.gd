## Going in and out of the TARDIS: the room you came from, where you stood, and the way back.
##
## IN: the door of a TARDIS keeps where the player was and where the TARDIS stood, and asks
## RetroXR's SceneManager for the console room the player chose. The room they came from is the one
## SceneManager was in (`current_scene_id`): that is the function it already has for changing rooms,
## and it saves the room being left into its slot if it keeps one.
##
## OUT: the console room's door asks SceneManager for that room again. When it is ready the player is
## put where they stood, a TARDIS behind them as if they had stepped out of its door, facing away
## from it. If the room's slot was not saved (a "clean" slot is read-only) the TARDIS is not in the
## room any more: one is put where it was, solid.
##
## What is kept (`origin`) lives as long as the game does and is never saved: restart inside a console
## room and the way out is the platform's default room, with no TARDIS to step out of.
##
## SceneManager is passed in (`manager`), so the suite can give a stand-in: it has to answer
## `current_scene_id`, `change_scene(id)`, `default_room()` and the signal `scene_content_ready(id)`.
extends RefCounted

const Settings := preload("res://mods/xenu.tardis/scripts/tardis_settings.gd")
const ConsoleRooms := preload("res://mods/xenu.tardis/scripts/console_rooms.gd")
const TARDIS_SCENE := "res://mods/xenu.tardis/scenes/tardis.tscn"
## How far in front of the TARDIS's door the player steps out to.
const STEP_OUT := 1.25

## {room, head (Transform3D), tardis (Transform3D), exterior} of the TARDIS last entered.
static var origin: Dictionary = {}
## The room a player in a console room goes out to when nothing was kept: set by the tests, else
## SceneManager's own default.
static var fallback_room := ""


static func manager_of(node: Node) -> Node:
	return node.get_node_or_null("/root/SceneManager")


static func in_console_room(manager: Object) -> bool:
	return manager != null and ConsoleRooms.is_console_room(str(manager.get("current_scene_id")))


## Into the TARDIS: keep the place, change to the active console room. `tardis` is the one whose door
## was pressed.
static func enter(tardis: Node3D, manager: Object = null) -> bool:
	if manager == null:
		manager = manager_of(tardis)
	if manager == null:
		push_warning("[xenu.tardis] no SceneManager: cannot go in")
		return false
	var cam := tardis.get_viewport().get_camera_3d()
	origin = {
		"room": str(manager.get("current_scene_id")),
		"head": cam.global_transform if cam != null else Transform3D.IDENTITY,
		"tardis": tardis.global_transform,
		"exterior": str(tardis.get("exterior")) if tardis.get("exterior") != null else "",
	}
	manager.call("change_scene", ConsoleRooms.room_id_of(Settings.console()))
	return true


## Out of the TARDIS: back to the room kept (the platform's default when none was), and when it is
## ready put the player at its door.
static func leave(from: Node, manager: Object = null) -> bool:
	if manager == null:
		manager = manager_of(from)
	if manager == null:
		return false
	var room := str(origin.get("room", ""))
	var kept := not room.is_empty()
	if not kept:
		room = fallback_room if not fallback_room.is_empty() else str(manager.call("default_room"))
	var tree := from.get_tree()
	var listener: Array[Callable] = [Callable()]
	listener[0] = func(scene_id: String) -> void:
		if scene_id != room:
			return
		manager.disconnect("scene_content_ready", listener[0])
		arrive(tree, kept)
	manager.connect("scene_content_ready", listener[0])
	manager.call("change_scene", room)
	return true


## Where the player stands to step out of a TARDIS at `tardis_xf`: in front of its door, turned away
## from it. Pure.
static func step_out_pose(tardis_xf: Transform3D) -> Transform3D:
	var front := tardis_xf.basis.z
	front.y = 0.0
	front = front.normalized()
	var pos := tardis_xf.origin + front * STEP_OUT
	# a rig's forward is -Z: facing away from the TARDIS is facing along its front, which is where
	# Basis(UP, yaw) turns -Z when sin(yaw) = -front.x and cos(yaw) = -front.z
	var yaw := atan2(-front.x, -front.z)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, tardis_xf.origin.y, pos.z))


## The player has come back to the room: a TARDIS there if there is none, the player at its door.
static func arrive(tree: SceneTree, kept: bool) -> void:
	if tree == null or tree.current_scene == null or not kept:
		return
	var scene := tree.current_scene
	var tardis: Node3D = null
	for n in tree.get_nodes_in_group(&"xenu_tardis"):
		tardis = n as Node3D
		break
	var xf: Transform3D = origin["tardis"]
	if tardis == null:
		tardis = (load(TARDIS_SCENE) as PackedScene).instantiate() as Node3D
		var ex: Variant = origin.get("exterior", "")
		if str(ex) != "":
			tardis.set("exterior", str(ex))
		scene.add_child(tardis)
		tardis.global_transform = xf
	else:
		xf = tardis.global_transform
	var rig := scene.get_node_or_null("PlayerRig")
	if rig is Node3D:
		(rig as Node3D).transform = step_out_pose(xf)
		var body: Variant = rig.get("body")
		if body != null and (body as Object).has_method("reset_for_new_world"):
			(body as Object).call("reset_for_new_world")
