## Calling the TARDIS: where it lands, and the sounds of it failing to.
##
## The sonic screwdriver, held for 1.5 s on nothing, summons the TARDIS into the room (once: there is
## one TARDIS in a room). It lands IN FRONT of the player if there is room; if not, in the nearest
## spot there is, but always on the floor of the room and in sight of the player (so never behind a
## wall or outside the map). If there is no room at all the materialisation sound starts, is cut off
## by a burst of distortion, and nothing appears.
##
## Rooms have no navmesh and change as the player moves things, so a spot is judged by asking the
## physics world, as the Synth mod's navigation does: a box the size of the TARDIS must overlap
## nothing, the floor must be under all of it, and the player must be able to see the spot.
##
## `candidates` and `score` are pure; `find_spot` takes the physics space, so the suite can build a
## room and ask.
extends RefCounted

const Assets := preload("res://mods/xenu.tardis/scripts/mod_assets.gd")
const TARDIS_SCENE := "res://mods/xenu.tardis/scenes/tardis.tscn"
const LANDING_SOUND := "res://mods/xenu.tardis/assets/audio/landing.mp3"

## The TARDIS as a box to fit (metres): its base with a hand's breadth to spare, and its height.
const BOX := Vector3(1.14, 2.3, 1.14)
## How far in front of the player it lands when there is room.
const FRONT_DISTANCE := 1.7
## Never closer than this to the player (it would land on them).
const MIN_DISTANCE := 1.0
## The farthest spot looked at, from the player.
const SEARCH_RADIUS := 8.0
const STEP := 0.25
## What a spot is weighed by: how far its distance is from FRONT_DISTANCE, and how far round from
## straight ahead it is (radians). A spot behind the player at arm's length beats one across the room.
const ANGLE_WEIGHT := 0.5
## The box stands this far off the floor in the query, so a floor that is a thick collider does not count.
const LIFT := 0.06
const MAX_TESTS := 700
## What blocks a TARDIS: the room (layer 1) and the things in it (the mask every pickable has).
const BLOCK_MASK := 196613
const WORLD_MASK := 1 << 0
## The floor under a spot may be this far from the player's floor.
const FLOOR_TOLERANCE := 0.12


## Whether a TARDIS is in the room already.
static func present(tree: SceneTree) -> bool:
	return not tree.get_nodes_in_group(&"xenu_tardis").is_empty()


## How good a spot `p` is for a player at `eye` looking along `forward` (both flat, y ignored): lower
## is better. 0 is the very spot in front.
static func score(p: Vector2, eye: Vector2, forward: Vector2) -> float:
	var to := p - eye
	var d := to.length()
	if d < 0.0001:
		return INF
	var angle := acos(clampf(to.dot(forward.normalized()) / d, -1.0, 1.0))
	return absf(d - FRONT_DISTANCE) + ANGLE_WEIGHT * angle


## The spots to try, best first: a grid round the player, not nearer than MIN_DISTANCE nor farther
## than SEARCH_RADIUS. Flat points (x, z).
static func candidates(eye: Vector2, forward: Vector2) -> Array[Vector2]:
	var f := forward.normalized() if forward.length() > 0.0001 else Vector2(0, -1)
	var spots: Array[Vector2] = []
	var n := int(SEARCH_RADIUS / STEP)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var p := eye + Vector2(ix, iz) * STEP
			var d := p.distance_to(eye)
			if d >= MIN_DISTANCE and d <= SEARCH_RADIUS:
				spots.append(p)
	# the exact spot ahead first, however the grid fell
	spots.append(eye + f * FRONT_DISTANCE)
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return score(a, eye, f) < score(b, eye, f))
	return spots


## The pose of the best free spot: {position, yaw} (its front toward the player), or {} when there is
## none. `eye` is the player's head, `floor_y` the floor they stand on.
static func find_spot(space: PhysicsDirectSpaceState3D, eye: Vector3, forward: Vector3, floor_y: float,
		exclude: Array[RID] = []) -> Dictionary:
	var flat_eye := Vector2(eye.x, eye.z)
	var tested := 0
	for p: Vector2 in candidates(flat_eye, Vector2(forward.x, forward.z)):
		tested += 1
		if tested > MAX_TESTS:
			break
		var yaw := atan2(eye.x - p.x, eye.z - p.y)
		if is_free(space, Vector3(p.x, floor_y, p.y), yaw, eye, exclude):
			return {"position": Vector3(p.x, floor_y, p.y), "yaw": yaw}
	return {}


