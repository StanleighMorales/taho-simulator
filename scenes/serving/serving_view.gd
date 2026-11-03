extends Node3D

## M2 — the serving minigame.
##
## Picks the cup, opens the lid, then hands the pointer to `FreeServe`, which
## lets the player work the buckets in any order until the cup is handed over.
## Owns every visual the steps ask for. Steps hold no node
## references themselves, so they stay testable and the scene wiring lives
## in exactly one place.
##
## It all happens on the pavement. Lolo Ben squats between his two buckets —
## tofu on the left, sago and arnibal on the right — with the cups in a row in
## front of him. Every trip a tool makes is the same gesture: press to load,
## drag to carry, release to tip. Where you let go is where the stuff goes,
## which is what makes the tools things rather than cursors.
##
## All input is pointer-based (press / drag / release). Godot synthesises
## mouse events from touch, so this plays the same on a phone.
##
## Runs two ways. On its own it loops customers forever, which is how it was
## built and tested. Embedded in the town it sleeps until `begin_order()`,
## then reports the sale with `order_finished` and goes back to sleep — the
## scene is never unloaded, exactly as section 7 of the plan asks.

signal order_finished(pay: int, tofu_used: float, sago_used: float, arnibal_used: float)

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

## Radius of the water mesh, so the puddle can be fitted to the wall.
const WATER_RADIUS := 0.242

## Height the dipper is held at while it works between the syrup bucket and
## the cup. Clear of the cup rim, so the tool reads as held above the cup
## rather than sunk into it.
const DIPPER_Y := 0.52

## Height the scoop is carried at once it is out of the bucket: clear of both
## bucket rims and the cup.
const CARRY_Y := 0.62

## Height of a full sago or arnibal compartment in the syrup bucket.
const COMPARTMENT_H := 0.36

## How one bucket radius of `u` and of depth maps onto the scoop in metres.
const LADLE_REACH := 0.16
const LADLE_DEPTH := 0.34

## Where the camera moves to for each part of the work, from where it starts.
## Never far: the cup has to stay in frame from all of them, because that is
## where everything gets carried to.
##
## The serve itself leans in over the buckets: forward more than down, so the
## bucket mouths sit low enough to clear the hint and gauge, there is still
## street on the left to throw water on, and the customer's hand is on screen.
const FOCUS_SHIFT := {
	"cups": Vector3(0.22, -0.06, -0.08),
	"tofu": Vector3(-0.26, -0.14, -0.2),
	"syrup": Vector3(0.26, -0.14, -0.2),
	"work": Vector3(-0.1, -0.2, -0.55),
}

## The bucket you are not working at drops back this far into the shade.
const DIM := 0.45
const GLOW_COLOR := Color(1.0, 0.82, 0.38)

## Cup sizes by price, as a share of a P20 cup. Taho is sold by what it costs.
const CUP_CAPACITY := {10: 0.6, 20: 1.0, 50: 1.8}

## What the street orders. Twenty is the usual cup.
const ORDERS := [10, 10, 20, 20, 20, 50]

## Linear size of a P20 cup against the cup mesh. The others scale by the cube
## root of their capacity, so a cup that holds three times as much looks it.
const CUP_SCALE := 0.88

## The row of empty cups on the pavement, front right, out of the way of the
## work between the buckets and clear of the street on the left, where the
## water gets thrown.
const STACK_Z := 0.38
const STACK_X := {10: 0.24, 20: 0.47, 50: 0.72}

const WATER_COLOR := Color(0.62, 0.76, 0.84, 0.85)
const TOFU_COLOR := Color(0.96, 0.95, 0.91)
const SAGO_COLOR := Color(0.24, 0.16, 0.11)
const ARNIBAL_COLOR := Color(0.40, 0.20, 0.06)


## One tool in the hand.
##
## Owns the gap between the pointer and the thing: lag, lean and load. The
## pointer sets a target and the tool chases it, and that gap is the entire
## point — a tool that arrives exactly where the pointer is, exactly when the
## pointer gets there, is a cursor, and there is nothing to feel.
##
## There are two tools and they are meant to feel different: a wide scoop
## heavy with tofu is not a thin dipper holding a spoonful of syrup. So the
## behaviour lives here once and the numbers live per instance.
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
	## Degrees it turns over to empty, and how long out and back takes.
	var tip_angle := 110.0
	var tip_time := 0.42
	## Fastest it can be pushed through material, in metres a second. A hand
	## can move as fast as it likes and the tool cannot, and the gap between
	## them is the resistance.
	var cut_speed := 0.5
	## How far a full load hangs below where the hand holds it.
	var sag := 0.03

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
	var _tip_t := -1.0

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
		_tip_t = -1.0
		node.visible = false

	## Turn it over where it is, then set it down. The contents leave on the
	## way over, so a tipped tool is light again.
	func tip_out() -> void:
		dumping = true
		bite = 0.0
		_tip_t = 0.0

	## `submerged` is the view's business — only it knows where the liquid is.
	func update(delta: float, submerged: bool) -> void:
		if not active:
			carried = move_toward(carried, 0.0, delta * 4.0)
			return

		# Water holds it back, but less than tofu does.
		var resistance := maxf(bite, 0.6 if submerged else 0.0)
		var settle := smooth + resistance * drag + carried * load_drag
		var aimed := _target - Vector3(0.0, carried * sag, 0.0)
		var sprung := _damp(node.position, aimed, _vel, settle, delta)
		var moved: Vector3 = sprung[0] - node.position
		_vel = sprung[1]
		# In material it has a top speed, however fast the hand goes.
		if resistance > 0.0:
			var limit := lerpf(4.0, cut_speed, resistance) * delta
			if moved.length() > limit:
				moved = moved.normalized() * limit
				_vel = moved / maxf(delta, 0.0001)
		node.position += moved

		if resistance > 0.0:
			dumping = false
			carried = minf(1.0, carried + delta * fill_rate * resistance)
		elif dumping:
			carried = move_toward(carried, 0.0, delta * 4.0)

		# Leading edge up, so the tool planes through the material rather than
		# ploughing into it.
		var want := clampf(_vel.x * lean_rate, -lean_max, lean_max)
		want *= 1.0 + resistance * 1.2 + carried * 0.5
		var tilt := _damp(Vector3(_lean, 0, 0), Vector3(want, 0, 0),
			Vector3(_lean_vel, 0, 0), lean_smooth, delta)
		_lean = tilt[0].x
		_lean_vel = tilt[1].x

		var tip := 0.0
		if _tip_t >= 0.0:
			_tip_t += delta
			var k := minf(_tip_t / tip_time, 1.0)
			tip = tip_angle * sin(k * PI)
			if k >= 1.0:
				put_down()
				return
		node.rotation_degrees.z = _lean + tip

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

