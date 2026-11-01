class_name SagoStep
extends ServingStep

## Step 3 — spoon in the sago pearls.
##
## No "done" button: the step ends when the player stops adding. Knowing when
## to stop IS the interaction, and an explicit confirm would dull it.

const TARGET := 0.62
const PER_SCOOP := 0.155
const SETTLE_TIME := 1.0

var amount := 0.0

var _idle := 0.0
var _scoops := 0


func _init() -> void:
	title = "Add the sago"


func pointer_down(_pos: Vector2) -> void:
	amount += PER_SCOOP * randf_range(0.9, 1.1)
	_scoops += 1
	_idle = 0.0
	_view.set_cup_sago(minf(amount, 1.0))
	_view.sago_plop()


func update(delta: float) -> void:
	_idle += delta
	if _scoops > 0 and _idle > SETTLE_TIME:
		_finish(1.0 - absf(amount - TARGET) / TARGET)


func hint() -> String:
	if _scoops == 0:
		return "Tap to spoon in pearls. Stop when it looks right."
	return "Stop whenever you're happy."


func gauge() -> float:
	return amount


func gauge_target() -> float:
	return TARGET
