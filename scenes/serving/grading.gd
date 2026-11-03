class_name Grading
extends RefCounted

## Turns the step scores into a Sarap rating, a price and a tip.
##
## Weights say what the game cares about: the two pours that decide how it
## tastes matter most, and the handover is not scored at all.

const WEIGHTS := {
	# Getting the size right matters, but it is listening, not cooking.
	"Pick the cup": 0.5,
	# Opening the lid and handing the cup over are not skills. Weighting them
	# would only dilute the steps that decide how it tastes.
	"Open the bucket": 0.0,
	"Drain the water": 1.0,
	"Shave the tofu": 1.4,
	"Add the sago": 1.2,
	"Pour the arnibal": 1.5,
	"Swirl it through": 1.3,
	"Serve it": 0.0,
}

## A perfect cup earns a tip of up to half its price.
const TIP_SHARE := 0.5


static func sarap(steps: Array) -> float:
	var total := 0.0
	var weight_sum := 0.0
	for step in steps:
		var w: float = WEIGHTS.get(step.title, 1.0)
		total += step.score * w
		weight_sum += w
	if weight_sum <= 0.0:
		return 0.0
	return clampf(total / weight_sum, 0.0, 1.0)


static func grade_label(value: float) -> String:
	if value >= 0.85:
		return "SARAP!"
	if value >= 0.6:
		return "Ayos"
	if value >= 0.35:
		return "Hmm..."
	return "Patawad po"


## What the customer says. A good cup gets praise; anything less gets the one
## thing that was most wrong with it, so the player learns what to fix by
## tasting, not by reading a score breakdown.
static func reaction(value: float, steps: Array = []) -> String:
	if value >= 0.85:
		return "\"Ahhh! Ganito dapat, Lolo.\""
	var worst: ServingStep = null
	for step in steps:
		if WEIGHTS.get(step.title, 0.0) <= 0.0 or step.complaint() == "":
			continue
		if worst == null or step.score < worst.score:
			worst = step
	if worst != null and worst.score < 0.85:
		return worst.complaint()
	if value >= 0.6:
		return "\"Salamat po!\""
	return "\"Uhm. Salamat na lang po.\""


## The cup's price, always — a bad cup is still paid for — plus the tip.
static func payment(value: float, price := 20) -> int:
	return price + tip(value, price)


static func tip(value: float, price := 20) -> int:
	return int(round(price * TIP_SHARE * maxf(0.0, (value - 0.45) / 0.55)))