## The cup's jelly wobble: how hard it was hit, and how long ago.
var _pulse := 0.0
var _wobble_t := 0.0
var _losing_tofu := false

## The wide flat scoop for the tofu, and the thin small-bowled dipper for the
## sago and the arnibal. Two tools is what a vendor actually carries, and it
## is also why reaching for the right one reads as work.
var _scoop: ToolBody
var _dipper: ToolBody

## What each tool is holding, so the right thing lands where it is tipped.
var _ladle_kind := ""
var _dipper_kind := ""
var _ladle_fill: MeshInstance3D
var _dipper_fill: MeshInstance3D
## Whether the scoop was under the water, and down on the tofu, last frame.
var _scoop_wet := false
var _scoop_on_tofu := false
var _drip: CPUParticles3D

## The tofu, as a surface material is taken off, rather than a cylinder that
## gets shorter. The mesh is rebuilt from it at most once a frame.
var _tofu := TofuSurface.new()
var _tofu_dirty := true
## How much of the bucket there was when the order began, so the order can
## report what it actually took — on the street as well as in the cup.
var _tofu_start := 1.0

## The level shown in the cup chases the level the steps set, so a sheet
## settles in rather than appearing. Held back while the sheet is falling.
var _tofu_fill := 0.0
var _tofu_fill_target := 0.0
var _tofu_fill_hold := 0.0
var _contents_mat: ShaderMaterial
var _cup_rest := Vector3.ZERO

var _wanted := 20
var _price := 20
var _capacity := 1.0
var _cup_scale := CUP_SCALE
## Price -> the short stack of empty cups standing on the pavement.
var _stack := {}
var _bubble_t := 0.0
## What the pointer is over, so the thing you would pick up glows before you
## pick it up.
var _hover := ""

var _camera_home := Vector3.ZERO
var _focus := "-"
## The glowing rim on whatever is being worked at, and how dimmed each bucket
## is, 0..1, with the materials and colours that dimming darkens.
var _rings := {}
var _glow_mat: StandardMaterial3D
var _glow_t := 0.0
var _dim := {"tofu": 0.0, "syrup": 0.0}
var _dim_parts := {"tofu": [], "syrup": []}
var _last_buzz := 0

var _shell_mat: StandardMaterial3D
var _sheet_mat: StandardMaterial3D
var _drop_mesh: SphereMesh

@onready var _camera: Camera3D = $Camera3D
@onready var _bucket: Node3D = $Bucket
@onready var _water: MeshInstance3D = $Bucket/Water
@onready var _tofu_node: MeshInstance3D = $Bucket/Tofu
@onready var _cup: Node3D = $Cup
@onready var _contents: MeshInstance3D = $Cup/Contents
@onready var _sago: MultiMeshInstance3D = $Cup/Sago
@onready var _ladle: MeshInstance3D = $Ladle
@onready var _dipper_node: MeshInstance3D = $Dipper
@onready var _syrup: Node3D = $SyrupBucket
@onready var _syrup_sago: MeshInstance3D = $SyrupBucket/Sago
@onready var _syrup_arnibal: MeshInstance3D = $SyrupBucket/Arnibal
@onready var _lid: Node3D = $Bucket/Lid
@onready var _steam: CPUParticles3D = $Steam
@onready var _stream: MeshInstance3D = $PourStream
@onready var _customer: Node3D = $Customer
## What the customer is saying. On the HUD, because from down here by the
## buckets the customer is a pair of legs and a hand.
@onready var _bubble: Label = $UI/Order

@onready var _ui: CanvasLayer = $UI
@onready var _ui_money: Label = $UI/Money
@onready var _ui_hint: Label = $UI/Hint
@onready var _gauge_bg: ColorRect = $UI/GaugeBg
@onready var _gauge_fill: ColorRect = $UI/GaugeBg/GaugeFill
@onready var _gauge_target: ColorRect = $UI/GaugeBg/GaugeTarget
@onready var _gauge_name: Label = $UI/GaugeBg/GaugeName
@onready var _card: PanelContainer = $UI/Card
@onready var _card_grade: Label = $UI/Card/Box/Grade
@onready var _card_reaction: Label = $UI/Card/Box/Reaction
@onready var _card_pay: Label = $UI/Card/Box/Pay
@onready var _card_again: Label = $UI/Card/Box/Again


