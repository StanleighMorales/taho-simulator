extends CharacterBody3D

## Lolo Ben, roaming.
##
## Two ways to walk, because the game has to work on a phone as well as a
## laptop (section 1 of the plan): WASD / arrows, and tap-the-ground to walk
## there. A drag orbits the camera, a tap walks — separated by a small pixel
## threshold, so neither gesture steals the other.
##
## `V` (or the HUD button) swaps the follow camera for Lolo Ben's own eyes.
## Everything else stays the same: drag to look, keys walk where you face.
##
## The physics is a capsule against walls, nothing more. No ragdoll, no
## slopes worth the name.

signal interact_pressed()
## A car hit him. He lies where he fell until `revive`.
signal died()

const SPEED := 4.4
const ACCEL := 14.0
const FRICTION := 18.0
const GRAVITY := 22.0

## A drag longer than this is a camera look, not a tap on the ground.
const TAP_SLOP := 14.0

const CAM_DISTANCE := 6.4
const CAM_FOCUS := 1.35
const PITCH_MIN := -46.0
const PITCH_MAX := -6.0

## First person: eyes just under the hat brim, and more room to look up and
## down than the orbit has.
const EYE_HEIGHT := 1.5
const FP_PITCH_MIN := -70.0
const FP_PITCH_MAX := 60.0

## True while the serving view has the screen; the player stands still and
## ignores input without having to be removed from the tree.
var frozen := false:
	set(value):
		frozen = value
		if value:
			velocity = Vector3.ZERO
			_walk_target = Vector3.INF

var _yaw := 8.0
var _pitch := -22.0
var _walk_target := Vector3.INF
var _drag_from := Vector2.ZERO
var _dragging := false
var _drag_moved := 0.0
var _bob := 0.0
var _distance := CAM_DISTANCE
var first_person := false
var dead := false

@onready var _camera: Camera3D = $Camera3D
@onready var _rig: Node3D = $Rig


func _ready() -> void:
	_build_body()
	# The camera is driven by hand rather than parented or hung off a
	# SpringArm3D. Both of those encode a direction convention it is easy to
	# get backwards, and this project has already paid for one of those.
	_camera.top_level = true
	_place_camera(1.0)


func camera() -> Camera3D:
	return _camera


## Swap between the follow camera and his own eyes. The heading carries over;
## the tilt starts fresh, because a good orbit angle stares at the pavement
## from his eyes. His body stays for its shadow, but out of the way of them.
func toggle_view() -> void:
	first_person = not first_person
	_pitch = -6.0 if first_person else -22.0
	for mesh in _rig.get_children():
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
			if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Knocked down by a car going `push` (its velocity). A frozen player is
## serving or already down, and a car cannot hit him twice.
func hit_by_car(push: Vector3) -> void:
	if frozen:
		return
	dead = true
	frozen = true
	var fall := create_tween().set_parallel()
	fall.tween_property(self, "global_position", global_position + push.normalized() * 2.0, 0.3)
	fall.tween_property(_rig, "rotation_degrees:x", 85.0, 0.3)
	died.emit()


func revive(at: Vector3) -> void:
	_rig.rotation_degrees.x = 0.0
	global_position = at
	dead = false
	frozen = false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var wish := _wish_direction()
	if wish != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, wish.x * SPEED, ACCEL * delta)
		velocity.z = move_toward(velocity.z, wish.z * SPEED, ACCEL * delta)
		# Face where we are going, never instantly.
		var target := atan2(-wish.x, -wish.z)
		_rig.rotation.y = lerp_angle(_rig.rotation.y, target, minf(1.0, delta * 9.0))
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)

	move_and_slide()

	# A walk-to order is done when we arrive, and abandoned if a wall stops
	# us short — otherwise the player would press into a building forever.
	if _walk_target != Vector3.INF:
		var flat := Vector2(global_position.x - _walk_target.x, global_position.z - _walk_target.z)
		if flat.length() < 0.6 or (wish != Vector3.ZERO and velocity.length() < 0.4):
			_walk_target = Vector3.INF

	_animate(delta)


