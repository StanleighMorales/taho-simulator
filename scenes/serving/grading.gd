class_name Grading
extends RefCounted

## Turns six step scores into a Sarap rating, a price and a tip.
##
## Weights say what the game cares about: the two pours that decide how it
## tastes matter most, and the handover is not scored at all.

const WEIGHTS := {
	# Opening the lid and handing the cup over are not skills. Weighting them
	# would only dilute the five steps that decide how it tastes.
	"Open the bucket": 0.0,
	"Skim the water": 1.0,
	"Shave the tofu": 1.4,
	"Add the sago": 1.2,
	"Pour the arnibal": 1.5,
	"Swirl it through": 1.3,
	"Serve it": 0.0,
}

const BASE_PRICE := 15
const MAX_TIP := 10


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


static func reaction(value: float) -> String:
	if value >= 0.85:
		return "\"Ahhh! Ganito dapat, Lolo.\""
	if value >= 0.6:
		return "\"Salamat po!\""
	if value >= 0.35:
		return "\"Okay lang... konti pa sana ang arnibal.\""
	return "\"Uhm. Salamat na lang po.\""


static func payment(value: float) -> int:
	return BASE_PRICE + int(round(MAX_TIP * maxf(0.0, (value - 0.45) / 0.55)))
