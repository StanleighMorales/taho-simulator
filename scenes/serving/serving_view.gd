extends Node3D

## M2 — the serving minigame.
##
## Runs the six steps in order, forwards pointer gestures to whichever is
## active, and owns every visual the steps ask for. Steps hold no node
## references themselves, so they stay testable and the scene wiring lives
## in exactly one place.
##
## All input is pointer-based (press / drag / release). Godot synthesises
## mouse events from touch, so this plays the same on a phone.
##
## Runs two ways. On its own it loops customers forever, which is how it was
## built and tested. Embedded in the town it sleeps until `begin_order()`,
## then reports the sale with `order_finished` and goes back to sleep — the
## scene is never unloaded, exactly as section 7 of the plan asks.

signal order_finished(pay: int, sago_used: float, arnibal_used: float)

const TABLE_Y := 0.05

## How the tools behave.
##
## The pointer sets a *target*; the tool chases it. The gap between the two is
## the entire point. A tool that arrives exactly where the pointer is, exactly
## when the pointer gets there, is a cursor — there is nothing between the
## hand and the result, so there is nothing to feel. Lag, lean and load are
## what make it read as something you are holding.
const LADLE_SMOOTH := 0.055
const LADLE_DRAG := 0.10
const LADLE_LOAD_DRAG := 0.07
const LADLE_TILT_SMOOTH := 0.08
const LADLE_TILT_MAX := 24.0

## False when the town owns the flow.
@export var standalone := true

var _steps: Array = []
var _index := 0
var _active: ServingStep = null
var _finished := false

## True only while this view has the screen and the pointer.
var _live := false

var _last_pay := 0

var _pulse := 0.0
var _losing_tofu := false

var _ladle_active := false
var _ladle_target := Vector3.ZERO
var _ladle_vel := Vector3.ZERO
var _ladle_tilt := 0.0
var _ladle_tilt_vel := 0.0
## 0..1 of a full scoop. A loaded tool is slower to turn and slower to stop.
var _ladle_load := 0.0
## How much material the tool is cutting through right now, as the step sees
## it. Liquid the view works out for itself; tofu only the step knows about.
var _ladle_bite := 0.0
var _ladle_dumping := false

var _tofu_fill := 0.0
var _contents_mat: ShaderMaterial
var _cup_rest := Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D
@onready var _bucket: Node3D = $Bucket
@onready var _water: MeshInstance3D = $Bucket/Water
@onready var _cup: Node3D = $Cup
@onready var _contents: MeshInstance3D = $Cup/Contents
@onready var _sago: MultiMeshInstance3D = $Cup/Sago
@onready var _ladle: MeshInstance3D = $Ladle
@onready var _stream: MeshInstance3D = $PourStream
@onready var _customer: Node3D = $Customer

@onready var _ui: CanvasLayer = $UI
@onready var _ui_money: Label = $UI/Money
@onready var _ui_title: Label = $UI/Title
@onready var _ui_hint: Label = $UI/Hint
@onready var _gauge_bg: ColorRect = $UI/GaugeBg
@onready var _gauge_fill: ColorRect = $UI/GaugeBg/GaugeFill
@onready var _gauge_target: ColorRect = $UI/GaugeBg/GaugeTarget
@onready var _card: PanelContainer = $UI/Card
@onready var _card_grade: Label = $UI/Card/Box/Grade
@onready var _card_reaction: Label = $UI/Card/Box/Reaction
@onready var _card_pay: Label = $UI/Card/Box/Pay
@onready var _card_again: Label = $UI/Card/Box/Again


func _ready() -> void:
	_cup_rest = _cup.position
	_build_materials()
	_build_sago()
	_build_ladle()
	if standalone:
		_card_again.text = "tap for the next customer"
		begin_order()
	else:
		_card_again.text = "tap to pick the buckets back up"
		end_order()


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 4.0)
		var s := 1.0 + _pulse * 0.06
		_cup.scale = Vector3(s, 1.0 + _pulse * 0.1, s)

	_update_ladle(delta)

	if _finished or _active == null:
		return

	_active.update(delta)
	_refresh_hud()

	if _active.complete:
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if not _live:
		return
	if _finished:
		if _is_press(event):
			if standalone:
				_start_customer()
			else:
				_hand_back()
		return
	if _active == null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_active.pointer_down(event.position)
		else:
			_active.pointer_up(event.position)
	elif event is InputEventMouseMotion:
		_active.pointer_move(event.position, event.relative)


func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	return false


# --- flow ------------------------------------------------------------------

## Take the screen and start an order. The town calls this once the player
## sets the buckets down next to a customer.
func begin_order() -> void:
	visible = true
	_ui.visible = true
	_live = true
	_camera.make_current()
	_start_customer()


