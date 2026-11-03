class_name FreeServe
extends ServingStep

## Step 3 — the serve itself, in whatever order the player likes.
##
## Once the cup is down and the lid is open there are no more steps. A press
## picks up whatever is under it — the scoop in the tofu bucket, the dipper in
## either side of the syrup bucket, a stir in the cup — and that tool keeps the
## gesture until it is let go. A short cup can have more tofu shaved into it
## after the syrup is in, a pale one another dip of arnibal, and the order ends
## only when the cup is handed over. The cup is the scorecard.
##
## The scoop takes whatever it touches. While there is water on the tofu a dip
## lifts water (and, too deep, broken tofu with it). Once the water is gone the
## same scoop shaves sheets. Nobody tells the player which; the bucket does.
##
## Each tool is still one of the step classes, so its rules and its scoring are
## the ones the tests already pin down. This only decides who gets the pointer,
## and asks them all to settle when the cup goes over.

## Pulled this far out of the cup, in bucket radii, a stir becomes picking the
## cup up.
const LIFT_CUP := 1.4

var drain := DrainStep.new()
var shave := ShaveStep.new()
var sago := SagoStep.new()
var arnibal := ArnibalStep.new()
var swirl := SwirlStep.new()
var serve := ServeStep.new()

## Whoever has the pointer right now, and whoever had it last.
var _owner: ServingStep = null
var _last: ServingStep = null


func _init() -> void:
	title = "Serve"
	focus = "work"


func setup(view: Object) -> void:
	super.setup(view)
	for tool in tools():
		tool.setup(view)


func tools() -> Array:
	return [drain, shave, sago, arnibal, swirl, serve]


func begin() -> void:
	# Only the bucket needs setting up. The tools are picked up when they are
	# reached for, not laid out in advance.
	drain.begin()


func pointer_down(pos: Vector2) -> void:
	match _view.zone_at(pos):
		"tofu":
			_owner = drain if drain.water > 0.001 else shave
		"sago":
			_owner = sago
		"arnibal":
			_owner = arnibal
		"cup":
			_owner = swirl
		_:
			_owner = null
	if _owner != null:
		_last = _owner
		_owner.pointer_down(pos)


func pointer_move(pos: Vector2, rel: Vector2) -> void:
	if _owner == swirl:
		var out: float = _view.cup_screen_position().distance_to(pos) \
			/ maxf(_view.bucket_screen_extent(), 1.0)
		if out > LIFT_CUP:
			swirl.pointer_up(pos)
			_owner = serve
			_last = serve
			serve.pointer_down(_view.cup_screen_position())
	if _owner != null:
		_owner.pointer_move(pos, rel)


func pointer_up(pos: Vector2) -> void:
	if _owner != null:
		_owner.pointer_up(pos)
	_owner = null


func update(delta: float) -> void:
	for tool in tools():
		tool.update(delta)
	if serve.complete:
		complete = true


## Which bucket is in use right now, for the glow and the dimming.
func working() -> String:
	if _owner == drain or _owner == shave:
		return "tofu"
	if _owner == sago or _owner == arnibal:
		return "syrup"
	if _owner == swirl or _owner == serve:
		return "cup"
	return ""


func hint() -> String:
	return _shown().hint()


## The gauge belongs to the tool in hand, or the last one put down, so it
## always says something about what the player has just been doing.
func gauge() -> float:
	return _shown().gauge()


func gauge_target() -> float:
	return _shown().gauge_target()


func gauge_name() -> String:
	return _shown().gauge_name()


func _shown() -> ServingStep:
	if _owner != null:
		return _owner
	return _last if _last != null else drain


## The cup has been handed over: every tool settles what it did, and those are
## what gets graded.
func scored() -> Array:
	var judged := [drain, shave, sago, arnibal, swirl]
	for tool in judged:
		tool.settle()
	return judged + [serve]
