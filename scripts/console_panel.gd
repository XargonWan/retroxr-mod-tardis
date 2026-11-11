## ConsolePanel -- the console's menu: opened like every object's (point at the console and press the
## left thumbstick, Tab on a desktop), it floats just over the console's top, on the side the player is
## standing, and turns to face them (it used to hang 2.6 m out toward the player and so wandered round the
## room: the menu belongs ON the console). What its buttons do:
##   console room  -> kept (tardis_settings.gd); when the player is IN a console room, they are taken to
##                    the one chosen now (SceneManager.change_scene),
##   exterior      -> kept, and the TARDIS they will step out of wears it,
##   reset         -> ConsoleRoom.reset_room: everything the player put in this room goes.
extends FloatingObjectPanel3D

const PANEL_SCENE := preload("res://mods/xenu.tardis/scenes/console_panel.tscn")
const Settings := preload("res://mods/xenu.tardis/scripts/tardis_settings.gd")
const ConsoleRooms := preload("res://mods/xenu.tardis/scripts/console_rooms.gd")
const Travel := preload("res://mods/xenu.tardis/scripts/tardis_travel.gd")
const NODE_NAME := "ConsolePanel"
## Where it floats: over the console's top by this much (the panel is 0.62 m high: its middle is half of that
## above the top, and a few centimetres of air), and this fraction of the console's radius toward the player.
const HOVER := 0.34
const TOWARD_PLAYER := 0.5

var _console: Node3D = null

@onready var _viewport_node: XRToolsViewport2DIn3D = $ConsoleViewport


static func toggle_for(console: Node3D, camera: Node3D) -> void:
	if not is_instance_valid(console):
		return
	var panel := console.get_node_or_null(NODE_NAME)
	if panel == null:
		panel = PANEL_SCENE.instantiate()
		panel.name = NODE_NAME
		console.add_child(panel)
	if panel.visible:
		panel.hide_panel()
	else:
		panel.show_for(console, camera)


func show_for(console: Node3D, camera: Node3D) -> void:
	_console = console
	_camera = camera
	global_position = _anchor()
	# the menu is INSIDE the console's pointing cylinder, which would catch the ray before the menu does: it is let be
	# while the menu is up (the menu's own close button, or the way out, shuts it)
	_set_console_pointable(false)
	visible = true
	_ensure_ui_connected()
	_populate()


func hide_panel() -> void:
	super()
	_set_console_pointable(true)


func _set_console_pointable(on: bool) -> void:
	if is_instance_valid(_console) and _console.has_method("set_pointable"):
		_console.call("set_pointable", on)


func _get_ui() -> Control:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if vp == null or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as Control


func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var ui := _get_ui()
	if ui == null:
		call_deferred("_ensure_ui_connected")
		return
	ui.close_requested.connect(hide_panel)
	ui.leave_requested.connect(_on_leave)
	ui.console_chosen.connect(_on_console_chosen)
	ui.exterior_chosen.connect(_on_exterior_chosen)
	ui.hum_toggled.connect(_on_hum_toggled)
	ui.reset_confirmed.connect(_on_reset)
	_ui_connected = true


func _populate() -> void:
	var ui := _get_ui()
	if ui == null:
		call_deferred("_populate")
		return
	var s := Settings.load_settings()
	ui.populate(str(s["console"]), str(s["exterior"]), bool(s["hum"]))


func _on_console_chosen(id: String) -> void:
	Settings.set_console(id)
	var manager := Travel.manager_of(self)
	if manager != null and Travel.in_console_room(manager) and ConsoleRooms.room_id_of(id) != str(manager.get("current_scene_id")):
		manager.call("change_scene", ConsoleRooms.room_id_of(id))
		return
	_populate()


func _on_hum_toggled(on: bool) -> void:
	Settings.set_hum(on)
	var room := _console.get_parent() if is_instance_valid(_console) else null
	if room != null and room.has_method("set_hum"):
		room.call("set_hum", on)
	_populate()


func _on_exterior_chosen(id: String) -> void:
	Settings.set_exterior(id)
	if not Travel.origin.is_empty():
		Travel.origin["exterior"] = id
	_populate()


## The way out from the menu: the room's own door press (its sound, then TardisTravel.leave).
func _on_leave() -> void:
	hide_panel()
	var room := _console.get_parent() if is_instance_valid(_console) else null
	if room != null and room.has_method("press_door"):
		room.call("press_door")


func _on_reset() -> void:
	var room := _console.get_parent() if is_instance_valid(_console) else null
	if room != null and room.has_method("reset_room"):
		room.call("reset_room")


func _target_node() -> Node3D:
	return _console


func _float_height() -> float:
	return _console_height() + HOVER


func _console_height() -> float:
	return float(_console.get("height")) if is_instance_valid(_console) and _console.get("height") != null else 1.0


func _anchor() -> Vector3:
	if not is_instance_valid(_console):
		return global_position
	var cam := _camera if is_instance_valid(_camera) else get_viewport().get_camera_3d()
	var to_cam := Vector3(0, 0, 1)
	if cam != null:
		to_cam = Vector3(cam.global_position.x - _console.global_position.x, 0.0, cam.global_position.z - _console.global_position.z)
	if to_cam.length() < 0.01:
		to_cam = Vector3(0, 0, 1)
	var radius := float(_console.get("radius")) if _console.get("radius") != null else 1.0
	return _console.global_position + to_cam.normalized() * radius * TOWARD_PLAYER + Vector3(0, _float_height(), 0)
