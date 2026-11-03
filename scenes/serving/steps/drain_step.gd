class_name DrainStep
extends ServingStep

## The tofu bucket while there is still water on top.
##
## Taho vendors do not tip the bucket. The water pools on top of the silken
## tofu, and they lift it off with the flat scoop and throw it on the street,
## one scoop at a time.
##
## The hand pushes the scoop in. Drag down and it goes down with you, through
## the water easily; reach the tofu and it stops following, the hand moving on
## while the scoop barely gives. That is the cue, felt rather than read. The
## further it went through the water, the fuller it comes up. It can graze soft
## tofu, but pushed on into it, it brings broken tofu up with the water. Pull
## up and it comes up with you, out of the bucket, and is carried; let go to
## tip it. One stroke — down, up, over — the shape of a real scoop. Where it is
## tipped decides where the water goes, and the cup is the wrong answer.
##
## It used to sink on its own while the hand was held still, which put the
## depth on a timer instead of in the hand. Every scooping game that feels
## right maps the tool to the hand directly and lets the *material* push back.
##
## The water layer thins as you remove it, so every scoop has a shorter way to
## go before it meets the tofu. The step tightens the way the real one does.
##
## Depth is where the scoop actually got to, not where the hand is holding it.

const SCOOP_VOLUME := 0.38
const TOFU_PENALTY := 0.8

## Into the water at least this far, in depth units, or nothing comes up.
const MIN_DIP := 0.02

## Depth units the scoop goes down per bucket radius the hand drags down, and
## how much of the hand's push still reaches it once it is in the tofu. The
## second is the resistance: the hand keeps going and the scoop barely does.
const PUSH := 0.8
const GIVE := 0.3
const MAX_DEPTH := 1.3

## Pull the hand this far back above where it went in, in bucket radii, and the
## scoop comes up out of the bucket with whatever it caught.
const LIFT := 0.4

## How far past the top of the tofu the scoop can go before it breaks it. Soft
## tofu gives a little, and without this the last thin skin of water would
## take a precision nobody has.
const GRACE := 0.05

## The pointer this far to either side of the middle of the bucket mouth, in
## bucket radii, has left the bucket, and the scoop comes with it. Sideways
## only: dragging down past the near rim is pushing harder, not leaving.
const OUT := 1.35

## Water left standing makes a watery cup. Water tipped into the cup is worse.
const LEFT_PENALTY := 0.6
const CUP_PENALTY := 1.5

var water := 1.0
var tofu_lost := 0.0
var water_in_cup := 0.0
## Scoops of water thrown on the street.
var scoops := 0

var _dipping := false
var _carrying := false
## How deep the hand is holding the scoop, and how deep it actually got.
var _sink := 0.0
var _deepest := 0.0
var _hand_u := 0.0
## Where the scoop went in: the hand's height on screen, and the depth.
var _press_y := 0.0
var _entry := 0.0
var _travel := 0.0
var _last_u := 0.0
var _scooped := 0.0
## The bucket as it was when this scoop went in. A scoop is judged against the
## water it dipped into, not the water it leaves behind.
var _water_top := 0.0
var _tofu_top := 0.0


func _init() -> void:
	title = "Drain the water"
	focus = "tofu"


func begin() -> void:
	_view.set_bucket_water(water)
	_view.set_ladle(false, 0.0, 0.0)


## Depth of the top of the tofu, in the units the scoop is held at.
func band() -> float:
	return _view.tofu_surface_depth()


func pointer_down(pos: Vector2) -> void:
	if _view.zone_at(pos) != "tofu":
		return
	_dipping = true
	_hand_u = _u_at(pos)
	_press_y = pos.y
	_travel = 0.0
	_water_top = _view.water_surface_depth()
	_tofu_top = band()
	# It goes in at the surface of whatever is on top.
	_entry = maxf(_water_top - 0.05, 0.0)
	_sink = _entry
	_view.set_ladle(true, _hand_u, _sink)
	_deepest = _view.ladle_depth()
	_last_u = _view.ladle_u()


func pointer_move(pos: Vector2, _rel: Vector2) -> void:
	if _carrying:
		_view.carry_ladle(pos)
		return
	if not _dipping:
		return
	var pushed := (pos.y - _press_y) / maxf(_view.bucket_screen_extent(), 1.0)
	if _out(pos) or pushed < -LIFT:
		_lift_out(pos)
		return
	_hand_u = _u_at(pos)
	# The water gives way; the tofu pushes back. Past its top only a share of
	# the hand's push gets through, so the scoop all but stops on it.
	var want := _entry + pushed * PUSH
	if want > _tofu_top:
		want = _tofu_top + (want - _tofu_top) * GIVE
	_sink = clampf(want, -0.4, MAX_DEPTH)
	_drive()


