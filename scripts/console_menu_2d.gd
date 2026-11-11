## ConsoleMenu2D -- the TARDIS console's menu, drawn into ConsolePanel's SubViewport.
##
## The way out first (the door is not always easy to reach or to aim at), then three things: which console room the TARDIS door leads to (one per interior), starting this room
## over (it asks twice), and which exterior the TARDIS wears. Choices are a button each, the current
## one marked, because a drop-down is not something to operate with a laser.
##
## Emits (the panel does the work, so this stays a face):
##   leave_requested, console_chosen(id), exterior_chosen(id), hum_toggled(on), reset_confirmed, close_requested
extends Control

signal close_requested
signal leave_requested
signal console_chosen(id: String)
signal exterior_chosen(id: String)
signal hum_toggled(on: bool)
signal reset_confirmed

const ConsoleRooms := preload("res://mods/xenu.tardis/scripts/console_rooms.gd")
const Exteriors := preload("res://mods/xenu.tardis/scripts/tardis_exteriors.gd")

const COLOR_BG := Color(0.03, 0.10, 0.16, 0.96)
const COLOR_HEAD := Color(0.55, 0.95, 0.95)
const COLOR_ON := Color(0.45, 1.0, 0.65)
const COLOR_WARN := Color(1.0, 0.75, 0.35)
## The reset button asks again within this long, else it forgets it was asked.
const CONFIRM_SECONDS := 4.0

var _root: VBoxContainer = null
var _console_id := ""
var _exterior_id := ""
var _confirming := false
var _hum_on := true
var _reset_btn: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 8)
	margin.add_child(_root)
	_rebuild()


## Show the current choices.
func populate(console_id: String, exterior_id: String, hum_on: bool = true) -> void:
	_console_id = console_id
	_exterior_id = exterior_id
	_hum_on = hum_on
	_confirming = false
	if _root != null:
		_rebuild()


func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()
	MenuStyle.close_button(MenuStyle.title_row(_root, "TARDIS Console"), func() -> void: close_requested.emit())
	var leave := Button.new()
	leave.text = "Leave the TARDIS"
	leave.custom_minimum_size = Vector2(0, 50)
	leave.add_theme_color_override("font_color", COLOR_ON)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	_root.add_child(leave)
	_root.add_child(HSeparator.new())
	_heading("Console room")
	for id: String in ConsoleRooms.ids():
		_choice(str(ConsoleRooms.ROOMS[id]["label"]), id == _console_id, func() -> void: console_chosen.emit(id))
	_root.add_child(HSeparator.new())
	_heading("Exterior")
	for id: String in Exteriors.EXTERIORS:
		_choice(str(Exteriors.EXTERIORS[id]["label"]), id == _exterior_id, func() -> void: exterior_chosen.emit(id))
	_root.add_child(HSeparator.new())
	_choice("Interior hum: " + ("on" if _hum_on else "off"), _hum_on, func() -> void: hum_toggled.emit(not _hum_on))
	_root.add_child(HSeparator.new())
	_reset_btn = Button.new()
	_reset_btn.custom_minimum_size = Vector2(0, 46)
	_set_reset_text()
	_reset_btn.pressed.connect(_on_reset_pressed)
	_root.add_child(_reset_btn)


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", COLOR_HEAD)
	_root.add_child(l)


func _choice(text: String, current: bool, on_press: Callable) -> void:
	var b := Button.new()
	b.text = ("✓  " if current else "     ") + text
	b.custom_minimum_size = Vector2(0, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if current:
		b.add_theme_color_override("font_color", COLOR_ON)
	b.pressed.connect(on_press)
	_root.add_child(b)


func _set_reset_text() -> void:
	_reset_btn.text = "Really? Remove everything from this room" if _confirming else "Reset this room"
	_reset_btn.add_theme_color_override("font_color", COLOR_WARN if _confirming else Color.WHITE)


func _on_reset_pressed() -> void:
	if _confirming:
		_confirming = false
		_set_reset_text()
		reset_confirmed.emit()
		return
	_confirming = true
	_set_reset_text()
	get_tree().create_timer(CONFIRM_SECONDS).timeout.connect(func() -> void:
		if _confirming and is_instance_valid(_reset_btn):
			_confirming = false
			_set_reset_text())
