class_name ShaveStep
extends ServingStep

## Step 4 — shave silky layers of tofu and carry them to the cup.
##
## The scoop collects what it lifts out of the bucket, and the bucket is a real
## surface (`TofuSurface`) that remembers where you have been. A flat blade
## rides the high points, so grinding one groove stops paying almost at once
## and the bucket has to be worked across.
##
## Then the scoopful has to go somewhere. Carry it to the cup and tip it, and
## it lands as one sheet. A cup is a few trips, and each trip is a small
## decision: is one more scoop too much?
##
## The blade cuts wherever the scoop actually is, not where the hand is. In
## tofu the scoop has a top speed and falls behind a hand that rushes, so a
## fast sweep is not a faster cup — it is a scoop dragging along behind you.
##
## Push down while sweeping and the blade bites deeper, for as long as the hand
## keeps pushing. A deeper bite takes a thicker sheet — a scoop fills in fewer
## sweeps — but thick sheets are rough, and the tofu drags harder on the blade.
## Pull up, or carry it off the side of the bucket, and it comes out with you.
##
## Quality is still *evenness of the hand*: the step samples how much the sweep
## speed changes frame to frame, so confident steady arcs score well and jerky
## stabs crumble the tofu. The skill is "move smoothly", not "move fast".

const OVERFILL_PENALTY := 1.8

## Tofu dropped on the street, per `TofuSurface` unit.
const WASTE_PENALTY := 0.5

## How deep a full bite sits below the top of the tofu, in depth units.
const BITE_DEPTH := 0.06
## Half the scoop's thickness, in depth units: how far above the tofu its
## middle sits when it is resting on top.
const REST := 0.035

## The hand pushed this far below where it went in, in bucket radii, starts to
## bite, and this much further is a full bite. The first stretch is slack so
## the wobble of a sideways sweep does not roughen the sheets.
const BITE_SLACK := 0.08
const BITE_PUSH := 0.3

## Pull the hand this far back above where it went in, in bucket radii, and the
## scoop comes up out of the bucket.
const LIFT := 0.4

## A full bite cuts this much more than a skim, and costs this much of every
## stroke's smoothness.
const THICK := 1.0
const ROUGH := 0.25

## One scoopful, in `TofuSurface` units: three of them fill a P20 cup to
## `FULL` without spilling, so a full scoop every time is right for a P20 and
## the other sizes need a lighter last scoop.
const SCOOP_CAP := 0.6

## The pointer this far to either side of the middle of the bucket mouth, in
## bucket radii, has left the bucket, and the scoop comes with it.
const OUT := 1.35

## A cup this full counts as full. Nobody fills taho to the brim.
const FULL := 0.9

var fill := 0.0
var overfill := 0.0
var wasted := 0.0
var smoothness := 0.0
## What is in the scoop right now, in `TofuSurface` units.
var scooped := 0.0
## One per scoopful tipped in. The shader stripes the cup with them.
var sheets := 0

var _holding := false
var _carrying := false
var _last_speed := 0.0
var _samples := 0
var _last_u := 0.0
var _has_u := false
## Sweeps in a row that took nothing: the middle is down and the sides are not.
var _dry := 0
## How deep the bite is, 0 skimming to 1 a full bite.
var bite := 0.0
var _hand_u := 0.0
var _press_y := 0.0


func _init() -> void:
	title = "Shave the tofu"
	focus = "tofu"


func pointer_down(pos: Vector2) -> void:
	if _view.zone_at(pos) != "tofu":
		return
	_holding = true
	_last_speed = 0.0
	bite = 0.0
	_press_y = pos.y
	_hand_u = _u_at(pos)
	_view.set_ladle(true, _hand_u, _depth(), 0.0)
	_last_u = _view.ladle_u()
	_has_u = true
	_view.ladle_load("tofu", scooped / SCOOP_CAP)


func pointer_up(pos: Vector2) -> void:
	if _holding:
		# Set down in the bucket. Whatever it lifted stays in it for next time.
		_holding = false
		bite = 0.0
		_view.set_ladle(false, 0.0, 0.0)
		return
	if not _carrying:
		return
	_carrying = false

	match _view.zone_at(pos):
		"cup":
			_tip_into_cup()
		"tofu":
			_view.set_ladle(false, 0.0, 0.0)
		_:
			wasted += scooped
			scooped = 0.0
			_view.tip_ladle("ground")


