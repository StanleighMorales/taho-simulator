extends Node

## Headless tests for how the tools feel.
##
##     godot --headless res://tests/feel_tests.tscn
##
## The step tests check the rules and the town tests check the wiring. This one
## checks what the player actually feels: that the ladle is an object with mass
## and not a cursor. Every assertion compares two runs of the same movement, or
## waits for a settled state, rather than pinning a number — so tuning stays
## free to move and the *intent* does not.
##
## Runs as a scene, not with `--script`: the spring integrates in `_process`,
## so it needs real frames. It waits on conditions rather than frame counts,
## because headless runs well above 60fps and the springs are in seconds.

## Frames of travel to compare between two trials. Short, so the tool is still
## visibly behind the hand when the measurement is taken.
const TRIAL_FRAMES := 6
const POLL_LIMIT := 1200

var _failures := 0
var _checks := 0
var _phase := 0
var _wait := 0
var _polled := 0
var _done := false

var _view: Node3D
var _ladle: Node3D

var _left_x := 0.0
var _right_x := 0.0
var _after_one_frame := 0.0
var _residual_dry := 0.0
var _residual_wet := 0.0
var _residual_loaded := 0.0


func _ready() -> void:
	_view = load("res://scenes/serving/serving_view.tscn").instantiate()
	# Asleep, so no step is driving the tools while we measure them.
	_view.standalone = false
	add_child(_view)
	_ladle = _view.get_node("Ladle")

	# Learn where the view actually puts the tool, rather than mirroring its
	# arithmetic here — a tuning change to the reach should not fail a test
	# about weight.
	_park(-1.0)
	_left_x = _x()
	_park(1.0)
	_right_x = _x()


func _process(_delta: float) -> void:
	if _done:
		return
	if _wait > 0:
		_wait -= 1
		return

	match _phase:
		0:
			_section("the ladle is an object, not a cursor")
			_park(-1.0)
			_check("a fresh stroke starts under the hand",
				is_equal_approx(_x(), _left_x), "x=%.3f" % _x())
			_view.set_ladle(true, 1.0, 0.0)
			_wait = 1

		1:
			_after_one_frame = _x()
			_check("it does not teleport to the hand",
				_after_one_frame < _right_x - 0.01,
				"after 1 frame x=%.3f, hand at %.3f" % [_after_one_frame, _right_x])
			_check("but it does set off toward it",
				_after_one_frame > _left_x + 0.001, "x=%.3f" % _after_one_frame)

		2:
			if not _poll("and it gets there", absf(_x() - _right_x) < 0.005,
					"x=%.3f" % _x()):
				return

			_section("material drags on the tool")
			_park(-1.0)
			_view.set_ladle(true, 1.0, 0.0, 0.0)
			_wait = TRIAL_FRAMES

		3:
			_residual_dry = absf(_x() - _right_x)
			_park(-1.0)
			_view.set_ladle(true, 1.0, 0.0, 1.0)
			_wait = TRIAL_FRAMES

		4:
			_residual_wet = absf(_x() - _right_x)
			_check("cutting through tofu lags more than moving through air",
				_residual_wet > _residual_dry,
				"wet=%.4f dry=%.4f" % [_residual_wet, _residual_dry])
			_check("working the tool starts filling it", _view._ladle_load > 0.0,
				"load=%.3f" % _view._ladle_load)

			_section("a full scoop is heavier than an empty one")
			# Sit still and keep working, to fill the scoop up properly.
			_park(-1.0)
			_view.set_ladle(true, -1.0, 0.0, 1.0)

		5:
			if not _poll("working it long enough fills the scoop",
					_view._ladle_load > 0.99, "load=%.3f" % _view._ladle_load):
				return
			# `_park` resets position and momentum but keeps what is in the
			# scoop, which is the one variable under test here.
			_park(-1.0)
			_view.set_ladle(true, 1.0, 0.0, 0.0)
			_wait = TRIAL_FRAMES

		6:
			_residual_loaded = absf(_x() - _right_x)
			_check("carrying a scoop lags more than carrying nothing",
				_residual_loaded > _residual_dry,
				"loaded=%.4f empty=%.4f" % [_residual_loaded, _residual_dry])
			_check("the load survives the lift out of the bucket",
				_view._ladle_load > 0.9, "load=%.3f" % _view._ladle_load)

			_section("it leans into the turn")
			_check("a tool moving right leans its leading edge up",
				_ladle.rotation_degrees.z > 0.5,
				"tilt=%.2f deg" % _ladle.rotation_degrees.z)

		7:
			if not _poll("and it comes back level once it stops",
					absf(_ladle.rotation_degrees.z) < 0.5,
					"tilt=%.2f deg" % _ladle.rotation_degrees.z):
				return

			_section("tipping it out empties it")
			_view.skim_splash()

		8:
			if not _poll("the scoop is light again after it is tipped out",
					_view._ladle_load < 0.01, "load=%.3f" % _view._ladle_load):
				return

			_section("putting it down")
			_view.set_ladle(false, 0.0, 0.0)
			_check("the tool is out of sight when no step is holding it",
				_ladle.visible == false)
			_report()
			return

	_phase += 1


# --- plumbing --------------------------------------------------------------

## Drop the ladle at `u` with no momentum, so every trial starts the same way.
## Deliberately does not touch what is in the scoop.
func _park(u: float) -> void:
	_view.set_ladle(false, 0.0, 0.0)
	_view.set_ladle(true, u, 0.0)


func _x() -> float:
	return _ladle.position.x


## Stay in this phase until `ok`. Returns true when the check has been recorded
## and the phase may move on — including when it gave up, so a wrong assertion
## fails the run instead of hanging it.
func _poll(label: String, ok: bool, detail := "") -> bool:
	if ok:
		_polled = 0
		_check(label, true, detail)
		return true
	_polled += 1
	if _polled > POLL_LIMIT:
		_polled = 0
		_check(label, false, "never settled — " + detail)
		return true
	return false


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
