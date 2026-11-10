## What TardisTravel needs of RetroXR's SceneManager, and a record of what was asked of it.
extends Node

signal scene_content_ready(scene_id: String)

var current_scene_id := "bedroom"
var changes: Array = []


func change_scene(scene_id: String) -> void:
	changes.append(scene_id)


func default_room() -> String:
	return "arcade"
