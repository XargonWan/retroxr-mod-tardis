## What PickableHighlight answers to the remote: it only remembers the last thing it was told.
extends Node


func set_remote_target(on: bool) -> void:
	get_parent().outlined = on