func pointer_move(pos: Vector2, rel: Vector2) -> void:
	if _carrying:
		_view.carry_ladle(pos)
		return
	if not _holding:
		return

	var pushed := (pos.y - _press_y) / maxf(_view.bucket_screen_extent(), 1.0)
	if _out(pos) or pushed < -LIFT:
		_holding = false
		_carrying = true
		bite = 0.0
		_view.carry_ladle(pos)
		return

	# Drive the scoop on every move, including the ones too slow to lift
	# anything, so the tool never freezes halfway through a sweep. The drag
	# scales with the stroke and with how deep it bites, which is what makes
	# the scoop push against the tofu instead of gliding over it.
	var speed := absf(rel.x)
	bite = clampf((pushed - BITE_SLACK) / BITE_PUSH, 0.0, 1.0)
	_hand_u = _u_at(pos)
	_view.set_ladle(true, _hand_u, _depth(), maxf(clampf(speed * 0.08, 0.0, 1.0), bite))

	if speed < 0.6:
		return

	# How far the blade travelled through the tofu, in bucket radii. Measuring
	# travel rather than time is what keeps the yield the same whether the
	# sweep is quick or slow — speed is this step's *quality*, not its rate.
	# And it is the scoop's travel, which in tofu is behind the hand.
	var blade: float = _view.ladle_u()
	var travel := absf(blade - _last_u) if _has_u else 0.0
	_last_u = blade
	_has_u = true

	# A full scoop rides over the tofu without taking any more.
	if scooped < SCOOP_CAP:
		var taken: float = _view.carve_tofu(blade, travel, 1.0 + bite * THICK)
		scooped += taken
		_dry = 0 if taken > 0.0005 else _dry + 1
		_view.ladle_load("tofu", scooped / SCOOP_CAP)

	# Jerkiness is the change in speed, not the speed itself.
	var jerk := absf(speed - _last_speed)
	smoothness += clampf(1.0 - jerk * 0.055, 0.0, 1.0) * (1.0 - bite * ROUGH)
	_samples += 1
	_last_speed = speed


## Where the blade sits: resting on the tofu when it skims, and sunk to its
## rim in a full bite, so it is still there to be seen.
func _depth() -> float:
	return _view.tofu_surface_depth() - REST + bite * BITE_DEPTH


func _tip_into_cup() -> void:
	_view.tip_ladle("cup")
	if scooped <= 0.0:
		return
	fill += scooped / (TofuSurface.PER_CUP * _view.cup_capacity())
	scooped = 0.0
	sheets += 1
	if fill > 1.0:
		overfill += fill - 1.0
		fill = 1.0
	_view.set_cup_tofu(fill)
	_view.set_cup_sheets(sheets)


func settle() -> void:
	var avg := smoothness / maxf(1.0, float(_samples))
	# Scaled by how full the cup actually got. A no-op for a full cup, and the
	# only thing that makes a half-empty one score like one. This is also the
	# last cup of a load: a short cup, honestly graded, rather than a wait for
	# tofu that is not there.
	var full := clampf(fill / FULL, 0.0, 1.0)
	_finish(avg * full - overfill * OVERFILL_PENALTY - wasted * WASTE_PENALTY)


func complaint() -> String:
	if fill < 0.6:
		return "\"Konti lang po ang taho.\""
	if overfill > 0.0:
		return "\"Umaapaw po!\""
	return "\"Durog po ang taho.\""


func gauge() -> float:
	return fill


func gauge_target() -> float:
	return FULL


func gauge_name() -> String:
	return "Tofu"


func hint() -> String:
	if overfill > 0.0:
		return "It's spilling over the rim!"
	if _carrying:
		if scooped <= 0.0:
			return "Empty scoop. Shave some first."
		if fill + scooped / (TofuSurface.PER_CUP * _view.cup_capacity()) > 1.0:
			return "That's more than the cup has room for."
		return "Tip it into the cup."
	if fill >= FULL:
		return "Full. The sago and arnibal are in the other bucket."
	if _view.tofu_remaining() <= 0.002:
		return "That is the last of it."
	if scooped >= SCOOP_CAP:
		return "The scoop is full. Carry it to the cup."
	if _holding and _dry > 25 and _view.tofu_remaining() > 0.002:
		return "Reach the sides, slower — the middle is scraped flat."
	if _holding and bite > 0.6:
		return "A deep bite: more tofu, rougher sheets."
	if _holding:
		return "Sweep side to side. Push down to bite deeper."
	if fill > 0.0:
		return "More. Shave another scoopful."
	return "Press on the tofu, sweep side to side, then carry it to the cup."


## Bucket radii from the middle of the bucket mouth, same units the drain
## step works in.
func _u_at(pos: Vector2) -> float:
	var centre: Vector2 = _view.bucket_screen_position()
	return (pos.x - centre.x) / maxf(_view.bucket_screen_extent(), 1.0)


func _out(pos: Vector2) -> bool:
	return absf(_u_at(pos)) > OUT
