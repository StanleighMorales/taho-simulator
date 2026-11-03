extends Node3D

## The game: roam the town, sell taho, walk home when the buckets run dry.
##
## This node owns the one mode switch in the game. Roaming and serving are two
## cameras over two sets of geometry that both stay loaded — stepping into the
## serving view hides the street and freezes the player, and stepping back out
## undoes exactly that. Nothing is reloaded, which is what section 7 of the
## plan asks for.

const CustomerScene := preload("res://scenes/npc/customer.tscn")

## How many customers are waiting in town at once, and how long before a
## served one is replaced. Low numbers on purpose: walking between them is
## the game, so a crowd would remove the reason the town exists.
const WAITING := 3
const RESPAWN_DELAY := 4.5
## How long Lolo Ben lies in the road after a car hits him, before he is back
## on his doorstep with the walk out to do again.
const DOWN_TIME := 3.0

var _target: Node3D = null
var _serving_now: Node3D = null
var _toast_t := 0.0
var _respawn_t := 0.0
var _relock := false
var _had_mouse := false

@onready var _town: Node3D = $Town
@onready var _player: CharacterBody3D = $Player
@onready var _serving: Node3D = $ServingView
@onready var _customers: Node3D = $Customers

@onready var _hud: CanvasLayer = $HUD
@onready var _money: Label = $HUD/Money
@onready var _supplies: Label = $HUD/Supplies
@onready var _prompt: Label = $HUD/Prompt
@onready var _compass: Label = $HUD/Compass
@onready var _toast: Label = $HUD/Toast
@onready var _controls: Label = $HUD/Controls
@onready var _view: Label = $HUD/ViewHint
@onready var _crosshair: Control = $HUD/Crosshair
@onready var _menu: CanvasLayer = $Menu

var _town_env: WorldEnvironment
var _serve_env: WorldEnvironment
var _town_environment: Environment
var _serve_environment: Environment


func _ready() -> void:
	_player.global_position = _town.player_start + Vector3(0, 0.2, 0)
	_player.interact_pressed.connect(_on_interact)
	_player.died.connect(_on_player_died)
	_serving.order_finished.connect(_on_order_finished)
	_town.get_node("HomeArea").body_entered.connect(_on_home_entered)

	# Only one WorldEnvironment can be in charge at a time, so each mode's
	# environment is parked and handed back rather than left to fight.
	_town_env = _town.get_node("WorldEnvironment")
	_serve_env = _serving.get_node("WorldEnvironment")
	_town_environment = _town_env.environment
	_serve_environment = _serve_env.environment
	_serve_env.environment = null

	_menu.get_node("Center/Panel/Box/Resume").pressed.connect(_resume)
	var exit: Button = _menu.get_node("Center/Panel/Box/Exit")
	exit.pressed.connect(get_tree().quit)
	# A page cannot close its own tab, and a quit there only freezes the canvas.
	exit.visible = not OS.has_feature("web")
	_controls.text = "WASD / arrows or tap the ground to walk   ·   mouse or drag to look   ·   E or tap to serve   ·   V to switch view   ·   Esc for the menu"
	# A browser refuses this until the first click, which then takes it.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for i in WAITING:
		_spawn_customer()
	_refresh_hud()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t = maxf(0.0, _toast_t - delta)
		_toast.modulate.a = minf(1.0, _toast_t * 2.0)
		_toast.visible = _toast_t > 0.0

	if _serving_now != null:
		return

	# Keep the street populated, but only after a gap, so a served customer
	# is not instantly replaced in front of the player.
	if _customers.get_child_count() < WAITING:
		_respawn_t += delta
		if _respawn_t >= RESPAWN_DELAY:
			_respawn_t = 0.0
			_spawn_customer()
	else:
		_respawn_t = 0.0

	# A browser takes the cursor back on Esc itself, and the game may never
	# see the key, so losing the cursor is what opens the menu.
	if _had_mouse and not _player.captured():
		_open_menu()
		return
	_had_mouse = _player.captured()

	_target = _nearest_waiting(3.4)
	_view.text = "[V]  Third person" if _player.first_person else "[V]  First person"
	# A free cursor walks to where it is, not to the middle.
	_crosshair.visible = _player.first_person and _player.captured()
	_refresh_prompt()
	_refresh_compass()


## Tapping the ground near a customer serves them too, so the game is
## playable with nothing but a pointer.
func _unhandled_input(event: InputEvent) -> void:
	# Not mid-serve: a tool held when the game pauses would never hear the
	# pointer let go, and stay stuck to it after Resume.
	if event.is_action_pressed("ui_cancel") and _serving_now == null:
		_open_menu()
		return
	if _serving_now != null or _target == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _player.global_position.distance_to(_target.global_position) < 2.6:
			_on_interact()


# --- the mode switch -------------------------------------------------------

func _on_interact() -> void:
	if _serving_now != null or _player.dead:
		return
	if _target == null:
		return
	if not GameState.can_serve():
		_say("The buckets are empty. Walk home and refill.")
		return
	_begin_serving(_target)


