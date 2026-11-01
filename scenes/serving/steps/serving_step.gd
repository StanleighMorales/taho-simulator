class_name ServingStep
extends RefCounted

## One step of the serving minigame.
##
## A step owns a little state, reads pointer gestures in screen space (so mouse
## and touch behave identically), drives the view's visuals, and reports a 0..1
## quality score when it finishes. The view polls `complete` rather than using
## signals, which keeps step ordering in one readable place.

var title := ""
var score := 0.0
var complete := false

# Anything answering the view's methods; a test stub is deliberately allowed.
var _view: Object = null


func setup(view: Object) -> void:
	_view = view


## Called once when this step becomes the active one.
func begin() -> void:
	pass


func update(_delta: float) -> void:
	pass


func pointer_down(_pos: Vector2) -> void:
	pass


func pointer_up(_pos: Vector2) -> void:
	pass


func pointer_move(_pos: Vector2, _rel: Vector2) -> void:
	pass


## Live hint, so a step can coach mid-gesture rather than only up front.
func hint() -> String:
	return ""


## 0..1 bar value, or -1 to hide the gauge.
func gauge() -> float:
	return -1.0


## 0..1 marker position on the gauge, or -1 for none.
func gauge_target() -> float:
	return -1.0


func _finish(quality: float) -> void:
	score = clampf(quality, 0.0, 1.0)
	complete = true