func _ready() -> void:
	_cup_rest = _cup.position
	_camera_home = _camera.position
	_build_materials()
	_build_sago()
	_build_tools()
	_build_cup_stack()
	_build_focus()
	if standalone:
		_card_again.text = "tap for the next customer"
		begin_order()
	else:
		_card_again.text = "tap to pick the buckets back up"
		end_order()


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 2.2)
		_wobble_t += delta
		# Squashes down and out, rebounds, settles: a jelly wobble, because
		# that is what a cup of soft tofu does when something lands in it.
		var w := _pulse * cos(_wobble_t * 24.0)
		_cup.scale = _cup_scale * Vector3(1.0 + w * 0.07, 1.0 - w * 0.09, 1.0 + w * 0.07)

	if _tofu_fill_hold > 0.0:
		_tofu_fill_hold -= delta
	elif not is_equal_approx(_tofu_fill, _tofu_fill_target):
		_tofu_fill = move_toward(_tofu_fill, _tofu_fill_target, delta * 1.6)
		_apply_cup_tofu()

	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.text = _order_line()

	_update_tools(delta)
	_update_focus(delta)

	if _tofu_dirty:
		_tofu_dirty = false
		_rebuild_tofu()

	if _finished or _active == null:
		return

	_active.update(delta)
	_refresh_hud(delta)

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
		_hover = _part(zone_at(event.position))
		if event.pressed:
			_active.pointer_down(event.position)
		else:
			_active.pointer_up(event.position)
	elif event is InputEventMouseMotion:
		_hover = _part(zone_at(event.position))
		_active.pointer_move(event.position, event.relative)


func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	return false


## The bucket a zone belongs to, for the glow.
func _part(zone: String) -> String:
	if zone == "sago" or zone == "arnibal":
		return "syrup"
	return zone if zone != "ground" else ""


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
	order_finished.emit(_last_pay, _tofu_used(), _sago_used(), _arnibal_used())


## What actually left the bucket this order, in P20 cups — including what was
## gouged out while draining and what was tipped on the street. The bucket
## you look into is the bucket you carry.
func _tofu_used() -> float:
	return maxf(0.0, _tofu_start - _tofu.remaining()) * GameState.LOAD_SIZE


## How much of each syrup actually went in, in P20 cups, so the town can take
## it out of the bucket. A heavy hand costs a refill trip sooner.
func _sago_used() -> float:
	for step in _tools():
		if step is SagoStep:
			return maxf(0.0, step.amount) * _capacity
	return 0.0


func _arnibal_used() -> float:
	for step in _tools():
		if step is ArnibalStep:
			return maxf(0.0, step.level + step.overflow) * _capacity
	return 0.0


func _tools() -> Array:
	return _steps.back().tools() if not _steps.is_empty() else []


func _start_customer() -> void:
	_finished = false
	_card.visible = false
	_index = 0
	_losing_tofu = false
	_wanted = ORDERS.pick_random()

	_steps = [CupStep.new(), LidStep.new(), FreeServe.new()]
	for step in _steps:
		step.setup(self)

	_reset_visuals()
	_activate(0)


func _activate(index: int) -> void:
	_index = index
	_active = _steps[index]
	_active.begin()
	_set_focus(_active.focus)
	_refresh_hud()


func _advance() -> void:
	if _index + 1 < _steps.size():
		_activate(_index + 1)
	else:
		_complete_order()


func _complete_order() -> void:
	_finished = true
	_active = null

	# The cup and the lid, then every tool, settled now that the cup is gone.
	var judged: Array = _steps.slice(0, 2) + _steps.back().scored()
	var value := Grading.sarap(judged)
	var pay := Grading.payment(value, _price)
	_last_pay = pay
	# Standalone there is nobody else to bank it. Embedded, the town credits
	# the sale once the player picks the buckets back up.
	if standalone:
		GameState.earn(pay)

	_card_grade.text = Grading.grade_label(value)
	_card_reaction.text = Grading.reaction(value, judged)
	_card_pay.text = "+ P%d" % pay
	if pay > _price:
		_card_pay.text += "   (tip P%d)" % (pay - _price)
	_card.visible = true

	_ui_hint.text = ""
	_gauge_bg.visible = false
	_set_focus("")
	_refresh_money()


# --- the order -------------------------------------------------------------

func wanted_price() -> int:
	return _wanted


## Capacity of the cup being filled, as a share of a P20 cup.
func cup_capacity() -> float:
	return _capacity


## The price of the cup stack under the pointer, or 0.
func cup_at(screen_pos: Vector2) -> int:
	var best := 0
	var best_d := bucket_screen_extent() * 0.6
	for price in _stack:
		var stack: Node3D = _stack[price]
		var d := screen_pos.distance_to(
			_camera.unproject_position(stack.global_position + Vector3(0, 0.15, 0)))
		if d < best_d:
			best_d = d
			best = price
	return best


## Lift the top cup off that stack and set it down between the buckets.
func pick_cup(price: int) -> void:
	_price = price
	_capacity = CUP_CAPACITY[price]
	_cup_scale = CUP_SCALE * pow(_capacity, 1.0 / 3.0)

	var stack: Node3D = _stack[price]
	stack.get_child(2).visible = false
	_cup.scale = Vector3.ONE * _cup_scale
	_cup.position = stack.position + Vector3(0, 0.06, 0)
	_cup.visible = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_cup, "position", _cup_rest + Vector3(0, 0.12, 0), 0.22)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_cup, "position", _cup_rest, 0.12)
	tween.tween_callback(_land_pulse.bind(0.6))


func wrong_cup(price: int) -> void:
	var stack: Node3D = _stack[price]
	var x: float = STACK_X[price]
	var tween := create_tween()
	for i in 4:
		tween.tween_property(stack, "position:x", x + (0.025 if i % 2 == 0 else -0.025), 0.05)
	tween.tween_property(stack, "position:x", x, 0.05)
	_say("\"Hindi po, P%d!\"" % _wanted)


func _order_line() -> String:
	return "\"P%d po!\"" % _wanted


## The customer says something for a moment, then goes back to the order.
func _say(line: String) -> void:
	_bubble.text = line
	_bubble_t = 1.8


