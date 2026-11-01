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

const TABLE_Y := 0.05

var _steps: Array = []
var _index := 0
var _active: ServingStep = null
var _finished := false

var _money := 0
var _served := 0

var _pulse := 0.0
var _losing_tofu := false

var _tofu_fill := 0.0
var _contents_mat: ShaderMaterial
var _cup_rest := Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D
@onready var _bucket: Node3D = $Bucket
@onready var _water: MeshInstance3D = $Bucket/Water
@onready var _cup: Node3D = $Cup
@onready var _contents: MeshInstance3D = $Cup/Contents
@onready var _sago: MultiMeshInstance3D = $Cup/Sago
@onready var _stream: MeshInstance3D = $PourStream
@onready var _customer: Node3D = $Customer

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


func _ready() -> void:
	_cup_rest = _cup.position
	_build_materials()
	_build_sago()
	_start_customer()


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 4.0)
		var s := 1.0 + _pulse * 0.06
		_cup.scale = Vector3(s, 1.0 + _pulse * 0.1, s)

	if _finished or _active == null:
		return

	_active.update(delta)
	_refresh_hud()

	if _active.complete:
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		if _is_press(event):
			_start_customer()
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

func _start_customer() -> void:
	_finished = false
	_card.visible = false
	_index = 0
	_losing_tofu = false

	_steps = [
		DrainStep.new(),
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
	_money += pay
	_served += 1

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


func set_bucket_water(level: float) -> void:
	var l := maxf(level, 0.001)
	_water.scale.y = l
	_water.position.y = 0.02 + 0.21 * l
	_water.visible = level > 0.005


func spill(is_losing: bool) -> void:
	_losing_tofu = is_losing


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
	_set_material($Customer/Body, Color(0.35, 0.45, 0.62), 0.8)

	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.85, 0.89, 0.86, 0.55)
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
	_ui_money.text = "P%d    served: %d" % [_money, _served]
