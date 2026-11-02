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

## The tofu block: inner radius of the bucket, and how tall a full one stands
## above the bucket floor.
##
## A full bucket is nearly full to the rim — a vendor skims the surface just
## under the lid, not twenty centimetres down a well. It also has to be: the
## camera cannot see much below the rim, so a block sitting low in the bucket
## is a surface the player never sees, which would waste the whole of this.
const TOFU_RADIUS := 0.246
const TOFU_DEPTH := 0.38

## The bucket tapers towards its base, so the block has to follow it at every
## height — not just lean in at the bottom. Sized for the widest point and
## left straight, the block pokes out through the wall as a white band, and
## it does so worst when the level is low and the bucket is narrowest.
const BUCKET_INNER_BASE := 0.216
const BUCKET_FLARE := 0.08

## Height the dipper is held at while it works between the small bucket and
## the cup. Clear of the cup rim, so the tool reads as held above the cup
## rather than sunk into it.
const DIPPER_Y := 0.52


## One tool in the hand.
##
## Owns the gap between the pointer and the thing: lag, lean and load. The
## pointer sets a target and the tool chases it, and that gap is the entire
## point — a tool that arrives exactly where the pointer is, exactly when the
## pointer gets there, is a cursor, and there is nothing to feel.
##
## There are two tools on the table and they are meant to feel different: a
## wide scoop heavy with tofu is not a thin dipper holding a spoonful of
## syrup. So the behaviour lives here once and the numbers live per instance.
class ToolBody:
	extends RefCounted

	## Seconds to settle while moving through air.
	var smooth := 0.055
	## Added on top while cutting through material.
	var drag := 0.10
	## Added on top at a full load.
	var load_drag := 0.07
	## How fast working the tool fills it.
	var fill_rate := 1.6
	## Degrees of lean per unit of sideways speed, and the cap.
	var lean_rate := 7.0
	var lean_max := 24.0
	var lean_smooth := 0.08

	var node: Node3D
	var active := false
	## 0..1 of a full tool. A loaded tool is slower to turn and slower to stop.
	var carried := 0.0
	## How much material it is working through right now, as the step sees it.
	var bite := 0.0
	var dumping := false

	var _target := Vector3.ZERO
	var _vel := Vector3.ZERO
	var _lean := 0.0
	var _lean_vel := 0.0

	func _init(for_node: Node3D) -> void:
		node = for_node

	## Point the tool at a local position. `hardness` is how much material it
	## is cutting through, 0..1.
	func aim(at: Vector3, hardness: float) -> void:
		bite = clampf(hardness, 0.0, 1.0)
		_target = at
		if active:
			return
		# The first frame of a stroke starts under the hand, not wherever the
		# last stroke happened to end.
		active = true
		node.visible = true
		node.position = at
		_vel = Vector3.ZERO
		_lean = 0.0
		_lean_vel = 0.0

	func put_down() -> void:
		active = false
		bite = 0.0
		node.visible = false

	## Tipped out, so it is light again.
	func empty() -> void:
		dumping = true

	## `submerged` is the view's business — only it knows where the liquid is.
	func update(delta: float, submerged: bool) -> void:
		if not active:
			carried = move_toward(carried, 0.0, delta * 4.0)
			return

		var resistance := maxf(bite, 1.0 if submerged else 0.0)
		var settle := smooth + resistance * drag + carried * load_drag
		var sprung := _damp(node.position, _target, _vel, settle, delta)
		node.position = sprung[0]
		_vel = sprung[1]

		if resistance > 0.0:
			dumping = false
			carried = minf(1.0, carried + delta * fill_rate * resistance)
		elif dumping:
			carried = move_toward(carried, 0.0, delta * 4.0)

		# Leading edge up, so the tool planes through the material rather than
		# ploughing into it.
		var want := clampf(_vel.x * lean_rate, -lean_max, lean_max)
		want *= 1.0 + resistance * 0.5 + carried * 0.4
		var tilt := _damp(Vector3(_lean, 0, 0), Vector3(want, 0, 0),
			Vector3(_lean_vel, 0, 0), lean_smooth, delta)
		_lean = tilt[0].x
		_lean_vel = tilt[1].x
		node.rotation_degrees.z = _lean

	## Critically damped spring, returning [position, velocity]. The closed
	## form rather than a naive spring, because this has to stay stable on a
	## browser frame that occasionally takes 40ms.
	static func _damp(current: Vector3, target: Vector3, vel: Vector3,
			smooth_time: float, delta: float) -> Array:
		var omega := 2.0 / maxf(smooth_time, 0.0001)
		var x := omega * delta
		var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var change := current - target
		var temp := (vel + change * omega) * delta
		return [target + (change + temp) * decay, (vel - temp * omega) * decay]

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