## Whether a TARDIS standing at `pos` (on the floor) turned by `yaw` would overlap nothing, have the
## floor under all of its base, and be seen from `eye`.
static func is_free(space: PhysicsDirectSpaceState3D, pos: Vector3, yaw: float, eye: Vector3,
		exclude: Array[RID] = []) -> bool:
	var basis := Basis(Vector3.UP, yaw)
	var shape := BoxShape3D.new()
	shape.size = Vector3(BOX.x, BOX.y - LIFT, BOX.z)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(basis, pos + Vector3(0, LIFT + shape.size.y / 2.0, 0))
	q.collision_mask = BLOCK_MASK
	q.exclude = exclude
	if not space.intersect_shape(q, 1).is_empty():
		return false
	# the floor under the middle and the four corners: not the edge of the map, not a hole
	for off: Vector3 in [Vector3.ZERO, Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		var at := pos + basis * (off * Vector3(BOX.x, 0, BOX.z) * 0.45)
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.6, 0), at + Vector3(0, -0.6, 0))
		ray.collision_mask = WORLD_MASK
		ray.exclude = exclude
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - pos.y) > FLOOR_TOLERANCE:
			return false
	# seen from the player: not behind a wall, not in the next room
	var see := PhysicsRayQueryParameters3D.create(eye, pos + Vector3(0, 1.0, 0))
	see.collision_mask = WORLD_MASK
	see.exclude = exclude
	return space.intersect_ray(see).is_empty()


## The floor the player stands on: the XR origin's height, else the world's zero (as GroundPlacement).
static func floor_y(cam: Camera3D) -> float:
	var node: Node = cam.get_parent() if cam != null else null
	while node != null:
		if node is XROrigin3D:
			return (node as XROrigin3D).global_position.y
		node = node.get_parent()
	return 0.0


## Call the TARDIS for `caller` (the screwdriver): returns the TARDIS it made, materialising, or null
## when there was no room (the failure sound is played) or one is here already.
static func summon(caller: Node3D) -> Node3D:
	var tree := caller.get_tree()
	if present(tree):
		return null
	var cam := caller.get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else caller.global_position
	var look := -(cam.global_basis.z if cam != null else caller.global_basis.z)
	var flat := Vector3(look.x, 0, look.z)
	if flat.length() < 0.2:  # looking at the floor or the ceiling: ahead is where the hand points
		var hand := -caller.global_basis.z
		flat = Vector3(hand.x, 0, hand.z)
	var floor_height := floor_y(cam) if cam != null else minf(eye.y, caller.global_position.y)
	var exclude: Array[RID] = []
	if caller is CollisionObject3D:
		exclude.append((caller as CollisionObject3D).get_rid())
	var spot := find_spot(caller.get_world_3d().direct_space_state, eye, flat, floor_height, exclude)
	if spot.is_empty():
		fail(caller.get_tree().current_scene, eye)
		return null
	var tardis := (load(TARDIS_SCENE) as PackedScene).instantiate() as Node3D
	caller.get_tree().current_scene.add_child(tardis)
	tardis.global_transform = Transform3D(Basis(Vector3.UP, float(spot["yaw"])), spot["position"] as Vector3)
	tardis.call("materialize")
	return tardis


## How long the landing sound is let run before the fizzle cuts it off.
const FAIL_CUT_SECONDS := 1.5

## No room: the landing sound begins, a fizzle of distortion cuts it off, and the node removes itself.
## Returns the holder (it has the two players: "Landing" and "Fizzle").
static func fail(parent: Node, at: Vector3) -> Node3D:
	push_warning("[xenu.tardis] the TARDIS found no room to land")
	var holder := Node3D.new()
	holder.name = "TardisFailed"
	parent.add_child(holder)
	holder.global_position = at
	var landing := _fail_player("Landing", Assets.mp3(LANDING_SOUND), 0.0)
	holder.add_child(landing)
	var fizzle := _fail_player("Fizzle", distortion(), 4.0)
	holder.add_child(fizzle)
	landing.play()
	holder.get_tree().create_timer(FAIL_CUT_SECONDS).timeout.connect(func() -> void:
		landing.stop()
		fizzle.play())
	fizzle.finished.connect(holder.queue_free)
	return holder


static func _fail_player(player_name: String, stream: AudioStream, gain_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = player_name
	p.stream = stream
	p.unit_size = 6.0
	p.max_distance = 25.0
	p.volume_db = gain_db
	return p


## A fizzle: the materialisation shorting out. Noise broken into stuttering bursts, a harsh buzz that
## falls and a crackle, all dying away; made here, 1.1 s of it.
static func distortion() -> AudioStreamWAV:
	var rate := 22050
	var length := 1.1
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var block := int(rate * 0.008)
	var gate := 1.0
	for i in n:
		if i % block == 0:
			# the stutter: most blocks on, some nearly off, more of them off as it dies
			gate = 1.0 if rng.randf() < lerpf(0.75, 0.3, float(i) / n) else 0.12
		var t := float(i) / rate
		var buzz := signf(sin(TAU * (300.0 - 230.0 * t) * t))
		var crackle := 1.0 if rng.randf() < 0.02 else 0.0
		var hiss := rng.randf_range(-1.0, 1.0)
		var env := exp(-t * 2.4) * (1.0 - t / length)
		var v := clampf((0.55 * hiss + 0.35 * buzz + 0.6 * crackle * hiss) * gate * env * 1.4, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
