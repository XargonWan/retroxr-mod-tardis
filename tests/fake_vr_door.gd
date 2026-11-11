## A stand-in for RetroXR's VRDoor (res://Scripts/Objects/room/vr_door.gd) with the same surface the TARDIS uses, because that script
## does not compile where the engine's extensions are missing (this host). Tardis.door_script_path points at it in the suite.
extends Node3D

signal unlatched
signal latched
signal door_changed(degrees: float, latched: bool)

var hinge_side := -1
var swing := -1
var open_deg := 0.0
var self_closing := false
var leaf_collision := true
var width := 0.0
var height := 0.0
var thickness := 0.0
var bottom_gap := -1.0
var knob_position := Vector2.ZERO
var log_name := ""
var leaf: Node3D = null
var opener: Node3D = null
var closed := false
var angle := 0.0


func dress_leaf(node: Node3D) -> void:
	leaf = node


func dress_opener(node: Node3D) -> void:
	opener = node


func get_angle_deg() -> float:
	return angle


func close(_animate: bool = true) -> void:
	closed = true
	angle = 0.0
