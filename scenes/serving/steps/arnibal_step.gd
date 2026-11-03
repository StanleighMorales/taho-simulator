class_name ArnibalStep
extends ServingStep

## Step 6 — pour the melted brown sugar.
##
## Hold the dipper down in the arnibal and it fills; the longer you hold, the
## more it carries. Carry it to the cup and tip it, and the whole dipperful
## goes in — thick syrup does not stop halfway. So the skill is judging the
## load before you lift it, and the slow tail after the tip makes the amount
## feel physical rather than counted.

const TARGET := 0.70

## A full dipper, as a share of a P20 cup: two of them is a P20 cup.
const PER_DIP := 0.35

## Seconds held under to fill the dipper.
const FILL_TIME := 1.1

## How quickly what has been tipped runs into the cup. Proportional to what is
## left, so the last of it trails off the way thick syrup does.
const FLOW := 3.2
const MIN_FLOW := 0.05

var level := 0.0
var overflow := 0.0
## 0..1 of a full dipper.
var dipper := 0.0
var pours := 0

var _filling := false
var _carrying := false
## Tipped, not yet in the cup.
var _running := 0.0


func _init() -> void:
	title = "Pour the arnibal"
	focus = "syrup"


func begin() -> void:
	_view.rest_dipper()


func pointer_down(pos: Vector2) -> void:
	if _view.zone_at(pos) != "arnibal":
		return
	_carrying = true
	_filling = true
	dipper = 0.0
	_view.dip_dipper(pos)


func pointer_move(pos: Vector2, _rel: Vector2) -> void:
	if _filling and _view.zone_at(pos) == "arnibal":
		_view.dip_dipper(pos)
		return
	_filling = false
	_view.set_dipper(true, pos)


func pointer_up(pos: Vector2) -> void:
	if not _carrying:
		return
	_carrying = false
	_filling = false
	match _view.zone_at(pos):
		"cup":
			_running += dipper * PER_DIP / _view.cup_capacity()
			pours += 1
			_view.tip_dipper("cup")
		"arnibal":
			_view.dipper_load("", 0.0)
		_:
			_view.tip_dipper("ground")
	dipper = 0.0


func update(delta: float) -> void:
	if _filling:
		dipper = minf(1.0, dipper + delta / FILL_TIME)
		_view.dipper_load("arnibal", dipper)

	if _running > 0.0:
		var flow := minf(_running, maxf(_running * FLOW, MIN_FLOW) * delta)
		_running -= flow
		_pour(flow)

	_view.pour_stream(clampf(_running * 6.0, 0.0, 1.0))


func _pour(amount: float) -> void:
	level += amount
	if level > 1.0:
		overflow += level - 1.0
		level = 1.0
	_view.set_cup_arnibal(level)


func settle() -> void:
	# Whatever is still running lands; handing the cup over does not catch it.
	_pour(_running)
	_running = 0.0
	_view.pour_stream(0.0)
	_finish(1.0 - absf(level - TARGET) / TARGET - overflow * 2.0)


func complaint() -> String:
	if level < TARGET:
		return "\"Matabang po.\""
	return "\"Ang tamis po!\""


func gauge() -> float:
	return level


func gauge_target() -> float:
	return TARGET


func gauge_name() -> String:
	return "Arnibal"


func hint() -> String:
	if _filling:
		return "Filling... lift it out when it holds enough."
	if _carrying:
		return "Tip it into the cup."
	if _running > 0.0:
		return "Running in..."
	if level <= 0.02:
		return "Hold the dipper in the arnibal (right side), then carry it to the cup."
	if level + overflow > TARGET + 0.06:
		return "That's very sweet."
	return "More, or stir it in the cup."
