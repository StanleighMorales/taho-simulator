class_name ShaveStep
extends ServingStep

## Step 2 — shave silky layers of tofu into the cup.
##
## The cup fills with what the scoop actually lifted out of the bucket, and
## the bucket is a real surface (`TofuSurface`) that remembers where you have
## been. A flat blade rides the high points, so grinding one groove stops
## paying almost immediately and the bucket has to be worked across. That is
## a constraint rather than a score: the player cannot fill a cup badly, they
## can only fill it slowly.
##
## Quality is still *evenness of the hand*: the step samples how much the
## sweep speed changes frame to frame, so confident steady arcs score well
## and jerky stabs crumble the tofu. The skill is "move smoothly", not "move
## fast".

const OVERFILL_PENALTY := 1.8

## How far below the rim the flat scoop rides while it shaves. It is taking
## the top off the tofu, not digging.
const BITE_DEPTH := 0.12

var fill := 0.0
var overfill := 0.0
var smoothness := 0.0

var sheets := 0

var _holding := false
var _last_speed := 0.0
var _samples := 0
var _idle := 0.0
var _last_u := 0.0
var _has_u := false
var _direction := 0.0


func _init() -> void:
	title = "Shave the tofu"


func pointer_down(pos: Vector2) -> void:
	_holding = true
	_last_speed = 0.0
	_last_u = _u_at(pos)
	_has_u = true
	_view.set_ladle(true, _last_u, BITE_DEPTH, 0.0)


func pointer_up(_pos: Vector2) -> void:
	_holding = false
	_view.set_ladle(false, 0.0, 0.0)


func pointer_move(pos: Vector2, rel: Vector2) -> void:
	if not _holding:
		return
	var speed := absf(rel.x)
	var u := _u_at(pos)

	# Drive the scoop on every move, including the ones too slow to lift
	# anything, so the tool never freezes halfway through a sweep. The bite
	# scales with the stroke, which is what makes the scoop drag against the
	# tofu instead of gliding over it.
	_view.set_ladle(true, u, BITE_DEPTH, clampf(speed * 0.08, 0.0, 1.0))

	if speed < 0.6:
		return

	# How far the blade travelled through the tofu, in bucket radii. Measuring
	# travel rather than time is what keeps the yield the same whether the
	# sweep is quick or slow — speed is step 2's *quality*, not its rate.
	var travel := absf(u - _last_u) if _has_u else 0.0
	_count_sheet(u)
	_last_u = u
	_has_u = true

	_idle = 0.0
	var added: float = _view.carve_tofu(u, travel) / TofuSurface.PER_CUP
	if fill < 1.0:
		fill = minf(1.0, fill + added)
	else:
		overfill += added

	# Jerkiness is the change in speed, not the speed itself.
	var jerk := absf(speed - _last_speed)
	smoothness += clampf(1.0 - jerk * 0.055, 0.0, 1.0)
	_samples += 1
	_last_speed = speed

	_view.set_cup_tofu(fill)
	_view.shave_tick(fill)


## Each pass of the blade lays one sheet, so a reversal is a new sheet.
func _count_sheet(u: float) -> void:
	var step_dir := signf(u - _last_u)
	if step_dir == 0.0:
		return
	if _direction == 0.0 or step_dir != _direction:
		_direction = step_dir
		sheets += 1
		_view.set_cup_sheets(sheets)


func update(delta: float) -> void:
	_idle += delta
	if fill >= 1.0 and _idle > 0.45:
		_view.set_ladle(false, 0.0, 0.0)
		var avg := smoothness / maxf(1.0, float(_samples))
		_finish(avg - overfill * OVERFILL_PENALTY)


func hint() -> String:
	if fill < 1.0:
		return "Sweep side to side. Smooth, even strokes."
	return "Full. Lift the ladle."


func gauge() -> float:
	return fill


func gauge_target() -> float:
	return 1.0


## Sideways position in bucket radii, same units the skim step works in.
func _u_at(pos: Vector2) -> float:
	var centre: Vector2 = _view.bucket_screen_position()
	return (pos.x - centre.x) / maxf(_view.bucket_screen_extent(), 1.0)