## Give the screen back without unloading anything. Safe to call twice: the
## town calls it when it takes the screen back, whether or not the player got
## there by dismissing the grade card.
func end_order() -> void:
	_live = false
	_active = null
	visible = false
	_ui.visible = false


func _hand_back() -> void:
	end_order()
	order_finished.emit(_last_pay, _sago_used(), _arnibal_used())


## How much of a cup's worth of each syrup actually went in, so the town can
## take it out of the buckets. A heavy hand costs a refill trip sooner.
func _sago_used() -> float:
	for step in _steps:
		if step is SagoStep:
			return maxf(0.0, step.amount)
	return 1.0


func _arnibal_used() -> float:
	for step in _steps:
		if step is ArnibalStep:
			return maxf(0.0, step.level + step.overflow)
	return 1.0


func _start_customer() -> void:
	_finished = false
	_card.visible = false
	_index = 0
	_losing_tofu = false

	_steps = [
		SkimStep.new(),
		ShaveStep.new(),
		SagoStep.new(),
		ArnibalStep.new(),
		SwirlStep.new(),
		ServeStep.new(),
	]
	for step in _steps:
		step.setup(self)

	_reset_visuals()
	_activate(0)


func _activate(index: int) -> void:
	_index = index
	_active = _steps[index]
	_active.begin()
	_ui_title.text = "%d/6  %s" % [index + 1, _active.title]
	_refresh_hud()


func _advance() -> void:
	if _index + 1 < _steps.size():
		_activate(_index + 1)
	else:
		_complete_order()


func _complete_order() -> void:
	_finished = true
	_active = null

	var value := Grading.sarap(_steps)
	var pay := Grading.payment(value)
	_last_pay = pay
	# Standalone there is nobody else to bank it. Embedded, the town credits
	# the sale once the player picks the buckets back up.
	if standalone:
		GameState.earn(pay)

	_card_grade.text = Grading.grade_label(value)
	_card_reaction.text = Grading.reaction(value)
	_card_pay.text = "+ P%d" % pay
	_card.visible = true

	_ui_title.text = ""
	_ui_hint.text = ""
	_gauge_bg.visible = false
	_refresh_money()


# --- visuals the steps drive ----------------------------------------------

func set_bucket_tilt(degrees: float) -> void:
	_bucket.rotation_degrees.z = degrees


## The whey lies as a thin layer on top of the tofu, so skimming it visibly
## uncovers the white tofu underneath.
func set_bucket_water(level: float) -> void:
	var l := maxf(level, 0.001)
	# Shrink the puddle sideways as well as down. Seen from above, a receding
	# edge reads far more clearly than a few millimetres of height, and it
	# uncovers the white tofu around it.
	var spread := lerpf(0.3, 1.0, l)
	_water.scale = Vector3(spread, l, spread)
	_water.position.y = 0.32 + 0.06 * l
	_water.visible = level > 0.01


func spill(is_losing: bool) -> void:
	_losing_tofu = is_losing


## Middle of the bucket mouth, in screen pixels.
func bucket_screen_position() -> Vector2:
	return _camera.unproject_position(_bucket_mouth())


## One bucket radius, in screen pixels, so steps can work in bucket-relative
## units and stay independent of resolution.
func bucket_screen_extent() -> float:
	var centre := _camera.unproject_position(_bucket_mouth())
	var edge := _camera.unproject_position(_bucket_mouth() + Vector3(0.26, 0, 0))
	return maxf(absf(edge.x - centre.x), 1.0)


func _bucket_mouth() -> Vector3:
	return _bucket.global_position + Vector3(0, 0.5, 0)


## `u` is sideways position in bucket radii, `depth` is how far below the rim
## the ladle is held, in the same units, and `bite` is how much material the
## tool is working through, 0..1.
##
## This sets a target. The tool gets there in `_update_ladle`, late.
func set_ladle(active: bool, u: float, depth: float, bite := 0.0) -> void:
	_ladle_bite = clampf(bite, 0.0, 1.0)
	if not active:
		_ladle_active = false
		_ladle.visible = false
		return

	# Local space throughout. The view is instanced into the town, so a global
	# y written into a local position puts the ladle somewhere under the map —
	# which is exactly what the old `mouth.y` here did once it was embedded.
	var mouth_y := _bucket.position.y + 0.5
	_ladle_target = Vector3(
		# Tighter than the bucket radius: the scoop is wide now, so the full
		# reach would hang it most of the way off the rim.
		_bucket.position.x + clampf(u, -1.1, 1.1) * 0.16,
		mouth_y - clampf(depth, -0.4, 1.3) * 0.34,
		_bucket.position.z)

	if not _ladle_active:
		# First frame of a stroke starts under the hand, not wherever the last
		# stroke happened to end.
		_ladle_active = true
		_ladle.visible = true
		_ladle.position = _ladle_target
		_ladle_vel = Vector3.ZERO
		_ladle_tilt = 0.0
		_ladle_tilt_vel = 0.0


