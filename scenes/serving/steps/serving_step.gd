class_name ServingStep
extends RefCounted

## One step of the serving minigame.
##
## A step owns a little state, reads pointer gestures in screen space (so mouse
## and touch behave identically), drives the view's visuals, and reports a 0..1
## quality score when it finishes. The view polls `complete` rather than using
## signals, which keeps step ordering in one readable place.

var title := ""
## Where this step works: "cups", "tofu", "syrup", "cup", or "" for the whole
## setup. The view frames and lights that part, so the player's eye is
## already where the hand needs to go.
var focus := ""
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


## What the gauge is measuring, written on the bar.
func gauge_name() -> String:
	return ""


## The part of the setup in use right now, for the glow. A step that works in
## one place is always there.
func working() -> String:
	return focus


## The cup has been handed over: score whatever this tool did. Steps that end
## on their own never see this.
func settle() -> void:
	pass


## What the customer says when this is the worst thing about the cup.
func complaint() -> String:
	return ""


func _finish(quality: float) -> void:
	score = clampf(quality, 0.0, 1.0)
	complete = true