# --- where things are ------------------------------------------------------

## What is under the pointer: "tofu", "sago", "arnibal", "cup", or "ground"
## for anywhere else on the street. Screen space with generous radii, because
## this is about where the hand is, not a hit test.
func zone_at(screen_pos: Vector2) -> String:
	var e := bucket_screen_extent()
	if _cup.visible and screen_pos.distance_to(cup_screen_position()) < e * 0.75:
		return "cup"
	if screen_pos.distance_to(bucket_screen_position()) < e * 1.15:
		return "tofu"
	var syrup := _camera.unproject_position(_syrup.global_position + Vector3(0, 0.44, 0))
	if screen_pos.distance_to(syrup) < e * 1.05:
		return "sago" if screen_pos.x < syrup.x else "arnibal"
	return "ground"


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


func cup_screen_position() -> Vector2:
	return _camera.unproject_position(to_global(_cup_top()))


## Rim of the cup, in local space.
func _cup_top() -> Vector3:
	return _cup.position + Vector3(0, 0.27 * _cup_scale, 0)


func customer_screen_position() -> Vector2:
	# Where their hands are, which is about as high as the camera can see.
	return _camera.unproject_position(_customer.global_position + Vector3(0, 0.45, 0.25))


# --- the tofu bucket -------------------------------------------------------

## The water lies as a thin layer on top of the tofu, so draining it visibly
## uncovers the white tofu underneath.
func set_bucket_water(level: float) -> void:
	var l := maxf(level, 0.001)
	var top := TOFU_DEPTH * _tofu.highest()
	# Shrink the puddle sideways as well as down. Seen from above, a receding
	# edge reads far more clearly than a few millimetres of height, and it
	# uncovers the white tofu around it. Fitted to the wall at whatever height
	# the block stands, so a low block does not show water through the bucket.
	var spread := lerpf(0.3, 1.0, l) * (BUCKET_INNER_BASE + BUCKET_FLARE * top) / WATER_RADIUS
	_water.scale = Vector3(spread, l, spread)
	# The water lies on top of the tofu, so it rides on the block.
	_water.position.y = top + 0.06 * l
	_water.visible = level > 0.01


## Take a thin layer of tofu off wherever the blade is, and report how much
## actually came up. The scoop fills by what it lifted, so working one groove
## stops paying and the bucket has to be worked across.
func carve_tofu(u: float, effort: float, thickness := 1.0) -> float:
	var taken := _tofu.carve(u, effort, thickness)
	if taken > 0.0:
		_tofu_dirty = true
		_buzz(10)
	return taken


## Digging below the water while draining takes a bite out of the tofu, and
## the dent is still there when it is time to shave it.
func gouge_tofu(u: float, depth: float) -> void:
	_tofu.gouge(u, depth)
	_tofu_dirty = true


func tofu_remaining() -> float:
	return _tofu.remaining()


## How deep the top of the tofu, and the top of the water on it, lie below
## the rim, in the units `set_ladle` takes. Where the scoop meets each is what
## draining and shaving are judged on, so it has to be the bucket on screen.
func tofu_surface_depth() -> float:
	return (0.5 - TOFU_DEPTH * _tofu.highest()) / LADLE_DEPTH


func water_surface_depth() -> float:
	if not _water.visible:
		return tofu_surface_depth()
	# The water mesh is 0.12 high and scaled by the level about its middle.
	return (0.5 - (_water.position.y + 0.06 * _water.scale.y)) / LADLE_DEPTH


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


## How far the lid is swung back, 0 shut to 1 wide open.
##
## It swings up on its hinge at the back rim and leans just past upright.
## Folded further it hangs in mid-air behind the bucket, and with the camera
## looking down from above, an upright lid sits behind the bucket on screen
## rather than across the tofu.
func set_lid(open: float) -> void:
	_lid.rotation_degrees.x = -105.0 * clampf(open, 0.0, 1.0)


## The moment the bucket is opened: warm taho, so it steams.
##
## A steady wisp rather than a burst that settles. `amount_ratio` is a GPU
## particles property, and changing `amount` on CPU particles restarts the
## system, which pops — so the burst can wait for a second emitter.
func lid_opened() -> void:
	_steam.restart()
	_steam.emitting = true


# --- the scoop -------------------------------------------------------------

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
		_bucket.position.x + clampf(u, -1.1, 1.1) * LADLE_REACH,
		mouth_y - clampf(depth, -0.4, 1.3) * LADLE_DEPTH,
		_bucket.position.z), bite)


## Where the scoop really is, in the units `set_ladle` aims it with. In tofu
## and water this is behind the hand, and it is what the steps judge.
func ladle_u() -> float:
	return (_ladle.position.x - _bucket.position.x) / LADLE_REACH


func ladle_depth() -> float:
	return (_bucket.position.y + 0.5 - _ladle.position.y) / LADLE_DEPTH


## Out of the bucket and carried over the street, under the hand.
func carry_ladle(screen_pos: Vector2) -> void:
	var at := _plane_point(screen_pos, CARRY_Y)
	if at == Vector3.INF:
		return
	_scoop.aim(Vector3(clampf(at.x, -1.4, 1.4), CARRY_Y, clampf(at.z, -0.6, 0.7)), 0.0)


## What is in the scoop, so a full scoop looks full. `amount` is 0..1.
func ladle_load(kind: String, amount: float) -> void:
	_ladle_kind = kind if amount > 0.01 else ""
	_show_load(_ladle_fill, _ladle_kind, amount)
	_drip.emitting = _ladle_kind == "water"


## Turn the scoop over where it is. `where` is the zone it is over, which is
## where its contents land.
func tip_ladle(where: String) -> void:
	_scoop.tip_out()
	_drip.emitting = false
	_tip(where, _ladle_kind, _ladle, _ladle_fill)
	_ladle_kind = ""


