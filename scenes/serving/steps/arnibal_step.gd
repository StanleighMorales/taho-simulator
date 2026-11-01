class_name ArnibalStep
extends ServingStep

## Step 4 — pour the melted brown sugar.
##
## The syrup keeps running after you let go. That lag is the entire skill:
## you have to release *before* the target, and the thickness makes the
## overshoot feel physical rather than unfair.

const TARGET := 0.70
const POUR_RATE := 0.44
const DRIP_DECAY := 2.6

var level := 0.0
var overflow := 0.0

var _pouring := false
var _drip := 0.0
var _settled := 0.0


func _init() -> void:
	title = "Pour the arnibal"


func pointer_down(_pos: Vector2) -> void:
	_pouring = true


func pointer_up(_pos: Vector2) -> void:
	_pouring = false


func update(delta: float) -> void:
	if _pouring:
		_drip = POUR_RATE
		_settled = 0.0
	else:
		_drip = move_toward(_drip, 0.0, DRIP_DECAY * delta * maxf(_drip, 0.08))

	if _drip > 0.0:
		level += _drip * delta
		if level > 1.0:
			overflow += (level - 1.0)
			level = 1.0
		_view.set_cup_arnibal(level)

	_view.pour_stream(_drip / POUR_RATE)

	if not _pouring and _drip <= 0.001:
		_settled += delta
		if _settled > 0.5 and level > 0.02:
			_finish(1.0 - absf(level - TARGET) / TARGET - overflow * 2.0)


func hint() -> String:
	if _pouring:
		return "Let go early — it keeps running."
	if level <= 0.02:
		return "Press and hold to pour."
	return "Settling..."


func gauge() -> float:
	return level


func gauge_target() -> float:
	return TARGET