func _wish_direction() -> Vector3:
	if frozen:
		return Vector3.ZERO

	var keys := Input.get_vector("walk_left", "walk_right", "walk_forward", "walk_back")
	if keys.length_squared() > 0.01:
		_walk_target = Vector3.INF  # taking the keys overrides a tap
		var basis_yaw := Basis(Vector3.UP, deg_to_rad(_yaw))
		var dir := basis_yaw * Vector3(keys.x, 0.0, keys.y)
		return dir.normalized()

	if _walk_target != Vector3.INF:
		var to := _walk_target - global_position
		to.y = 0.0
		if to.length() > 0.4:
			return to.normalized()

	return Vector3.ZERO


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return

	if event.is_action_pressed("interact"):
		interact_pressed.emit()
		return

	if event.is_action_pressed("toggle_view"):
		toggle_view()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_moved = 0.0
			_drag_from = event.position
		elif _dragging:
			_dragging = false
			if _drag_moved <= TAP_SLOP:
				_tap_ground(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_drag_moved += event.relative.length()
		if _drag_moved > TAP_SLOP:
			_yaw -= event.relative.x * 0.25
			var lo := FP_PITCH_MIN if first_person else PITCH_MIN
			var hi := FP_PITCH_MAX if first_person else PITCH_MAX
			_pitch = clampf(_pitch - event.relative.y * 0.15, lo, hi)
	elif event is InputEventMouseButton and event.pressed:
		var zoom := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = -0.6
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = 0.6
		if zoom != 0.0:
			_distance = clampf(_distance + zoom, 3.4, 10.0)


## Walk to wherever on the ground the pointer landed. Only the world layer is
## queried, so clicking a customer walks up to them rather than through them.
func _tap_ground(screen_pos: Vector2) -> void:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_walk_target = hit["position"]


func _process(delta: float) -> void:
	_place_camera(minf(1.0, delta * 12.0))


## Orbit the player at `_yaw` / `_pitch`, pulling in if a building is in the
## way so the view never ends up inside a wall. In first person the same angles
## aim his eyes instead, so switching keeps the way you were facing.
func _place_camera(weight: float) -> void:
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch)
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))

	if first_person:
		# The rig's walk bob is his head bob too, and when he falls the eyes
		# go down with him.
		var eye := global_position + Vector3(0.0,
			maxf(EYE_HEIGHT * cos(_rig.rotation.x), 0.3) + _rig.position.y, 0.0)
		_camera.global_position = eye
		_camera.look_at(eye - dir, Vector3.UP)
		return

	var focus := global_position + Vector3(0.0, CAM_FOCUS, 0.0)

	var distance := _distance
	var query := PhysicsRayQueryParameters3D.create(focus, focus + dir * (_distance + 0.4))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		distance = maxf(2.4, focus.distance_to(hit["position"]) - 0.4)

	var want := focus + dir * distance
	_camera.global_position = _camera.global_position.lerp(want, weight)
	_camera.look_at(focus, Vector3.UP)


# --- the silhouette --------------------------------------------------------

## Lolo Ben has to read by shape alone: bent back, wide hat, two buckets on a
## yoke pole (section 2 of the plan). Placeholder boxes, right silhouette.
func _build_body() -> void:
	var skin := Color(0.72, 0.56, 0.42)
	var shirt := Color(0.86, 0.84, 0.76)
	var pants := Color(0.34, 0.36, 0.42)

	_box(_rig, Vector3(0, 0.42, 0), Vector3(0.44, 0.84, 0.3), pants)
	# Leaning torso. The bend is the whole character.
	var torso := _box(_rig, Vector3(0, 1.1, -0.08), Vector3(0.52, 0.62, 0.34), shirt)
	torso.rotation_degrees.x = -14.0
	_box(_rig, Vector3(0, 1.48, -0.12), Vector3(0.24, 0.24, 0.24), skin)
	# The hat: wide, flat, unmistakable from behind.
	_box(_rig, Vector3(0, 1.62, -0.12), Vector3(0.74, 0.06, 0.74), Color(0.82, 0.72, 0.46))
	_box(_rig, Vector3(0, 1.69, -0.12), Vector3(0.3, 0.12, 0.3), Color(0.78, 0.68, 0.42))

	# Yoke pole across the shoulders, a bucket hanging at each end.
	var pole := _box(_rig, Vector3(0, 1.36, -0.04), Vector3(2.5, 0.07, 0.07),
		Color(0.52, 0.38, 0.24))
	pole.rotation_degrees.z = 2.0
	for side in [-1.0, 1.0]:
		var bucket := CylinderMesh.new()
		bucket.top_radius = 0.26
		bucket.bottom_radius = 0.22
		bucket.height = 0.5
		var mi := MeshInstance3D.new()
		mi.name = "Bucket%d" % int(side)
		mi.mesh = bucket
		mi.position = Vector3(side * 1.05, 0.92, -0.04)
		mi.material_override = _flat(Color(0.76, 0.78, 0.80))
		_rig.add_child(mi)
		_box(_rig, Vector3(side * 1.05, 1.18, -0.04), Vector3(0.5, 0.03, 0.5),
			Color(0.84, 0.86, 0.88))


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = _flat(color)
	parent.add_child(mi)
	return mi


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


## A walk cycle without an animation: the whole rig sways, and the buckets
## swing against it. Enough to make walking feel like effort.
func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_bob += delta * (4.0 + speed * 2.4)
	var amount := clampf(speed / SPEED, 0.0, 1.0)
	_rig.position.y = sin(_bob * 2.0) * 0.035 * amount
	_rig.rotation_degrees.z = sin(_bob) * 2.6 * amount
