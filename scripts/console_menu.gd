## The console at the middle of the room, as something to point at: a pointable collider and the
## `toggle_options_ui` every RetroXR object answers (point at it and press the left thumbstick, Tab on
## a desktop). The menu it opens (console_panel.gd) changes the console room, resets this one and
## changes the TARDIS's exterior.
extends Node3D

const PANEL := preload("res://mods/xenu.tardis/scripts/console_panel.gd")

var pointer: StaticBody3D = null


func setup(radius: float, height: float) -> void:
	# layer 21: what the pointing raycast looks for. Without it the console cannot be pointed at.
	pointer = StaticBody3D.new()
	pointer.name = "PointerArea"
	pointer.collision_layer = 1 << 20
	pointer.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height + 0.8
	cs.shape = shape
	cs.position = Vector3(0, (height + 0.8) / 2.0, 0)
	pointer.add_child(cs)
	add_child(pointer)


func toggle_options_ui(camera: Node3D) -> void:
	PANEL.toggle_for(self, camera)
