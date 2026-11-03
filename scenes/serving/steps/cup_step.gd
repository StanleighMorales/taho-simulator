class_name CupStep
extends ServingStep

## Step 1 — pick the cup they asked for.
##
## Taho is sold by price, not by small, medium and large: "bente po" is the
## cup that costs twenty. The customer names a price and the cups stand in a
## row on the ground. Picking the wrong one is a mistake the customer calls
## out, which makes the order something to listen to rather than a menu.

const MISTAKE_COST := 0.5

var mistakes := 0

var _wanted := 0


func _init() -> void:
	title = "Pick the cup"
	focus = "cups"


func begin() -> void:
	_wanted = _view.wanted_price()


func pointer_down(pos: Vector2) -> void:
	var price: int = _view.cup_at(pos)
	if price == 0:
		return
	if price != _wanted:
		mistakes += 1
		_view.wrong_cup(price)
		return
	_view.pick_cup(price)
	_finish(1.0 - mistakes * MISTAKE_COST)


func hint() -> String:
	if mistakes > 0:
		return "Wrong size. They asked for P%d." % _wanted
	return "They want a P%d cup. Tap it." % _wanted