func pointer_up(pos: Vector2) -> void:
	if _dipping:
		# Let go while still down in the bucket: nothing came up.
		_dipping = false
		_view.set_ladle(false, 0.0, 0.0)
		return
	if not _carrying:
		return
	_carrying = false

	match _view.zone_at(pos):
		"tofu":
			# Poured back. The water returns; any tofu it lifted does not.
			water += _scooped
			_view.set_bucket_water(water)
			_view.tip_ladle("tofu")
		"cup":
			water_in_cup += _scooped
			_view.tip_ladle("cup")
		_:
			if _scooped > 0.0:
				scoops += 1
			_view.tip_ladle("ground")
	_scooped = 0.0


func update(delta: float) -> void:
	if _dipping:
		_drive()
	_view.spill(_dipping and _deepest > _tofu_top + GRACE)


## Hold the scoop where the hand has it, and note where it really got to.
func _drive() -> void:
	# Below the top of the tofu it is cutting, and the tool drags like it.
	_view.set_ladle(true, _hand_u, _sink, 1.0 if _sink > _tofu_top else 0.0)
	var at: float = _view.ladle_u()
	_travel += absf(at - _last_u)
	_last_u = at
	_deepest = maxf(_deepest, _view.ladle_depth())


## The scoop came up out of the bucket, and whatever it caught is in it now.
func _lift_out(pos: Vector2) -> void:
	_dipping = false
	_carrying = true
	_scooped = 0.0

	if water > 0.0 and _deepest - _water_top >= MIN_DIP:
		# The further through the water, the fuller. A sweep while it is down
		# there gathers a little more.
		var through := clampf((_deepest - _water_top) / maxf(_tofu_top - _water_top, 0.01), 0.0, 1.0)
		var fullness := clampf(0.5 + 0.5 * through + _travel * 0.3, 0.0, 1.0)
		_scooped = minf(water, SCOOP_VOLUME * fullness)
		water -= _scooped
		var dug := _deepest - (_tofu_top + GRACE)
		if dug > 0.0:
			tofu_lost += dug * TOFU_PENALTY
			# And it leaves a dent, which is still there to shave around later.
			_view.gouge_tofu(_last_u, dug * 0.25)
		_view.set_bucket_water(water)

	_view.ladle_load("water", _scooped / SCOOP_VOLUME)
	_view.carry_ladle(pos)


func settle() -> void:
	_finish(1.0 - tofu_lost - water * LEFT_PENALTY - water_in_cup * CUP_PENALTY)


func complaint() -> String:
	if water_in_cup > 0.0 or water > 0.05:
		return "\"Matubig po.\""
	return "\"Durog po ang taho.\""


## While the scoop is down, the bar is a depth gauge with the top of the tofu
## marked on it. The rest of the time it is the water left.
func gauge() -> float:
	if _dipping:
		return _deepest / MAX_DEPTH
	return water


func gauge_target() -> float:
	if _dipping:
		return _tofu_top / MAX_DEPTH
	return 0.0


func gauge_name() -> String:
	return "Depth" if _dipping else "Water left"


func hint() -> String:
	if _dipping:
		if _deepest > _tofu_top + GRACE:
			return "Too deep — that's tofu you're lifting!"
		if _deepest >= _tofu_top - 0.02:
			return "Touching the tofu. Pull up!"
		if _deepest < _water_top:
			return "Hold still and let it sink into the water."
		return "Sinking through the water..."
	if _carrying:
		if _scooped <= 0.0:
			return "Nothing in it. Push it down into the water first."
		return "Tip it out on the street, away from the cup."
	if water_in_cup > 0.0:
		return "That was water in the cup!"
	if water <= 0.05:
		return "No more water. Now the scoop takes tofu."
	if scoops == 0:
		return "Press in the water, drag down to scoop, pull up and throw it on the street."
	return "Again. The water is thinner now."


# --- geometry, in bucket radii from the middle of the bucket mouth ---------

func _u_at(pos: Vector2) -> float:
	var centre: Vector2 = _view.bucket_screen_position()
	return (pos.x - centre.x) / maxf(_view.bucket_screen_extent(), 1.0)


func _out(pos: Vector2) -> bool:
	return absf(_u_at(pos)) > OUT
