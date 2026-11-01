class_name ShaveStep
extends ServingStep

## Step 2 — shave silky layers of tofu into the cup.
##
## Fill comes from sweeping sideways, but quality comes from *evenness*: the
## step samples how much the sweep speed changes frame to frame, so confident
## steady arcs score well and jerky stabs crumble the tofu. That makes the
## skill "move smoothly", not "move fast".

const OVERFILL_PENALTY := 1.8

var fill := 0.0
var overfill := 0.0
var smoothness := 0.0

var _holding := false
var _last_speed := 0.0
var _samples := 0
var _idle := 0.0


func _init() -> void:
	title = "Shave the tofu"


func pointer_down(_pos: Vector2) -> void:
	_holding = true
	_last_speed = 0.0


func pointer_up(_pos: Vector2) -> void:
	_holding = false


func pointer_move(_pos: Vector2, rel: Vector2) -> void:
	if not _holding:
		return
	var speed := absf(rel.x)
	if speed < 0.6:
		return

	_idle = 0.0
	var added := speed * 0.0022
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


func update(delta: float) -> void:
	_idle += delta
	if fill >= 1.0 and _idle > 0.45:
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
