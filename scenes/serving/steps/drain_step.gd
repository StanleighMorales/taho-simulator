class_name DrainStep
extends ServingStep

## Step 1 — tip the whey off the tofu.
##
## The tension: water only pours past a tilt, but tofu starts sliding out at a
## steeper one, and the gap between them is narrow enough to demand care.
## Finishing requires setting the bucket back down, which reads as deliberate.

const TILT_MAX := 46.0
const DRAIN_ANGLE := 12.0
const SPILL_ANGLE := 33.0

var tilt := 0.0
var water := 1.0
var tofu_lost := 0.0

var _holding := false


func _init() -> void:
	title = "Drain the whey"


func begin() -> void:
	_view.set_bucket_water(water)


func pointer_down(_pos: Vector2) -> void:
	_holding = true


func pointer_up(_pos: Vector2) -> void:
	_holding = false


func pointer_move(_pos: Vector2, rel: Vector2) -> void:
	if _holding:
		tilt = clampf(tilt - rel.y * 0.16, 0.0, TILT_MAX)


func update(delta: float) -> void:
	if not _holding:
		tilt = move_toward(tilt, 0.0, 70.0 * delta)

	if tilt > DRAIN_ANGLE and water > 0.0:
		water = maxf(0.0, water - (tilt - DRAIN_ANGLE) * 0.055 * delta)
		_view.set_bucket_water(water)

	_view.spill(tilt > SPILL_ANGLE)

	if tilt > SPILL_ANGLE:
		tofu_lost += (tilt - SPILL_ANGLE) * 0.012 * delta

	_view.set_bucket_tilt(tilt)

	if water <= 0.005 and tilt < 5.0:
		_finish(1.0 - tofu_lost * 2.4)


func hint() -> String:
	if tilt > SPILL_ANGLE:
		return "Too steep — you're losing tofu!"
	if water > 0.005:
		return "Drag up to tilt. Pour off the water, not the tofu."
	return "Clean. Now set it back down."


func gauge() -> float:
	return water


func gauge_target() -> float:
	return 0.0
