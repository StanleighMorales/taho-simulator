class_name SwirlStep
extends ServingStep

## Step 7 — swirl the arnibal through the tofu.
##
## The only step where the skill is *stopping*. Under-mixed is streaky,
## over-mixed goes flat muddy brown, and the ideal is a marbled middle.
## Mixing is accumulated angle around the cup, so it rewards real circles —
## and it is the dipper's angle, not the hand's. Set tofu holds the dipper
## back, so frantic circles turn into small slow ones.

const IDEAL := 0.66
const BAND := 0.5

var mix := 0.0

var _angle_ref := 0.0
var _has_ref := false
var _holding := false


func _init() -> void:
	title = "Swirl it through"
	focus = "cup"


func begin() -> void:
	_view.rest_dipper()


func pointer_down(pos: Vector2) -> void:
	_holding = true
	_has_ref = false
	_view.set_dipper(true, pos, 0.6)


func pointer_up(_pos: Vector2) -> void:
	_holding = false
	_has_ref = false
	_view.set_dipper(false, Vector2.ZERO)


func pointer_move(pos: Vector2, _rel: Vector2) -> void:
	if not _holding:
		return
	# Stirring through set tofu is work, so the dipper drags against it.
	_view.set_dipper(true, pos, 0.6)
	var tip: Vector2 = _view.dipper_screen_position()
	var c: Vector2 = _view.cup_screen_position()
	# Only stirring once it is actually in the cup. On its way over from the
	# syrup bucket it is just being carried.
	if tip.distance_to(c) > _view.bucket_screen_extent() * 1.2:
		_has_ref = false
		return
	var a := atan2(tip.y - c.y, tip.x - c.x)
	if not _has_ref:
		_angle_ref = a
		_has_ref = true
		return
	# Shortest signed delta, so crossing the -PI/PI seam doesn't spike.
	var d := wrapf(a - _angle_ref, -PI, PI)
	_angle_ref = a
	mix += absf(d) / TAU * 0.34
	_view.set_cup_mix(mix)


func settle() -> void:
	_finish(1.0 - absf(mix - IDEAL) / BAND)


func complaint() -> String:
	if mix < IDEAL:
		return "\"Hindi pa po nahalo.\""
	return "\"Sobrang halo na po.\""


func gauge() -> float:
	return minf(mix, 1.2) / 1.2


func gauge_target() -> float:
	return IDEAL / 1.2


func gauge_name() -> String:
	return "Mix"


func hint() -> String:
	if mix <= 0.05:
		return "Draw circles over the cup."
	if mix > IDEAL + BAND * 0.5:
		return "Careful — it's going muddy."
	return "Hand it over when the marbling looks right."
