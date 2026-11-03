class_name LidStep
extends ServingStep

## Step 2 — open the bucket.
##
## The tofu bucket has a hinged lid in the centre, and lifting it is how a
## serve actually begins. It is here for three reasons: it is the moment the
## steam comes out, which is the only way the player learns the taho is warm;
## it puts a hand on the equipment before any of it is being judged; and it
## gives the order a beginning instead of starting mid-task.
##
## Deliberately **not graded** — see `Grading.WEIGHTS`. Opening a lid is not a
## skill, and scoring it would only add noise to the Sarap.

## Bucket radii of upward drag needed to swing it clear. Generous: this is a
## greeting, not a test.
const TRAVEL := 1.3

var open := 0.0

var _dragging := false
var _opened := false


func _init() -> void:
	title = "Open the bucket"
	focus = "tofu"


func begin() -> void:
	_view.set_lid(0.0)


func pointer_down(_pos: Vector2) -> void:
	_dragging = true


func pointer_up(_pos: Vector2) -> void:
	_dragging = false


func pointer_move(_pos: Vector2, rel: Vector2) -> void:
	if not _dragging or _opened:
		return
	# Only upward drag counts, so it reads as lifting rather than rubbing.
	var lifted := maxf(0.0, -rel.y) / maxf(_view.bucket_screen_extent(), 1.0)
	open = clampf(open + lifted / TRAVEL, 0.0, 1.0)
	_view.set_lid(open)


func update(_delta: float) -> void:
	if _opened or open < 1.0:
		return
	_opened = true
	_view.lid_opened()
	_finish(1.0)


func gauge() -> float:
	return open


func gauge_target() -> float:
	return 1.0


func gauge_name() -> String:
	return "Lid"


func hint() -> String:
	if open <= 0.0:
		return "Drag upward to lift the lid."
	if open < 1.0:
		return "Keep going..."
	return "Warm."
