extends Node

## Headless tests for the roaming layer.
##
##     godot --headless res://tests/town_tests.tscn
##
## Run as a scene, not with `--script`: a custom main loop does not register
## the autoload names, and both this and the code under test need `GameState`.
##
## The step tests drive the minigame through a stub. This one loads the real
## main scene and walks it: customers appear, standing next to one offers a
## sale, the mode switch hands the screen over and takes it back, the sale is
## banked, supplies come out of the buckets, and the porch refills them.
##
## It runs as a phase machine because Area3D detection needs real frames to
## happen in — there is no way to assert on proximity without letting physics
## tick.

const SETTLE := 12

var _failures := 0
var _checks := 0
var _phase := 0
var _wait := 0
var _done := false

var _main: Node = null
var _player: Node3D = null
var _town: Node3D = null
var _customers: Node = null
var _subject: Node3D = null
var _wait_from := Vector3.ZERO


func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_player = _main.get_node("Player")
	_town = _main.get_node("Town")
	_customers = _main.get_node("Customers")
	# Traffic only runs in its own section. Anywhere else a car passing at
	# the wrong moment would decide the result.
	for car in get_tree().get_nodes_in_group("cars"):
		car.process_mode = Node.PROCESS_MODE_DISABLED


func _process(_delta: float) -> void:
	if _done:
		return
	if _wait > 0:
		_wait -= 1
		return

	match _phase:
		0:
			_section("the town exists")
			_check("ground and buildings were built", _town.get_child_count() > 40,
				"children=%d" % _town.get_child_count())
			_check("there are pavement spots for customers",
				_town.customer_spots.size() >= 6)
			_check("the player starts near home",
				_player.global_position.distance_to(_town.home_position) < 10.0)
			_check("roaming camera is the active one", _player.camera().is_current())

			_section("first person")
			var body: GeometryInstance3D = _player.get_node("Rig").get_child(0)
			_player.toggle_view()
			_player._place_camera(1.0)
			var eye: Vector3 = _player.global_position + Vector3(0, _player.EYE_HEIGHT, 0)
			_check("the camera moves to his eyes",
				_player.camera().global_position.distance_to(eye) < 0.1)
			_check("his body only casts a shadow, so it is not in the way",
				body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
			_player.toggle_view()
			_check("switching back shows him again",
				body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

			_section("the menu")
			_tap_key(KEY_ESCAPE)
			_check("Esc opens the menu and stops the street",
				_main._menu.visible and get_tree().paused)
			_tap_key(KEY_ESCAPE)
			_check("and Esc again carries on", not _main._menu.visible and not get_tree().paused)
			# A paused tree would stop this test too.
			if get_tree().paused:
				_main._resume()
			_wait = SETTLE

		1:
			_section("customers")
			_check("the street is populated", _customers.get_child_count() == 3,
				"count=%d" % _customers.get_child_count())
			_subject = _customers.get_child(0)
			_check("a customer is waiting", _subject.is_waiting())
			_check("nobody is in range yet", _subject.player_in_range() == false)

			# Stand on top of them. Proximity is an Area3D, so this needs
			# frames to register.
			_player.global_position = _subject.global_position + Vector3(1.2, 0.2, 0)
			_wait = SETTLE

		2:
			_check("standing next to a customer is noticed", _subject.player_in_range())

			_section("the mode switch")
			var before: int = GameState.money
			_main._target = _subject
			_main._on_interact()
			_check("the serving view took the screen", _main._serving.visible)
			_check("and the bucket is as full as the load is",
				_main._serving._tofu.remaining() > 0.95,
				"block=%.2f" % _main._serving._tofu.remaining())
			_check("the street is hidden", _town.visible == false)
			_check("the player is frozen", _player.frozen)
			_player.hit_by_car(Vector3(0, 0, 8))
			_check("a car cannot hit him while he is serving", _player.dead == false)
			_check("nothing was paid yet", GameState.money == before)
			_wait = 4

		3:
			# Hand back a finished order the way the view does: a decent cup
			# with a heavy hand on the arnibal.
			var money_before: int = GameState.money
			var tofu_before: float = GameState.tofu
			var arnibal_before: float = GameState.arnibal
			_main._on_order_finished(22, 1.8, 0.6, 1.4)

			_check("the sale was banked", GameState.money == money_before + 22,
				"money=%d" % GameState.money)
			_check("a P50 cup takes a P50 cup's worth of tofu",
				is_equal_approx(GameState.tofu, tofu_before - 1.8), "tofu=%.2f" % GameState.tofu)
			_check("a heavy hand costs more arnibal than a cup",
				is_equal_approx(GameState.arnibal, arnibal_before - 1.4),
				"arnibal=%.2f" % GameState.arnibal)
			_check("the street is back", _town.visible)
			_check("the serving view let go", _main._serving.visible == false)
			_check("the customer stops asking", _subject.is_waiting() == false)
			_wait = SETTLE

		4:
			_check("the player can walk again", _player.frozen == false)
			_check("roaming camera is active again", _player.camera().is_current())

			_section("supplies and the refill trip")

			# The bucket the player looks into has to be the bucket they are
			# carrying, or the block is just decoration.
			GameState.tofu = 6.0
			_main._serving.begin_order()
			_check("a half-used load shows as a half-full bucket",
				absf(_main._serving._tofu.remaining() - 0.5) < 0.05,
				"block=%.2f" % _main._serving._tofu.remaining())
			_main._serving.end_order()
			_player.camera().make_current()

			GameState.tofu = 0.0
			_check("an empty bucket cannot serve", GameState.can_serve() == false)
			_main._target = _customers.get_child(0)
			_main._on_interact()
			_check("serving is refused when empty", _main._serving.visible == false)

			_player.global_position = _town.home_position + Vector3(0, 0.3, 0)
			_wait = SETTLE

		5:
			_check("standing on the porch refills the buckets",
				GameState.tofu == GameState.LOAD_SIZE, "tofu=%.1f" % GameState.tofu)
			_check("sago and arnibal came back too",
				GameState.sago == GameState.LOAD_SIZE
				and GameState.arnibal == GameState.LOAD_SIZE)
			_check("and now a sale is possible again", GameState.can_serve())

			_section("traffic")
			_subject = get_tree().get_nodes_in_group("cars")[0]
			_check("there is traffic", get_tree().get_nodes_in_group("cars").size() >= 6)
			_wait_from = _subject.global_position
			for car in get_tree().get_nodes_in_group("cars"):
				car.process_mode = Node.PROCESS_MODE_INHERIT
			_wait = SETTLE

		6:
			_check("the cars drive", _subject.global_position.distance_to(_wait_from) > 0.5,
				"moved=%.2fm" % _subject.global_position.distance_to(_wait_from))
			# Step out right in front of one.
			_player.global_position = _subject.global_position \
				+ _subject.global_transform.basis.z * 1.5 + Vector3(0, 0.2, 0)
			_wait = SETTLE

		7:
			_check("a car that runs into him knocks him down", _player.dead)
			_check("and he cannot walk while he is down", _player.frozen)
			_check("the street says what happened", _main._toast.visible)
			_player.revive(_town.player_start)
			_check("he gets up again at home",
				not _player.dead and not _player.frozen
				and _player.global_position.distance_to(_town.home_position) < 2.0)
			_report()
			return

	_phase += 1


# --- plumbing --------------------------------------------------------------

## A whole key press, down and up, the way a keyboard sends it.
func _tap_key(key: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = down
		_main.get_viewport().push_input(ev)

func _section(title: String) -> void:
	print(title)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("  ok    %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _report() -> void:
	_done = true
	print("")
	if _failures == 0:
		print("ALL PASS  (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("%d of %d checks FAILED" % [_failures, _checks])
		get_tree().quit(1)
