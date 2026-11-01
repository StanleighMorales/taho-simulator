class_name SkimStep
extends ServingStep

## Step 1 — skim the water off the tofu.
##
## Taho vendors do not tip the bucket. The whey pools on top of the silken
## tofu and they lift it off with the flat ladle, one scoop at a time.
##
## So one scoop is one gesture: dip in, sweep across, lift out. The only thing
## that matters is how deep you dipped. Stay in the water and you take only
## water; go below it and you bring up tofu with it.
##
## The water layer thins as you remove it, so every scoop has to be shallower
## than the last. The step tightens exactly the way the real one does.

const SCOOP_VOLUME := 0.38
const MIN_DIP := 0.10
const LIFT_CLEARANCE := 0.15
const TOFU_PENALTY := 0.8

var water := 1.0
var tofu_lost := 0.0
var scoops := 0

var _scooping := false
var _deepest := 0.0
var _travel := 0.0
var _last_u := 0.0
var _settle := 0.0


func _init() -> void:
	title = "Skim the water"


func begin() -> void:
	_view.set_bucket_water(water)
	_view.set_ladle(false, 0.0, 0.0)


## How deep the water still lies. Shrinks as the whey is removed.
func band() -> float:
	return 0.18 + 0.52 * water


func pointer_down(pos: Vector2) -> void:
	if absf(_u_at(pos)) > 1.4:
		return
	_scooping = true
	# Where you put the ladle in counts as part of the dip.
	_deepest = _depth_at(pos)
	_travel = 0.0
	_last_u = _u_at(pos)
	_view.set_ladle(true, _last_u, _depth_at(pos))


func pointer_move(pos: Vector2, _rel: Vector2) -> void:
	if not _scooping:
		return
	var u := _u_at(pos)
	_travel += absf(u - _last_u)
	_last_u = u
	_deepest = maxf(_deepest, _depth_at(pos))
	_view.set_ladle(true, u, _depth_at(pos))


func pointer_up(pos: Vector2) -> void:
	if not _scooping:
		return
	_scooping = false
	_view.set_ladle(false, 0.0, 0.0)

	# It only counts as a scoop if the ladle went in and came back out.
	if _deepest < MIN_DIP:
		return
	if _depth_at(pos) > _deepest - LIFT_CLEARANCE:
		return

	scoops += 1
	# Judge the dip against how deep the water was WHEN the ladle went in,
	# not after this scoop has already removed some of it.
	var water_depth := band()

	# A wider sweep gathers a fuller ladle.
	var fullness := clampf(0.45 + _travel * 0.7, 0.45, 1.0)
	water = maxf(0.0, water - SCOOP_VOLUME * fullness)

	if _deepest > water_depth:
		tofu_lost += (_deepest - water_depth) * TOFU_PENALTY

	_view.set_bucket_water(water)
	_view.skim_splash()


func update(delta: float) -> void:
	_view.spill(_scooping and _deepest > band())

	if water <= 0.02 and not _scooping:
		_settle += delta
		if _settle > 0.35:
			_finish(1.0 - tofu_lost)


func hint() -> String:
	if _scooping and _deepest > band():
		return "Too deep — that's tofu you're lifting!"
	if scoops == 0:
		return "Dip the ladle in, sweep across, lift it out."
	if water > 0.02:
		return "Again — shallower now, the water is thinner."
	return "Clean."


func gauge() -> float:
	return water


func gauge_target() -> float:
	return 0.0


# --- geometry, in bucket radii from the middle of the bucket mouth ---------

func _u_at(pos: Vector2) -> float:
	var centre: Vector2 = _view.bucket_screen_position()
	return (pos.x - centre.x) / maxf(_view.bucket_screen_extent(), 1.0)


func _depth_at(pos: Vector2) -> float:
	var centre: Vector2 = _view.bucket_screen_position()
	return (pos.y - centre.y) / maxf(_view.bucket_screen_extent(), 1.0)
