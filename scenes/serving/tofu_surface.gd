class_name TofuSurface
extends RefCounted

## The tofu in the bucket, as a surface you can actually take material off.
##
## Before this, the tofu was a cylinder that got shorter and a `fill` number
## that went up, and nothing was ever taken from anywhere and put anywhere
## else. You could not form a mental model of the stuff: no trench from your
## last stroke, no reason to work one side rather than another.
##
## **One dimension, not two.** The gesture that shaves tofu is a sideways
## sweep — it has no depth component at all — so the surface is a profile
## across the bucket, extruded front to back. Modelling an axis the player
## cannot address would cost work and buy nothing.
##
## Heights run 0 (scraped to the bottom) to 1 (a full bucket).

## Samples across the full width of the bucket.
const SAMPLES := 24

## How deep one pass of the blade bites.
const LAYER := 0.045

## How much of the bucket the scoop covers, in bucket radii either side.
const REACH := 0.5

## Total height removed to fill one cup. Roughly five full sweeps.
const PER_CUP := 5.4

var heights: PackedFloat32Array


func _init() -> void:
	refill()


func refill() -> void:
	heights = PackedFloat32Array()
	heights.resize(SAMPLES)
	heights.fill(1.0)


## Take a thin layer wherever the blade is. `u` is the middle of the blade in
## bucket radii (-1 at the left wall, +1 at the right), and `effort` is how
## far it travelled, in the same units. Returns how much was actually lifted,
## which is the whole point: asking for more than is there gets you less.
##
## The rule is that the blade cannot cut more than one layer below the
## **highest** part of the surface. A flat blade rides on the high points: it
## cannot dig a well. So grinding away at one spot stops paying almost at
## once, and the only way to keep taking tofu is to work the whole bucket
## down together — which is what a vendor does, and now the player has to.
func carve(u: float, effort: float) -> float:
	if effort <= 0.0:
		return 0.0

	var limit := maxf(0.0, highest() - LAYER)
	var taken := 0.0
	for i in _covered(u):
		var allow := maxf(0.0, heights[i] - limit)
		if allow <= 0.0:
			continue
		var cut := minf(allow, effort)
		heights[i] -= cut
		taken += cut
	return taken


## A gouge rather than a shave: digging below the water in step 1 takes a bite
## out of the tofu, and the dent is still there when it is time to shave.
## Deliberately not bound by `carve`'s levelling rule — that rule is about a
## flat blade riding the surface, and this is the opposite of that.
func gouge(u: float, depth: float) -> void:
	for i in _covered(u):
		heights[i] = maxf(0.0, heights[i] - depth)


func height_at(u: float) -> float:
	return heights[_index(u)]


func highest() -> float:
	var top := 0.0
	for h in heights:
		top = maxf(top, h)
	return top


func lowest() -> float:
	var bottom := 1.0
	for h in heights:
		bottom = minf(bottom, h)
	return bottom


## 1.0 when the surface is dead level, falling off as it gets ragged. Not used
## for scoring — `carve` already makes levelling compulsory rather than
## merely rewarded — but it is what the bucket's state is worth reporting as.
func levelness() -> float:
	return 1.0 - clampf((highest() - lowest()) / 0.5, 0.0, 1.0)


## How much is left, 0..1, as a share of a full bucket.
func remaining() -> float:
	var total := 0.0
	for h in heights:
		total += h
	return total / float(SAMPLES)


func _index(u: float) -> int:
	var t := (clampf(u, -1.0, 1.0) + 1.0) * 0.5
	return clampi(int(round(t * float(SAMPLES - 1))), 0, SAMPLES - 1)


## The samples under the blade when it is centred at `u`.
func _covered(u: float) -> Array:
	var from_i := _index(u - REACH)
	var to_i := _index(u + REACH)
	return range(from_i, to_i + 1)