## The wide flat scoop for the tofu, and the thin small-bowled dipper for the
## sago and the arnibal. Two tools is what a vendor actually carries, and it
## is also why reaching for the right one reads as work.
var _scoop: ToolBody
var _dipper: ToolBody

## The tofu, as a surface material is taken off, rather than a cylinder that
## gets shorter. The mesh is rebuilt from it at most once a frame.
var _tofu := TofuSurface.new()
var _tofu_dirty := true

var _tofu_fill := 0.0
var _contents_mat: ShaderMaterial
var _cup_rest := Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D
@onready var _bucket: Node3D = $Bucket
@onready var _water: MeshInstance3D = $Bucket/Water
@onready var _tofu_node: MeshInstance3D = $Bucket/Tofu
@onready var _cup: Node3D = $Cup
@onready var _contents: MeshInstance3D = $Cup/Contents
@onready var _sago: MultiMeshInstance3D = $Cup/Sago
@onready var _ladle: MeshInstance3D = $Ladle
@onready var _dipper_node: MeshInstance3D = $Dipper
@onready var _small: Node3D = $SmallBucket
@onready var _small_sago: MeshInstance3D = $SmallBucket/Sago
@onready var _small_arnibal: MeshInstance3D = $SmallBucket/Arnibal
@onready var _lid: Node3D = $Bucket/Lid
@onready var _steam: CPUParticles3D = $Steam
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
	_build_tools()
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

	_update_tools(delta)

	if _tofu_dirty:
		_tofu_dirty = false
		_rebuild_tofu()

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
		LidStep.new(),
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
	_ui_title.text = "%d/%d  %s" % [index + 1, _steps.size(), _active.title]
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
	# The whey lies on top of the tofu, so it rides on the block.
	_water.position.y = TOFU_DEPTH + 0.06 * l
	_water.visible = level > 0.01


## Take a thin layer of tofu off wherever the blade is, and report how much
## actually came up. The cup fills by what the scoop lifted, so working one
## groove stops paying and the bucket has to be worked across.
func carve_tofu(u: float, effort: float) -> float:
	var taken := _tofu.carve(u, effort)
	if taken > 0.0:
		_tofu_dirty = true
	return taken


## Digging below the water in step 1 takes a bite out of the tofu, and the
## dent is still there when it is time to shave it.
func gouge_tofu(u: float, depth: float) -> void:
	_tofu.gouge(u, depth)
	_tofu_dirty = true


func tofu_remaining() -> float:
	return _tofu.remaining()