# --- the dipper ------------------------------------------------------------

## The dipper works between the syrup bucket and the cup, so it is aimed in
## screen space — which is what the steps already have — rather than in units
## relative to one container.
func set_dipper(active: bool, screen_pos: Vector2, bite := 0.0) -> void:
	if not active:
		_dipper.put_down()
		return
	var at := _plane_point(screen_pos, DIPPER_Y)
	if at == Vector3.INF:
		return
	# Keep it over the pavement in front of us, so a stray drag cannot fling
	# it into the sky.
	_dipper.aim(Vector3(clampf(at.x, -1.2, 1.2), DIPPER_Y, clampf(at.z, -0.6, 0.9)),
		bite)


## Hold the dipper down in one side of the syrup bucket. It sinks to whatever
## is left on that side, so a nearly empty compartment is a long reach.
func dip_dipper(screen_pos: Vector2) -> void:
	var side := _syrup_sago if zone_at(screen_pos) == "sago" else _syrup_arnibal
	var top := maxf(side.scale.y * COMPARTMENT_H, 0.1) + 0.02
	_dipper.aim(_syrup.position + Vector3(side.position.x, top, side.position.z), 1.0)


func dipper_screen_position() -> Vector2:
	return _camera.unproject_position(_dipper_node.global_position)


## Pick the dipper up and hold it over its own bucket, before the first
## gesture of a step that uses it.
func rest_dipper() -> void:
	_dipper.aim(Vector3(_syrup.position.x, DIPPER_Y, _syrup.position.z), 0.0)


func dipper_load(kind: String, amount: float) -> void:
	_dipper_kind = kind if amount > 0.01 else ""
	_show_load(_dipper_fill, _dipper_kind, amount)


func tip_dipper(where: String) -> void:
	_dipper.tip_out()
	if where == "cup":
		# The syrup runs into the cup from where the dipper was turned over.
		_stream.position.x = _dipper_node.position.x
		_stream.position.z = _dipper_node.position.z
	_tip(where, _dipper_kind, _dipper_node, _dipper_fill)
	_dipper_kind = ""


func _update_tools(delta: float) -> void:
	var wet := _scoop.active and _water.visible and _ladle.global_position.y < _water_surface_y()
	# Breaking the surface, going in or coming out, is the moment the scoop is
	# felt: a splash where it crossed, bigger coming out full, and a buzz.
	if wet != _scoop_wet:
		var at := _ladle.position
		at.y = _water_surface_y() - global_position.y
		_burst(at, WATER_COLOR, 10 if _scoop_wet else 5, 0.35 if _scoop_wet else 0.2)
		_buzz(15)
	# Meeting the tofu under the water is a bump, not just a slowdown, so the
	# hand knows to stop pushing even on a desktop with no buzz.
	var on_tofu := wet and _scoop.bite > 0.5
	if on_tofu and not _scoop_on_tofu:
		_burst(_ladle.position, TOFU_COLOR, 4, 0.15)
		_buzz(30)
	_scoop_wet = wet
	_scoop_on_tofu = on_tofu
	_scoop.update(delta, wet)
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


# --- what lands where ------------------------------------------------------

func _show_load(fill: MeshInstance3D, kind: String, amount: float) -> void:
	fill.visible = kind != ""
	if not fill.visible:
		return
	var a := clampf(amount, 0.0, 1.0)
	var r := lerpf(0.55, 1.0, a)
	fill.scale = Vector3(r, lerpf(0.4, 1.0, a), r)
	(fill.material_override as StandardMaterial3D).albedo_color = _color_of(kind)


## The contents leave a moment into the tip, on the way over, not when the
## pointer comes up.
func _tip(where: String, kind: String, tool_node: Node3D, fill: MeshInstance3D) -> void:
	var tween := create_tween()
	tween.tween_interval(0.14)
	tween.tween_callback(_land.bind(where, kind, tool_node, fill))


func _land(where: String, kind: String, tool_node: Node3D, fill: MeshInstance3D) -> void:
	fill.visible = false
	if kind == "":
		return
	_buzz(25)
	var at := tool_node.position
	match where:
		"cup":
			if kind == "tofu":
				_drop_sheet(at)
			else:
				if kind == "water":
					_say("\"Ay, tubig!\"")
				_burst(_cup_top(), _color_of(kind), 6, 0.45)
				_land_pulse(0.5 if kind == "arnibal" else 0.8)
		"ground":
			var spot := Vector3(at.x, 0.0, at.z)
			_burst(spot + Vector3(0, 0.02, 0), _color_of(kind), 18, 1.0)
			_stain(spot, kind)
		_:
			# Back into a bucket.
			_burst(at - Vector3(0, 0.08, 0), _color_of(kind), 5, 0.4)