func _begin_serving(customer: Node3D) -> void:
	_serving_now = customer
	_player.frozen = true
	# The minigame is all pointer, so it gets the cursor; the street takes it
	# back after if it had it.
	_relock = _player.captured()
	_had_mouse = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_town.visible = false
	_player.visible = false
	_hud.visible = false
	_town_env.environment = null
	_serve_env.environment = _serve_environment
	_serving.begin_order()


func _on_order_finished(pay: int, tofu_used: float, sago_used: float, arnibal_used: float) -> void:
	GameState.earn(pay)
	GameState.spend_supplies(tofu_used, sago_used, arnibal_used)

	if _serving_now != null and is_instance_valid(_serving_now):
		_serving_now.mark_served()
	_serving_now = null
	_target = null

	_serving.end_order()
	_serve_env.environment = null
	_town_env.environment = _town_environment
	_town.visible = true
	_player.visible = true
	_hud.visible = true
	_player.camera().make_current()
	if _relock:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Deferred: the click that dismissed the grade card is still propagating,
	# and an unfrozen player would read it as "walk over there".
	_player.set_deferred("frozen", false)

	_refresh_hud()
	if not GameState.can_serve():
		_say("That was the last cup. Time to walk home.")


func _on_player_died() -> void:
	_say("Nasagasaan si Lolo Ben! Hit by a car. Back home.")
	await get_tree().create_timer(DOWN_TIME, false).timeout
	_player.revive(_town.player_start + Vector3(0, 0.2, 0))


# --- the menu --------------------------------------------------------------

## Esc stops everything, cars included, and gives the cursor back.
func _open_menu() -> void:
	_had_mouse = false
	_menu.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	_menu.visible = false
	get_tree().paused = false
	if _serving_now == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_home_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if GameState.tofu >= GameState.LOAD_SIZE:
		return
	GameState.refill()
	_refresh_hud()
	_say("Buckets refilled. %d cups." % GameState.LOAD_SIZE)


# --- customers -------------------------------------------------------------

func _spawn_customer() -> void:
	var spots: Array = _town.customer_spots
	if spots.is_empty():
		return

	# Pick a free spot that is not right on top of the player, so nobody
	# materialises in their face.
	var taken: Array[Vector3] = []
	for child in _customers.get_children():
		taken.append(child.global_position)

	var order := range(spots.size())
	order.shuffle()
	for i in order:
		var at: Transform3D = spots[i]
		var clear := true
		for t in taken:
			if t.distance_to(at.origin) < 6.0:
				clear = false
				break
		if not clear or _player.global_position.distance_to(at.origin) < 12.0:
			continue
		var customer := CustomerScene.instantiate()
		_customers.add_child(customer)
		customer.global_transform = at
		return


func _nearest_waiting(within: float) -> Node3D:
	var best: Node3D = null
	var best_d := within
	for child in _customers.get_children():
		if not child.has_method("player_in_range") or not child.player_in_range():
			continue
		var d: float = _player.global_position.distance_to(child.global_position)
		if d < best_d:
			best_d = d
			best = child
	return best


# --- hud -------------------------------------------------------------------

func _refresh_hud() -> void:
	_money.text = "P%d    served: %d" % [GameState.money, GameState.served]
	_supplies.text = GameState.supplies_line()
	_supplies.modulate = Color(1, 0.6, 0.5) if GameState.tofu <= 2 else Color(0.9, 0.92, 0.95)


func _refresh_prompt() -> void:
	if _target == null:
		_prompt.visible = false
		return
	_prompt.visible = true
	if GameState.can_serve():
		_prompt.text = "[E]  Set the buckets down and serve %s" % _target.type_name
		_prompt.modulate = Color(1, 1, 1)
	else:
		_prompt.text = "Buckets empty — walk home to refill"
		_prompt.modulate = Color(1, 0.62, 0.52)


## Which way the nearest customer is, in words. The plan wants a screen-edge
## arrow eventually; this is enough to stop the player wandering a town of
## boxes aimlessly, and it needs no glyph the web build might not ship a font
## for.
##
## The bearing is worked out in camera space, where the signs are not open to
## interpretation: +X is screen-right and -Z is into the screen.
func _refresh_compass() -> void:
	var nearest: Node3D = null
	var best := INF
	for child in _customers.get_children():
		if not (child.has_method("is_waiting") and child.is_waiting()):
			continue
		var d: float = _player.global_position.distance_to(child.global_position)
		if d < best:
			best = d
			nearest = child

	if nearest == null:
		_compass.visible = false
		return

	var local: Vector3 = _player.camera().global_transform.basis.inverse() 		* (nearest.global_position - _player.global_position)
	var bearing := rad_to_deg(atan2(local.x, -local.z))

	var where := "ahead"
	if absf(bearing) > 140.0:
		where = "behind you"
	elif bearing > 25.0:
		where = "to your right"
	elif bearing < -25.0:
		where = "to your left"

	_compass.visible = true
	_compass.text = "%s wants taho — %dm %s" % [nearest.type_name, int(round(best)), where]


func _say(message: String) -> void:
	_toast.text = message
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = 3.2
