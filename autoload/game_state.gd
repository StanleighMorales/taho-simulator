extends Node

## Money, supplies and the day's tally.
##
## Thin on purpose: no logic that belongs to a scene, no node references. The
## roaming world and the serving minigame both read it, which is what keeps
## them from reaching into each other.

signal money_changed(money: int)
signal supplies_changed()

## One full load of the buckets, in P20 cups.
const LOAD_SIZE := 12

## Less tofu than this is scrapings, not a sale.
const MIN_TOFU := 0.1

var money := 0
var served := 0

## What is left in the buckets, in P20 cups. Fractional, because a P10 cup
## takes less than a P50 one and the bucket has to know the difference. Tofu
## is the one that gates a sale; sago and arnibal run out sooner or later than
## the tofu depending on how heavy a hand you have, which is what makes a
## refill trip a decision.
var tofu := float(LOAD_SIZE)
var sago := float(LOAD_SIZE)
var arnibal := float(LOAD_SIZE)


func can_serve() -> bool:
	return tofu > MIN_TOFU


## Called once an order is handed over, with what actually went into the cup
## (and on the street), in P20 cups.
func spend_supplies(tofu_used: float, sago_used: float, arnibal_used: float) -> void:
	tofu = maxf(0.0, tofu - tofu_used)
	sago = maxf(0.0, sago - sago_used)
	arnibal = maxf(0.0, arnibal - arnibal_used)
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
	return "tofu %d%%   sago %d%%   arnibal %d%%" % [
		_percent(tofu), _percent(sago), _percent(arnibal)]


func _percent(cups: float) -> int:
	return roundi(cups / LOAD_SIZE * 100.0)