## The tool chases the hand instead of being the hand: it arrives late, leans
## into the turn, drags when it is in the liquid, and gets heavier as it
## fills, so lifting a full scoop out costs more than dipping an empty one in.
func _update_ladle(delta: float) -> void:
	if not _ladle_active:
		_ladle_load = move_toward(_ladle_load, 0.0, delta * 4.0)
		return

	var submerged: bool = _water.visible and _ladle.global_position.y < _water_surface_y()
	var resistance := maxf(_ladle_bite, 1.0 if submerged else 0.0)

	var smooth := LADLE_SMOOTH + resistance * LADLE_DRAG + _ladle_load * LADLE_LOAD_DRAG
	var sprung := _damp(_ladle.position, _ladle_target, _ladle_vel, smooth, delta)
	_ladle.position = sprung[0]
	_ladle_vel = sprung[1]

	if resistance > 0.0:
		_ladle_dumping = false
		_ladle_load = minf(1.0, _ladle_load + delta * 1.6 * resistance)
	elif _ladle_dumping:
		_ladle_load = move_toward(_ladle_load, 0.0, delta * 4.0)

	# Leading edge up, so the tool planes through the material rather than
	# ploughing into it.
	var lean := clampf(_ladle_vel.x * 7.0, -LADLE_TILT_MAX, LADLE_TILT_MAX)
	lean *= 1.0 + resistance * 0.5 + _ladle_load * 0.4
	var tilt := _damp(Vector3(_ladle_tilt, 0, 0), Vector3(lean, 0, 0),
		Vector3(_ladle_tilt_vel, 0, 0), LADLE_TILT_SMOOTH, delta)
	_ladle_tilt = tilt[0].x
	_ladle_tilt_vel = tilt[1].x
	_ladle.rotation_degrees.z = _ladle_tilt


## Top of the water in world space. The mesh is a 0.12-high cylinder scaled by
## the level, so half of that rides above its own origin.
func _water_surface_y() -> float:
	return _water.global_position.y + _water.scale.y * 0.06


## Critically damped spring, returning [position, velocity]. The closed form
## rather than a naive spring, because this has to stay stable on a browser
## frame that occasionally takes 40ms.
func _damp(current: Vector3, target: Vector3, vel: Vector3, smooth_time: float,
		delta: float) -> Array:
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (vel + change * omega) * delta
	return [target + (change + temp) * decay, (vel - temp * omega) * decay]


func skim_splash() -> void:
	_pulse = 0.7
	# Lifted clear and tipped out: the scoop is light again.
	_ladle_dumping = true


func set_cup_tofu(fill: float) -> void:
	var f := maxf(fill, 0.02)
	_tofu_fill = f
	# The cup tapers, so narrow the contents as the level drops, otherwise a
	# near-empty cup shows a disc wider than the cup itself.
	var taper := lerpf(0.76, 1.0, f)
	_contents.scale = Vector3(taper, f, taper)
	_contents.position.y = 0.012 + 0.14 * f
	_place_sago()


func shave_tick(_fill: float) -> void:
	_pulse = maxf(_pulse, 0.25)


func set_cup_sago(amount: float) -> void:
	var mm := _sago.multimesh
	mm.visible_instance_count = int(round(clampf(amount, 0.0, 1.0) * mm.instance_count))
	_place_sago()


## Sago rides on the tofu surface. That is both how taho is actually served
## and the only way the pearls are visible through the open top of the cup.
func _place_sago() -> void:
	_sago.position.y = 0.016 + 0.28 * _tofu_fill
	var spread := lerpf(0.76, 1.0, _tofu_fill)
	_sago.scale = Vector3(spread, 1.0, spread)


func sago_plop() -> void:
	_pulse = 1.0


func set_cup_arnibal(level: float) -> void:
	_contents_mat.set_shader_parameter("arnibal_amount", clampf(level, 0.0, 1.0))


func pour_stream(intensity: float) -> void:
	var i := clampf(intensity, 0.0, 1.0)
	_stream.visible = i > 0.02
	_stream.scale = Vector3(maxf(i, 0.3), 1.0, maxf(i, 0.3))


func set_cup_mix(mix: float) -> void:
	_contents_mat.set_shader_parameter("mix_amount", mix)


func cup_screen_position() -> Vector2:
	return _camera.unproject_position(_cup.global_position + Vector3(0, 0.2, 0))


func customer_screen_position() -> Vector2:
	return _camera.unproject_position(_customer.global_position + Vector3(0, 0.7, 0))