## A scoopful slides off as one sheet and settles into the cup. The cup level
## rises when it lands, not before.
func _drop_sheet(from: Vector3) -> void:
	var slab := CylinderMesh.new()
	slab.top_radius = 0.11
	slab.bottom_radius = 0.1
	slab.height = 0.025
	slab.radial_segments = 12
	var sheet := MeshInstance3D.new()
	sheet.mesh = slab
	sheet.material_override = _sheet_mat
	add_child(sheet)
	sheet.position = from

	var tween := create_tween().set_parallel()
	tween.tween_property(sheet, "position", _cup_top(), 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(sheet, "scale", Vector3(0.95, 0.5, 0.95) * _cup_scale, 0.22)
	tween.chain().tween_callback(sheet.queue_free)
	tween.tween_callback(_land_pulse.bind(1.0))


func _land_pulse(strength: float) -> void:
	_pulse = maxf(_pulse, strength)
	_wobble_t = 0.0


## A one-shot spray of droplets. Short-lived, and freed once it has fallen.
func _burst(at: Vector3, color: Color, count: int, power: float) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _drop_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = count
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.7
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 0.5 * power
	p.initial_velocity_max = 1.3 * power
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.color = color
	# Placed before it enters the tree: a CPUParticles3D emits from the moment
	# it is added, and added first it sprays its first burst at the origin.
	p.emitting = false
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## What lands on the street stays there a while: a dark wet patch for water,
## a smear of whatever else. It spreads, then fades on its own.
func _stain(spot: Vector3, kind: String) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.16 if kind == "water" else 0.08
	disc.bottom_radius = disc.top_radius
	disc.height = 0.002
	disc.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if kind == "water":
		mat.albedo_color = Color(0.16, 0.16, 0.18, 0.45)
		mat.roughness = 0.15
	else:
		mat.albedo_color = Color(_color_of(kind), 0.9)
	var patch := MeshInstance3D.new()
	patch.mesh = disc
	patch.material_override = mat
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)
	patch.position = spot + Vector3(0, 0.003, 0)
	patch.scale = Vector3(0.4, 1.0, 0.4)

	var tween := create_tween()
	tween.tween_property(patch, "scale",
		Vector3(randf_range(0.9, 1.25), 1.0, randf_range(0.9, 1.25)), 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 6.0)
	tween.tween_callback(patch.queue_free)


func _color_of(kind: String) -> Color:
	match kind:
		"water":
			return WATER_COLOR
		"sago":
			return SAGO_COLOR
		"arnibal":
			return ARNIBAL_COLOR
	return TOFU_COLOR


# --- the cup ---------------------------------------------------------------

func set_cup_tofu(fill: float) -> void:
	_tofu_fill_target = maxf(fill, 0.02)
	# Held until the sheet has fallen in.
	_tofu_fill_hold = 0.36


func _apply_cup_tofu() -> void:
	var f := _tofu_fill
	# The cup tapers, so narrow the contents as the level drops, otherwise a
	# near-empty cup shows a disc wider than the cup itself.
	var taper := lerpf(0.76, 1.0, f)
	_contents.scale = Vector3(taper, f, taper)
	_contents.position.y = 0.012 + 0.14 * f
	_place_sago()


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
	_land_pulse(1.0)


func set_cup_arnibal(level: float) -> void:
	_contents_mat.set_shader_parameter("arnibal_amount", clampf(level, 0.0, 1.0))


## The syrup falls from the dipper to the rim of the cup, however big the cup.
func pour_stream(intensity: float) -> void:
	var i := clampf(intensity, 0.0, 1.0)
	_stream.visible = i > 0.02
	var top := _cup_top().y
	var span := maxf(DIPPER_Y - top, 0.05)
	_stream.position.y = top + span * 0.5
	var w := maxf(i, 0.3)
	_stream.scale = Vector3(w, span / 0.34, w)


func set_cup_mix(mix: float) -> void:
	_contents_mat.set_shader_parameter("mix_amount", mix)


## How many separate layers of tofu are stacked in the cup. Taho goes in as
## thin sheets, and the stack is the most recognisable image of the stuff —
## the shader bands the contents so it is visible through the cup wall.
func set_cup_sheets(count: int) -> void:
	_contents_mat.set_shader_parameter("sheets", float(count))


func drag_cup_to(screen_pos: Vector2) -> void:
	# The plane the cup slides on, so dragging tracks the pointer.
	var hit := _plane_point(screen_pos, 0.15)
	if hit == Vector3.INF:
		return
	_cup.position = Vector3(hit.x, _cup_rest.y + 0.08, hit.z)


func deliver_cup() -> void:
	var target: Vector3 = _customer.position + Vector3(-0.12, 0.6, 0.3)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_cup, "position", target, 0.35)
	_say("\"Salamat po!\"")


func return_cup() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_cup, "position", _cup_rest, 0.3)


# --- setup -----------------------------------------------------------------

