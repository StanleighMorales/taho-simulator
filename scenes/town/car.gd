class_name Car
extends Node3D

## A car driving round one loop of road, in its lane, for good.
##
## It keeps its distance from the car in front and gives way at junctions. It
## does not give way to people: walk out in front of one and it runs you over.
##
## Nothing here is physics. The car is moved along its path by hand, and the
## only collision it has is a box that notices Lolo Ben inside it.

## 30 km/h, about what a barangay street allows, and nearly twice Lolo Ben's
## walk, so crossing has to be timed.
const TOP_SPEED := 8.0
const ACCEL := 4.0
const BRAKE := 16.0
## Another car this far in front, and within this much of the line it is
## driving on, and this one waits for it.
const GAP := 9.0
const LANE_HALF := 1.8
## Waiting longer than this, it goes anyway. Four cars giving way to each
## other at a crossroads can wait in a circle for ever; impatience breaks it.
const PATIENCE := 2.5
## Any slower and walking into it is not being hit by it.
const HARM_SPEED := 2.0
## The kit's trucks are toy-sized. This makes one a little over 4 m long.
const SCALE := 1.5
## How far before a corner the turn starts.
const TURN := 4.0

var speed := 0.0

var _path := PackedVector3Array()
var _ends := PackedFloat32Array()
var _s := 0.0
var _waited := 0.0
var _wheels: Array[Node] = []
var _bumper: Area3D


## `corners` is the loop in its lane, one point per corner; `start` is how far
## round it to begin, 0..1.
func setup(model: PackedScene, corners: PackedVector3Array, start: float) -> void:
	add_to_group("cars")

	var body: Node3D = model.instantiate()
	body.scale = Vector3.ONE * SCALE
	add_child(body)
	_wheels = body.find_children("wheel*", "", true, false)
	# Only the body throws a shadow. The wheels and the underside are under it.
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		if mesh.name != "body":
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_bumper = Area3D.new()
	_bumper.collision_layer = 0
	_bumper.collision_mask = 2  # the player's layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.4, 2.9) * SCALE
	shape.shape = box
	shape.position = Vector3(0.0, 0.7, 0.1) * SCALE
	_bumper.add_child(shape)
	add_child(_bumper)

	_path = _round(corners)
	var total := 0.0
	for i in _path.size():
		total += _path[i].distance_to(_path[(i + 1) % _path.size()])
		_ends.append(total)
	_s = start * total
	speed = TOP_SPEED
	_move(0.0, 1.0)


func _physics_process(delta: float) -> void:
	var blocked := _blocked()
	_waited = _waited + delta if blocked else 0.0
	if blocked and _waited < PATIENCE:
		speed = move_toward(speed, 0.0, BRAKE * delta)
	else:
		speed = move_toward(speed, TOP_SPEED, ACCEL * delta)

	_move(speed * delta, minf(1.0, delta * 8.0))
	for wheel in _wheels:
		wheel.rotation.x += speed * delta / (0.3 * SCALE)

	if speed > HARM_SPEED:
		for body in _bumper.get_overlapping_bodies():
			if body.has_method("hit_by_car"):
				body.hit_by_car(global_transform.basis.z * speed)


## Along the path by `distance`, turning towards the way it now goes by
## `weight` (1 to face it outright). The kit's cars face +Z.
func _move(distance: float, weight: float) -> void:
	_s = fposmod(_s + distance, _ends[-1])
	var i := _ends.bsearch(_s, false)
	var from := _ends[i - 1] if i > 0 else 0.0
	var a := _path[i]
	var b := _path[(i + 1) % _path.size()]
	position = a.lerp(b, (_s - from) / maxf(_ends[i] - from, 0.001))
	rotation.y = lerp_angle(rotation.y, atan2(b.x - a.x, b.z - a.z), weight)


func _blocked() -> bool:
	for other in get_tree().get_nodes_in_group("cars"):
		if other == self or not _sees(other):
			continue
		# Two cars that each see the other in front would both wait. One of
		# them, it does not matter which, goes first.
		if other._sees(self) and get_instance_id() > other.get_instance_id():
			continue
		return true
	return false


func _sees(other: Node3D) -> bool:
	var rel := other.global_position - global_position
	var ahead := global_transform.basis.z
	var along := rel.dot(ahead)
	return along > 0.0 and along < GAP and absf(rel.dot(ahead.cross(Vector3.UP))) < LANE_HALF


## The loop with its corners rounded off, so a car turns instead of pivoting.
static func _round(corners: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in corners.size():
		var at := corners[i]
		var enter := at + (corners[i - 1] - at).normalized() * TURN
		var leave := at + (corners[(i + 1) % corners.size()] - at).normalized() * TURN
		for k in 5:
			var t := k / 4.0
			out.append(enter.lerp(at, t).lerp(at.lerp(leave, t), t))
	return out