## Rebuild the block from the profile: a ribbon across the top at the sampled
## heights, with a skirt down each side so it reads as a solid block rather
## than a sheet of paper. Small enough to regenerate outright — about fifty
## vertices — so there is no need to be clever about updating it in place.
func _rebuild_tofu() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()

	var n := TofuSurface.SAMPLES
	var xs := PackedFloat32Array()
	var halfs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	xs.resize(n)
	halfs.resize(n)
	ys.resize(n)
	for i in n:
		var t := float(i) / float(n - 1)
		xs[i] = lerpf(-TOFU_RADIUS, TOFU_RADIUS, t)
		# The bucket is round, so each slice is only as wide as the circle is
		# at that x. Without this the block is a box in a cylinder.
		halfs[i] = sqrt(maxf(0.0, TOFU_RADIUS * TOFU_RADIUS - xs[i] * xs[i]))
		ys[i] = TOFU_DEPTH * _tofu.heights[i]

	for i in n - 1:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var w0 := halfs[i]
		var w1 := halfs[i + 1]
		var y0 := ys[i]
		var y1 := ys[i + 1]

		# Every vertex is drawn in to whatever the bucket's radius is at its
		# own height, not just leaned in at the base.
		var t0 := _bucket_taper(y0)
		var t1 := _bucket_taper(y1)
		var tb := _bucket_taper(0.0)

		# Top. Wound front-to-back, so the normal comes out pointing up: the
		# other way round it is back-face culled and the bucket looks empty.
		_quad(verts, normals,
			Vector3(x0 * t0, y0, w0 * t0), Vector3(x1 * t1, y1, w1 * t1),
			Vector3(x1 * t1, y1, -w1 * t1), Vector3(x0 * t0, y0, -w0 * t0))

		# Sides, down to the bucket floor.
		_quad(verts, normals,
			Vector3(x0 * tb, 0.0, w0 * tb), Vector3(x1 * tb, 0.0, w1 * tb),
			Vector3(x1 * t1, y1, w1 * t1), Vector3(x0 * t0, y0, w0 * t0))
		_quad(verts, normals,
			Vector3(x0 * t0, y0, -w0 * t0), Vector3(x1 * t1, y1, -w1 * t1),
			Vector3(x1 * tb, 0.0, -w1 * tb), Vector3(x0 * tb, 0.0, -w0 * tb))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_tofu_node.mesh = mesh


## How much to draw the block in at height `y`, so it sits just inside the
## bucket wall. 1.0 at the height a full block stands at.
func _bucket_taper(y: float) -> float:
	return (BUCKET_INNER_BASE + BUCKET_FLARE * y) / TOFU_RADIUS


## Two triangles, with a flat normal each, so the block stays faceted like
## the rest of the art instead of looking smoothly inflated.
func _quad(verts: PackedVector3Array, normals: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(verts, normals, a, b, c)
	_tri(verts, normals, a, c, d)


func _tri(verts: PackedVector3Array, normals: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3) -> void:
	# The normal is the right-hand one for a-b-c, which is the outward
	# direction. Godot wants the *clockwise* winding for a front face though,
	# so the vertices go in reversed. Get this backwards and the block is
	# inside out: you see straight through the top at the inside of the far
	# wall, which is exactly how this was found.
	var normal := (b - a).cross(c - a).normalized()
	verts.append(a)
	verts.append(c)
	verts.append(b)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)


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
## the scoop is held, in the same units, and `bite` is how much material it is
## working through, 0..1.
##
## This sets a target. The tool gets there in `_update_tools`, late.
func set_ladle(active: bool, u: float, depth: float, bite := 0.0) -> void:
	if not active:
		_scoop.put_down()
		return

	# Local space throughout. The view is instanced into the town, so a global
	# y written into a local position puts the scoop somewhere under the map —
	# which is exactly what the old `mouth.y` here did once it was embedded.
	var mouth_y := _bucket.position.y + 0.5
	_scoop.aim(Vector3(
		# Tighter than the bucket radius: the scoop is wide, so the full reach
		# would hang it most of the way off the rim.
		_bucket.position.x + clampf(u, -1.1, 1.1) * 0.16,
		mouth_y - clampf(depth, -0.4, 1.3) * 0.34,
		_bucket.position.z), bite)


## The dipper works between the small bucket and the cup, so it is aimed in
## screen space — which is what the steps already have — rather than in units
## relative to one container.
func set_dipper(active: bool, screen_pos: Vector2, bite := 0.0) -> void:
	if not active:
		_dipper.put_down()
		return
	var at := _plane_point(screen_pos, DIPPER_Y)
	if at == Vector3.INF:
		return
	# Keep it over the table, so a stray drag cannot fling it into the sky.
	_dipper.aim(Vector3(clampf(at.x, -1.2, 1.2), DIPPER_Y, clampf(at.z, -0.6, 0.6)),
		bite)


## Pick the dipper up and hold it over its own bucket, before the first
## gesture of a step that uses it.
func rest_dipper() -> void:
	_dipper.aim(Vector3(_small.position.x, DIPPER_Y, _small.position.z), 0.0)


func _update_tools(delta: float) -> void:
	_scoop.update(delta, _water.visible and _ladle.global_position.y < _water_surface_y())
	_dipper.update(delta, false)
	# The syrup falls from wherever the dipper is, not from a fixed spout.
	if _dipper.active:
		_stream.position.x = _dipper_node.position.x
		_stream.position.z = _dipper_node.position.z