func drag_cup_to(screen_pos: Vector2) -> void:
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	# Intersect the plane the cup slides on, so dragging tracks the pointer.
	if absf(dir.y) < 0.001:
		return
	var t := (TABLE_Y + 0.15 - from.y) / dir.y
	if t <= 0.0:
		return
	var hit := from + dir * t
	_cup.position = Vector3(hit.x, _cup_rest.y + 0.08, hit.z)


func deliver_cup() -> void:
	var target: Vector3 = _customer.position + Vector3(-0.12, 0.78, 0.22)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_cup, "position", target, 0.35)


func return_cup() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_cup, "position", _cup_rest, 0.3)


# --- setup -----------------------------------------------------------------

func _build_materials() -> void:
	_set_material($Table, Color(0.30, 0.22, 0.17), 0.9)
	_set_material($Bucket/Body, Color(0.76, 0.78, 0.80), 0.45)
	_set_material($Bucket/Tofu, Color(0.96, 0.95, 0.91), 0.65)
	# The bucket has no lid now, so its far inner wall must not be culled.
	var body_mat: StandardMaterial3D = $Bucket/Body.get_surface_override_material(0)
	body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_set_material($Customer/Body, Color(0.35, 0.45, 0.62), 0.8)

	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.56, 0.70, 0.78, 0.85)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.15
	_water.set_surface_override_material(0, water)

	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.92, 0.94, 0.97, 0.35)
	shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell.roughness = 0.1
	$Cup/Shell.set_surface_override_material(0, shell)

	_contents_mat = ShaderMaterial.new()
	_contents_mat.shader = load("res://shaders/taho_contents.gdshader")
	_contents_mat.set_shader_parameter("radius", 0.14)
	_contents.set_surface_override_material(0, _contents_mat)

	var syrup := StandardMaterial3D.new()
	syrup.albedo_color = Color(0.40, 0.20, 0.06)
	syrup.roughness = 0.25
	_stream.set_surface_override_material(0, syrup)
	_stream.visible = false


func _set_material(node: MeshInstance3D, color: Color, roughness: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	node.set_surface_override_material(0, mat)


## The scoop gets a handle, and the handle is the point: a bare disc barely
## shows which way it is leaning, so all the weight in `_update_ladle` would
## be invisible. A handle turns a few degrees of tilt into a shape the eye
## reads immediately.
func _build_ladle() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.80, 0.82, 0.85)
	metal.metallic = 0.4
	metal.roughness = 0.35
	_ladle.set_surface_override_material(0, metal)

	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.022, 0.022, 0.36)

	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	handle.mesh = shaft
	handle.position = Vector3(0.0, 0.055, 0.21)
	handle.rotation_degrees = Vector3(-17.0, 0.0, 0.0)
	handle.material_override = StandardMaterial3D.new()
	handle.material_override.albedo_color = Color(0.34, 0.26, 0.19)
	handle.material_override.roughness = 0.8
	_ladle.add_child(handle)


func _build_sago() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.013
	sphere.height = 0.026
	sphere.radial_segments = 6
	sphere.rings = 3

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.14, 0.09)
	mat.roughness = 0.35
	sphere.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = 54
	mm.visible_instance_count = 0

	# Scatter the pearls in a shallow disc so they read as a settled layer.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	for i in mm.instance_count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.085
		var pos := Vector3(cos(a) * r, rng.randf() * 0.022, sin(a) * r)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))

	_sago.multimesh = mm


func _reset_visuals() -> void:
	set_bucket_tilt(0.0)
	set_bucket_water(1.0)
	set_cup_tofu(0.0)
	set_cup_sago(0.0)
	set_cup_arnibal(0.0)
	set_cup_mix(0.0)
	pour_stream(0.0)
	set_ladle(false, 0.0, 0.0)
	_ladle_load = 0.0
	_ladle_dumping = false
	_ladle.rotation_degrees.z = 0.0
	_cup.position = _cup_rest
	_cup.scale = Vector3.ONE
	_gauge_bg.visible = true
	_refresh_money()


# --- hud -------------------------------------------------------------------

func _refresh_hud() -> void:
	if _active == null:
		return
	_ui_hint.text = _active.hint()
	_ui_hint.modulate = Color(1, 0.5, 0.45) if _losing_tofu else Color(1, 1, 1)

	var value := _active.gauge()
	if value < 0.0:
		_gauge_bg.visible = false
		return

	_gauge_bg.visible = true
	var width := _gauge_bg.size.x
	_gauge_fill.size = Vector2(clampf(value, 0.0, 1.0) * width, _gauge_bg.size.y)

	var target := _active.gauge_target()
	_gauge_target.visible = target >= 0.0
	if target >= 0.0:
		_gauge_target.position.x = clampf(target, 0.0, 1.0) * width - 2.0


func _refresh_money() -> void:
	_ui_money.text = "P%d    served: %d" % [GameState.money, GameState.served]
