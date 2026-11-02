extends Node

## Money, supplies and the day's tally.
##
## Thin on purpose: no logic that belongs to a scene, no node references. The
## roaming world and the serving minigame both read it, which is what keeps
## them from reaching into each other.

signal money_changed(money: int)
signal supplies_changed()

## One full load of the buckets, in cups.
const LOAD_SIZE := 12

var money := 0
var served := 0

## Cups left in the buckets. Tofu is the one that gates a sale; sago and
## arnibal run out sooner or later than the tofu depending on how heavy a
## hand you have, which is what makes a refill trip a decision.
var tofu := LOAD_SIZE
var sago := LOAD_SIZE
var arnibal := LOAD_SIZE


func can_serve() -> bool:
	return tofu > 0


## Called once an order is handed over. `sago_used` and `arnibal_used` are the
## step scores' raw amounts, 0..1 of a cup's worth.
func spend_supplies(sago_used: float, arnibal_used: float) -> void:
	tofu = maxi(0, tofu - 1)
	sago = maxi(0, sago - int(ceil(sago_used)))
	arnibal = maxi(0, arnibal - int(ceil(arnibal_used)))
	supplies_changed.emit()


func refill() -> void:
	tofu = LOAD_SIZE
	sago = LOAD_SIZE
	arnibal = LOAD_SIZE
	supplies_changed.emit()


func earn(pay: int) -> void:
	money += pay
	served += 1
	money_changed.emit(money)


func supplies_line() -> String:
	return "tofu %d   sago %d   arnibal %d" % [tofu, sago, arnibal]