## Top of the water in world space. The mesh is a 0.12-high cylinder scaled by
## the level, so half of that rides above its own origin.
func _water_surface_y() -> float:
	return _water.global_position.y + _water.scale.y * 0.06


## Where a screen ray lands on a horizontal plane at local height `y`, in
## local space — which is what node positions want. Returns Vector3.INF when
## the ray never gets there.
func _plane_point(screen_pos: Vector2, y: float) -> Vector3:
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector3.INF
	var t := (global_position.y + y - from.y) / dir.y
	if t <= 0.0:
		return Vector3.INF
	return to_local(from + dir * t)


## How far the lid is swung back, 0 shut to 1 wide open.
##
## It folds right back to lie behind the bucket. Stopping it anywhere near
## upright leaves a 27cm disc facing the camera, square across the thing the
## player is supposed to be looking into.
func set_lid(open: float) -> void:
	_lid.rotation_degrees.x = -165.0 * clampf(open, 0.0, 1.0)


## The moment the bucket is opened: warm taho, so it steams.
##
## A steady wisp rather than a burst that settles. `amount_ratio` is a GPU
## particles property, and changing `amount` on CPU particles restarts the
## system, which pops — so the burst can wait for a second emitter.
func lid_opened() -> void:
	_steam.restart()
	_steam.emitting = true


func skim_splash() -> void:
	_pulse = 0.7
	# Lifted clear and tipped out: the scoop is light again.
	_scoop.empty()


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


## How many separate layers of tofu are stacked in the cup. Taho goes in as
## thin sheets, and the stack is the most recognisable image of the stuff —
## the shader bands the contents so it is visible through the cup wall.
func set_cup_sheets(count: int) -> void:
	_contents_mat.set_shader_parameter("sheets", float(count))


func cup_screen_position() -> Vector2:
	return _camera.unproject_position(_cup.global_position + Vector3(0, 0.2, 0))


func customer_screen_position() -> Vector2:
	return _camera.unproject_position(_customer.global_position + Vector3(0, 0.7, 0))


func drag_cup_to(screen_pos: Vector2) -> void:
	# The plane the cup slides on, so dragging tracks the pointer.
	var hit := _plane_point(screen_pos, TABLE_Y + 0.15)
	if hit == Vector3.INF:
		return
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
	# `material_override`, not a surface override: the block's mesh is
	# regenerated as it is carved, and swapping a mesh clears the per-surface
	# overrides with it.
	var tofu_mat := StandardMaterial3D.new()
	tofu_mat.albedo_color = Color(0.96, 0.95, 0.91)
	tofu_mat.roughness = 0.65
	$Bucket/Tofu.material_override = tofu_mat
	$Bucket/Tofu.position = Vector3.ZERO
	# The bucket has no lid now, so its far inner wall must not be culled.
	var body_mat: StandardMaterial3D = $Bucket/Body.get_surface_override_material(0)
	body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_set_material($Customer/Body, Color(0.35, 0.45, 0.62), 0.8)

	# The second bucket: sago and arnibal in their own compartments, and the
	# cash box, which is where a vendor actually keeps it.
	_set_material($SmallBucket/Body, Color(0.72, 0.74, 0.77), 0.45)
	var small_mat: StandardMaterial3D = $SmallBucket/Body.get_surface_override_material(0)
	small_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_set_material($SmallBucket/Divider, Color(0.62, 0.64, 0.66), 0.5)
	_set_material($SmallBucket/Sago, Color(0.24, 0.16, 0.11), 0.4)
	_set_material($SmallBucket/Arnibal, Color(0.33, 0.16, 0.05), 0.2)
	_set_material($SmallBucket/CashBox, Color(0.30, 0.24, 0.18), 0.75)
	_set_material($Bucket/Lid/Plate, Color(0.78, 0.80, 0.83), 0.4)

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