func _build_materials() -> void:
	_set_material($Ground, Color(0.47, 0.46, 0.44), 0.95)
	_set_material($Curb, Color(0.63, 0.62, 0.59), 0.9)
	_set_material($Bucket/Body, Color(0.62, 0.64, 0.67), 0.4)
	# `material_override`, not a surface override: the block's mesh is
	# regenerated as it is carved, and swapping a mesh clears the per-surface
	# overrides with it.
	var tofu_mat := StandardMaterial3D.new()
	tofu_mat.albedo_color = TOFU_COLOR
	tofu_mat.roughness = 0.65
	$Bucket/Tofu.material_override = tofu_mat
	$Bucket/Tofu.position = Vector3.ZERO
	# The bucket is open-topped, so its far inner wall must not be culled.
	var body_mat: StandardMaterial3D = $Bucket/Body.get_surface_override_material(0)
	body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_set_material($Customer/Body, Color(0.35, 0.45, 0.62), 0.8)
	_set_material($Customer/Head, Color(0.76, 0.58, 0.44), 0.8)

	# The second bucket: sago on one side of the divider, arnibal on the other.
	_set_material($SyrupBucket/Body, Color(0.58, 0.60, 0.63), 0.4)
	var syrup_mat: StandardMaterial3D = $SyrupBucket/Body.get_surface_override_material(0)
	syrup_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_set_material($SyrupBucket/Divider, Color(0.62, 0.64, 0.66), 0.5)
	_set_material($SyrupBucket/Sago, SAGO_COLOR, 0.4)
	_set_material($SyrupBucket/Arnibal, ARNIBAL_COLOR, 0.2)
	_set_material($Bucket/Lid/Plate, Color(0.5, 0.52, 0.55), 0.55)

	var water := StandardMaterial3D.new()
	# Clearer than a splash of it, so the scoop the hand is pushing down can
	# be watched going through it.
	water.albedo_color = Color(WATER_COLOR, 0.5)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.15
	_water.set_surface_override_material(0, water)

	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.92, 0.94, 0.97, 0.35)
	shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell.roughness = 0.1
	$Cup/Shell.set_surface_override_material(0, shell)

	# The empty cups are plastic stacked on plastic, so a little more solid
	# than the one with taho showing through it.
	_shell_mat = shell.duplicate()
	_shell_mat.albedo_color = Color(0.94, 0.95, 0.98, 0.6)

	_sheet_mat = StandardMaterial3D.new()
	_sheet_mat.albedo_color = TOFU_COLOR
	_sheet_mat.roughness = 0.6

	_contents_mat = ShaderMaterial.new()
	_contents_mat.shader = load("res://shaders/taho_contents.gdshader")
	_contents_mat.set_shader_parameter("radius", 0.14)
	_contents.set_surface_override_material(0, _contents_mat)

	var syrup := StandardMaterial3D.new()
	syrup.albedo_color = ARNIBAL_COLOR
	syrup.roughness = 0.25
	_stream.set_surface_override_material(0, syrup)
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stream.visible = false

	# One droplet, shared by every splash and drip. Coloured per emitter.
	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = 0.012
	_drop_mesh.height = 0.024
	_drop_mesh.radial_segments = 6
	_drop_mesh.rings = 3
	var drop_mat := StandardMaterial3D.new()
	drop_mat.vertex_color_use_as_albedo = true
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.roughness = 0.2
	_drop_mesh.material = drop_mat


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
	# Heavy enough to drag behind a rushed sweep, light enough that a steady
	# one still carries it wall to wall — and it has to reach the walls, or the
	# flat blade has nothing left to cut in the middle.
	_scoop.drag = 0.12
	_scoop.load_drag = 0.12
	_scoop.cut_speed = 0.6
	# Enough to see the weight, not so much that a full scoop sags through the
	# soft give of the tofu on its own.
	_scoop.sag = 0.012
	# Turned over to the right, towards the cup, which is where it is usually
	# going from the tofu bucket.
	_scoop.tip_angle = -115.0
	_ladle_fill = _make_fill(_ladle, 0.12, 0.018, 0.02)

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
	# And to the left, from the syrup bucket.
	_dipper.tip_angle = 100.0
	_dipper.tip_time = 0.36
	_dipper.cut_speed = 0.8
	_dipper.sag = 0.01
	_dipper_fill = _make_fill(_dipper_node, 0.042, 0.014, 0.022)

	# A scoop of water drips all the way to wherever it is thrown.
	_drip = CPUParticles3D.new()
	_drip.mesh = _drop_mesh
	_drip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drip.amount = 8
	_drip.lifetime = 0.5
	_drip.direction = Vector3(0, -1, 0)
	_drip.spread = 10.0
	_drip.initial_velocity_min = 0.1
	_drip.initial_velocity_max = 0.3
	_drip.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_drip.emission_sphere_radius = 0.1
	_drip.scale_amount_min = 0.4
	_drip.scale_amount_max = 0.7
	_drip.color = WATER_COLOR
	_drip.emitting = false
	_ladle.add_child(_drip)

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


## A disc sitting in the bowl of a tool, showing what it holds.
func _make_fill(tool_node: MeshInstance3D, radius: float, height: float, y: float) -> MeshInstance3D:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius * 0.92
	disc.height = height
	disc.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.3
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	fill.mesh = disc
	fill.material_override = mat
	fill.position.y = y
	fill.visible = false
	tool_node.add_child(fill)
	return fill


## A glowing rim for each place the work happens, and the materials that dim
## when it is the other bucket's turn.
func _build_focus() -> void:
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_color = GLOW_COLOR
	_rings["tofu"] = _ring(_bucket, 0.268, 0.5)
	_rings["syrup"] = _ring(_syrup, 0.248, 0.44)
	_rings["cup"] = _ring(_cup, 0.155, 0.3)

	for path in ["Bucket/Body", "Bucket/Lid/Plate"]:
		_dim_parts["tofu"].append(_dimmable(get_node(path).get_surface_override_material(0)))
	_dim_parts["tofu"].append(_dimmable($Bucket/Tofu.material_override))
	for path in ["SyrupBucket/Body", "SyrupBucket/Divider", "SyrupBucket/Sago", "SyrupBucket/Arnibal"]:
		_dim_parts["syrup"].append(_dimmable(get_node(path).get_surface_override_material(0)))


func _ring(parent: Node3D, radius: float, y: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.011
	torus.outer_radius = radius + 0.011
	torus.rings = 40
	torus.ring_segments = 6
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = _glow_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = y
	ring.visible = false
	parent.add_child(ring)
	return ring


func _dimmable(mat: StandardMaterial3D) -> Array:
	return [mat, mat.albedo_color]


## Glide the camera to the part of the setup this step works at. Only between
## steps, never mid-gesture, so nothing slides out from under the hand.
func _set_focus(where: String) -> void:
	if where == _focus:
		return
	_focus = where
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "position",
		_camera_home + FOCUS_SHIFT.get(where, Vector3.ZERO), 0.6)


