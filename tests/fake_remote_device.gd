## A stand-in for a TV: what RemoteTarget asks of a device, and a count of what was pressed on it.
## Its body is on the pointable layer (21), as a real device's PointerArea is.
extends Node3D

var presses: Array = []
var cells: Array = [{"id": "power", "glyph": "power", "col": 0, "row": 0, "span": 3}]
var power_enabled := true
## What the outline child was told last: null never told.
var outlined: Variant = null


func _init() -> void:
	RemoteTarget.join(self)


func _ready() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 20
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	var hl := Node.new()
	hl.name = "PickableHighlight"
	hl.set_script(load("res://mods/xenu.tardis/tests/fake_highlight.gd"))
	add_child(hl)


func remote_layout() -> Array:
	return cells


func remote_activate(id: String) -> void:
	presses.append(id)


func remote_cell_enabled(_id: String) -> bool:
	return power_enabled
