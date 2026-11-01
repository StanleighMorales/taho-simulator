class_name SwirlStep
extends ServingStep

## Step 5 — swirl the arnibal through the tofu.
##
## The only step where the skill is *stopping*. Under-mixed is streaky,
## over-mixed goes flat muddy brown, and the ideal is a marbled middle.
## Mixing is accumulated angle around the cup, so it rewards real circles.

const IDEAL := 0.66
const BAND := 0.5
const SETTLE_TIME := 0.7

var mix := 0.0

var _angle_ref := 0.0
var _has_ref := false
var _holding := false
var _idle := 0.0


func _init() -> void:
	title = "Swirl it through"


func pointer_down(pos: Vector2) -> void:
	_holding = true
	_angle_ref = _angle_at(pos)
	_has_ref = true


func pointer_up(_pos: Vector2) -> void:
	_holding = false
	_has_ref = false


func pointer_move(pos: Vector2, _rel: Vector2) -> void:
	if not _holding:
		return
	var a := _angle_at(pos)
	if not _has_ref:
		_angle_ref = a
		_has_ref = true
		return
	# Shortest signed delta, so crossing the -PI/PI seam doesn't spike.
	var d := wrapf(a - _angle_ref, -PI, PI)
	_angle_ref = a
	mix += absf(d) / TAU * 0.34
	_idle = 0.0
	_view.set_cup_mix(mix)


func update(delta: float) -> void:
	_idle += delta
	if mix > 0.05 and _idle > SETTLE_TIME:
		_finish(1.0 - absf(mix - IDEAL) / BAND)


func hint() -> String:
	if mix <= 0.05:
		return "Draw circles over the cup."
	if mix > IDEAL + BAND * 0.5:
		return "Careful — it's going muddy."
	return "Stop when the marbling looks right."


func gauge() -> float:
	return minf(mix, 1.2) / 1.2


func gauge_target() -> float:
	return IDEAL / 1.2


func _angle_at(pos: Vector2) -> float:
	var c: Vector2 = _view.cup_screen_position()
	var v := pos - c
	return atan2(v.y, v.x)