func _update_focus(delta: float) -> void:
	_glow_t += delta
	_glow_mat.albedo_color.a = 0.5 + 0.3 * sin(_glow_t * 4.0)

	# The cup lights up as the drop target while something for it is in hand.
	# Not for water: that goes on the street, and a glowing cup would say the
	# opposite.
	var bringing := (_scoop.active and _ladle_kind == "tofu") \
		or (_dipper.active and (_dipper_kind == "sago" or _dipper_kind == "arnibal"))
	# What is in use lights up; with nothing in use, whatever is under the
	# pointer does, so the thing you would pick up shows itself.
	var working: String = _active.working() if _active != null and not _finished else ""
	var lit := working if working != "" else _hover
	if _active is CupStep:
		lit = ""
	_rings["tofu"].visible = lit == "tofu"
	_rings["syrup"].visible = lit == "syrup"
	_rings["cup"].visible = _cup.visible and (lit == "cup" or bringing)

	# The other bucket steps back only while one is actually being worked.
	for side in _dim:
		var want := 1.0 if (working == "tofu" or working == "syrup") and working != side else 0.0
		if is_equal_approx(_dim[side], want):
			continue
		_dim[side] = move_toward(_dim[side], want, delta * 2.5)
		for part in _dim_parts[side]:
			var base: Color = part[1]
			part[0].albedo_color = base.darkened(DIM * _dim[side])


## A short buzz on a phone, so cutting and landing are felt in the hand. Does
## nothing on a desktop. Spaced out, or a sweep is one long drone.
func _buzz(ms: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_buzz < 90:
		return
	_last_buzz = now
	Input.vibrate_handheld(ms)


## Three short stacks of empty cups in a row on the pavement, P10 to P50, each
## with its price in front, so the order is matched by eye.
func _build_cup_stack() -> void:
	var shell_mesh: Mesh = $Cup/Shell.mesh
	for price in STACK_X:
		var s := CUP_SCALE * pow(CUP_CAPACITY[price], 1.0 / 3.0)
		var stack := Node3D.new()
		stack.name = "Cups%d" % price
		stack.position = Vector3(STACK_X[price], 0.0, STACK_Z)
		for i in 3:
			var shell := MeshInstance3D.new()
			shell.mesh = shell_mesh
			shell.material_override = _shell_mat
			# Nested, each sitting a little proud of the one below.
			shell.position = Vector3(0.0, (0.15 + 0.03 * i) * s, 0.0)
			shell.scale = Vector3.ONE * s
			stack.add_child(shell)
		var tag := Label3D.new()
		tag.text = "P%d" % price
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.pixel_size = 0.0022
		tag.font_size = 48
		tag.outline_size = 12
		tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tag.position = Vector3(0.0, 0.03, 0.15 * s + 0.05)
		stack.add_child(tag)
		add_child(stack)
		_stack[price] = stack


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
	_steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


## The syrup bucket shows what is actually left of the day's sago and arnibal,
## so a heavy hand on this customer is visible to the next one.
func _refresh_syrup_bucket() -> void:
	_set_compartment(_syrup_sago, GameState.sago / GameState.LOAD_SIZE)
	_set_compartment(_syrup_arnibal, GameState.arnibal / GameState.LOAD_SIZE)


func _set_compartment(node: MeshInstance3D, level: float) -> void:
	var l := clampf(level, 0.06, 1.0)
	node.scale.y = l
	# The compartment is a cylinder standing on the bucket floor, so it has to
	# drop as it shrinks rather than shrinking about its middle.
	node.position.y = COMPARTMENT_H * 0.5 * l


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
	# The block starts each order where the day left it. On cup eleven of
	# twelve there is visibly a scraping left in the bottom, which is the
	# whole argument for walking home before you have to. Set before the
	# water, which rides on it.
	_tofu.set_level(GameState.tofu / GameState.LOAD_SIZE)
	_tofu_start = _tofu.remaining()
	_tofu_dirty = true
	set_bucket_water(1.0)

	_price = _wanted
	_capacity = CUP_CAPACITY[_wanted]
	_cup_scale = CUP_SCALE * pow(_capacity, 1.0 / 3.0)
	_cup.visible = false
	_cup.position = _cup_rest
	_cup.scale = Vector3.ONE * _cup_scale
	_pulse = 0.0
	_tofu_fill = 0.02
	_tofu_fill_target = 0.02
	_tofu_fill_hold = 0.0
	_apply_cup_tofu()
	set_cup_sago(0.0)
	set_cup_arnibal(0.0)
	set_cup_mix(0.0)
	set_cup_sheets(0)
	pour_stream(0.0)

	for price in _stack:
		var stack: Node3D = _stack[price]
		stack.position.x = STACK_X[price]
		stack.get_child(2).visible = true

	set_ladle(false, 0.0, 0.0)
	set_dipper(false, Vector2.ZERO)
	ladle_load("", 0.0)
	dipper_load("", 0.0)
	_scoop.carried = 0.0
	_scoop.dumping = false
	_dipper.carried = 0.0
	_ladle.rotation_degrees.z = 0.0
	_dipper_node.rotation_degrees.z = 0.0
	set_lid(0.0)
	_steam.emitting = false
	_refresh_syrup_bucket()

	_bubble.text = _order_line()
	_bubble_t = 0.0
	_hover = ""
	_refresh_money()


# --- hud -------------------------------------------------------------------

## One reactive line and one gauge for whatever is in hand. The cup, the
## buckets and the customer carry the rest.
func _refresh_hud(_delta := 0.0) -> void:
	if _active == null:
		return
	_ui_hint.text = _active.hint()
	_ui_hint.modulate = Color(1, 0.5, 0.45) if _losing_tofu else Color(1, 1, 1)

	var value := _active.gauge()
	_gauge_bg.visible = value >= 0.0
	if value < 0.0:
		return
	var width := _gauge_bg.size.x
	_gauge_fill.size = Vector2(clampf(value, 0.0, 1.0) * width, _gauge_bg.size.y)
	_gauge_name.text = _active.gauge_name()

	var target := _active.gauge_target()
	_gauge_target.visible = target >= 0.0
	if target >= 0.0:
		_gauge_target.position.x = clampf(target, 0.0, 1.0) * width - 2.0


func _refresh_money() -> void:
	_ui_money.text = "P%d    served: %d" % [GameState.money, GameState.served]
