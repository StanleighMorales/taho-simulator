class_name ServeStep
extends ServingStep

## Step 6 — hand it over.
##
## Scored on nothing: after five judged steps, the handover should be relief,
## not one more test.

var _holding := false
var _delivered := false


func _init() -> void:
	title = "Serve it"


func begin() -> void:
	# Both hands on the cup now.
	_view.set_dipper(false, Vector2.ZERO)


func pointer_down(pos: Vector2) -> void:
	if _view.cup_screen_position().distance_to(pos) < 160.0:
		_holding = true


func pointer_move(pos: Vector2, _rel: Vector2) -> void:
	if _holding:
		_view.drag_cup_to(pos)


func pointer_up(pos: Vector2) -> void:
	if not _holding:
		return
	_holding = false
	if _view.customer_screen_position().distance_to(pos) < 180.0:
		_delivered = true
		_view.deliver_cup()
	else:
		_view.return_cup()


func update(_delta: float) -> void:
	if _delivered:
		_finish(1.0)


func hint() -> String:
	return "Drag the cup to the customer."