## Both tools, and the steam.
##
## Each gets a handle, and the handle is the point: a bare disc barely shows
## which way it is leaning, so all the weight in `ToolBody` would be
## invisible. A handle turns a few degrees of tilt into a shape the eye reads
## at once.
func _build_tools() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.80, 0.82, 0.85)
	metal.metallic = 0.4
	metal.roughness = 0.35

	_ladle.set_surface_override_material(0, metal)
	_handle(_ladle, Vector3(0.0, 0.055, 0.21), Vector3(0.022, 0.022, 0.36), -17.0)
	_scoop = ToolBody.new(_ladle)

	# The dipper is thin, small-bowled and barely weighs anything even full.
	# It should feel quick in the hand next to the scoop — that difference is
	# the reason for carrying two tools rather than one.
	_dipper_node.set_surface_override_material(0, metal)
	_handle(_dipper_node, Vector3(0.0, 0.075, 0.19), Vector3(0.016, 0.016, 0.34), -26.0)
	_dipper = ToolBody.new(_dipper_node)
	_dipper.smooth = 0.035
	_dipper.drag = 0.05
	_dipper.load_drag = 0.02
	_dipper.fill_rate = 3.0
	_dipper.lean_rate = 5.0
	_dipper.lean_max = 16.0

	_scoop.put_down()
	_dipper.put_down()
	_build_steam()


func _handle(tool_node: MeshInstance3D, at: Vector3, size: Vector3, pitch: float) -> void:
	var shaft := BoxMesh.new()
	shaft.size = size
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	handle.mesh = shaft
	handle.position = at
	handle.rotation_degrees = Vector3(pitch, 0.0, 0.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.34, 0.26, 0.19)
	wood.roughness = 0.8
	handle.material_override = wood
	tool_node.add_child(handle)


## Taho is served warm, and steam off the open bucket is most of what warm
## means to a player. CPU particles rather than GPU: they are the ones that
## are certain to work in the Compatibility renderer on the web.
func _build_steam() -> void:
	# A little sphere rather than a billboarded flat card. Billboarding and
	# particles need the BILLBOARD_PARTICLES path and its anim frames to
	# behave, and at twelve particles a six-segment sphere costs nothing and
	# looks the same from every angle.
	var puff := SphereMesh.new()
	puff.radius = 0.035
	puff.height = 0.07
	puff.radial_segments = 6
	puff.rings = 3

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	puff.material = mat

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.22, Color(1, 1, 1, 0.17))

	_steam.mesh = puff
	_steam.amount = 12
	_steam.lifetime = 2.0
	_steam.direction = Vector3(0, 1, 0)
	_steam.spread = 22.0
	_steam.initial_velocity_min = 0.2
	_steam.initial_velocity_max = 0.42
	_steam.gravity = Vector3(0, 0.14, 0)
	_steam.scale_amount_min = 0.35
	_steam.scale_amount_max = 0.9
	_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_steam.emission_sphere_radius = 0.14
	_steam.color_ramp = ramp
	# Back to front, or a dozen overlapping alpha quads stack into a solid
	# white ball instead of a wisp.
	_steam.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_steam.emitting = false


## The small bucket shows what is actually left of the day's sago and
## arnibal, so a heavy hand on this customer is visible to the next one.
func _refresh_small_bucket() -> void:
	_set_compartment(_small_sago, float(GameState.sago) / float(GameState.LOAD_SIZE))
	_set_compartment(_small_arnibal, float(GameState.arnibal) / float(GameState.LOAD_SIZE))


func _set_compartment(node: MeshInstance3D, level: float) -> void:
	var l := clampf(level, 0.06, 1.0)
	node.scale.y = l
	# The compartment is a 0.26-high cylinder sitting on the bucket floor, so
	# it has to drop as it shrinks rather than shrinking about its middle.
	node.position.y = 0.13 * l


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
	set_dipper(false, Vector2.ZERO)
	_scoop.carried = 0.0
	_scoop.dumping = false
	_dipper.carried = 0.0
	_ladle.rotation_degrees.z = 0.0
	_dipper_node.rotation_degrees.z = 0.0
	set_lid(0.0)
	_steam.emitting = false
	_refresh_small_bucket()
	# The block starts each order where the day left it. On cup eleven of
	# twelve there is visibly a scraping left in the bottom, which is the
	# whole argument for walking home before you have to.
	_tofu.set_level(float(GameState.tofu) / float(GameState.LOAD_SIZE))
	_tofu_dirty = true
	set_cup_sheets(0)
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
