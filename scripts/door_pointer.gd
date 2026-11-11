## DoorPointer -- what the laser (and the desktop reticle) can press where a door is, for the doors that are not a RetroXR VRDoor.
##
## A StaticBody3D on the pointable layer (21), because a headset's laser RayCast cannot see an Area3D (the VRButton over the door is
## one: in a headset only a fingertip with the trigger worked). It answers `pointer_event` like every pointable:
##   * the pointer's own press (the laser's trigger, a desktop click) emits `pressed`;
##   * and the A / X button (`ax_button`) of the controller whose laser is on it does too, on the press, once.
## Neither is the grip: the grab keeps taking things. A hand that is HOLDING something does not press (the screwdriver aimed at the TARDIS
## to send it away uses that very trigger and A).
extends StaticBody3D

signal pressed

const POINTABLE_LAYER := 1 << 20
const A_ON := 0.6
const A_OFF := 0.4

## Test seams: what A reads (a pointer node -> 0..1) and whether that pointer's hand holds something (a pointer node -> bool).
var read_a := Callable()
var hand_busy := Callable()

var _hovered: Dictionary = {}
var _a_down := false


func _init() -> void:
	collision_layer = POINTABLE_LAYER
	collision_mask = 0


func _ready() -> void:
	set_process(false)


func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_hovered[event.pointer] = true
			set_process(true)
		XRToolsPointerEvent.Type.EXITED:
			_hovered.erase(event.pointer)
			if _hovered.is_empty():
				_a_down = false
				set_process(false)
		XRToolsPointerEvent.Type.PRESSED:
			if not _busy(event.pointer):
				pressed.emit()


func _process(_delta: float) -> void:
	var value := 0.0
	for pointer: Variant in _hovered:
		if not is_instance_valid(pointer) or _busy(pointer as Node3D):
			continue
		value = maxf(value, _a_of(pointer as Node3D))
	if not _a_down and value > A_ON:
		_a_down = true
		pressed.emit()
	elif _a_down and value < A_OFF:
		_a_down = false


func _a_of(pointer: Node3D) -> float:
	if read_a.is_valid():
		return float(read_a.call(pointer))
	var ctrl := _controller_of(pointer)
	return ctrl.get_float("ax_button") if ctrl != null else 0.0


func _busy(pointer: Node3D) -> bool:
	if hand_busy.is_valid():
		return bool(hand_busy.call(pointer))
	var ctrl := _controller_of(pointer)
	if ctrl == null:
		return false
	for pick in ctrl.find_children("*", "XRToolsFunctionPickup", true, false):
		if is_instance_valid(pick.get("picked_up_object")):
			return true
	return false


## The controller a pointer (a function on it) belongs to.
static func _controller_of(pointer: Node) -> XRController3D:
	var n := pointer
	while n != null:
		if n is XRController3D:
			return n as XRController3D
		n = n.get_parent()
	return null


## A box of this size at `at` (a Transform3D in the parent's frame) for the pointer to hit.
static func make(size: Vector3, at: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_script(load("res://mods/xenu.tardis/scripts/door_pointer.gd"))
	body.name = "DoorPointer"
	body.transform = at
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	return body
