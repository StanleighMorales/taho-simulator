class_name SagoStep
extends ServingStep

## Step 5 — spoon in the sago pearls.
##
## Dip the thin dipper into the sago side of the syrup bucket, carry it to the
## cup, tip it. The dipper holds the same amount whatever the cup, so a P50
## cup is more trips than a P10. Knowing when to stop is the interaction, and
## the cup is where the player sees it.

const TARGET := 0.62

## One dipperful, as a share of a P20 cup.
const PER_DIP := 0.2

var amount := 0.0
var dips := 0

var _carrying := false


func _init() -> void:
	title = "Add the sago"
	focus = "syrup"


func begin() -> void:
	# Swap tools: the pearls come out of the syrup bucket on the thin dipper,
	# not on the wide scoop the tofu was shaved with.
	_view.set_ladle(false, 0.0, 0.0)
	_view.rest_dipper()


func pointer_down(pos: Vector2) -> void:
	if _view.zone_at(pos) != "sago":
		return
	_carrying = true
	_view.dip_dipper(pos)
	_view.dipper_load("sago", 1.0)


func pointer_move(pos: Vector2, _rel: Vector2) -> void:
	# The dipper tracks the hand between dips too, so the tool is a thing being
	# carried rather than something that blinks in where it is needed.
	_view.set_dipper(true, pos)


func pointer_up(pos: Vector2) -> void:
	if not _carrying:
		return
	_carrying = false
	match _view.zone_at(pos):
		"cup":
			amount += PER_DIP / _view.cup_capacity() * randf_range(0.9, 1.1)
			dips += 1
			_view.tip_dipper("cup")
			_view.set_cup_sago(minf(amount, 1.0))
			_view.sago_plop()
		"sago":
			_view.dipper_load("", 0.0)
		_:
			_view.tip_dipper("ground")


func settle() -> void:
	_finish(1.0 - absf(amount - TARGET) / TARGET)


func complaint() -> String:
	if amount < TARGET:
		return "\"Kulang po sa sago.\""
	return "\"Ang daming sago!\""


func gauge() -> float:
	return amount


func gauge_target() -> float:
	return TARGET


func gauge_name() -> String:
	return "Sago"


func hint() -> String:
	if _carrying:
		return "Tip it into the cup."
	if dips == 0:
		return "Dip into the sago (left side of the right bucket), carry it to the cup."
	if amount > TARGET + 0.1:
		return "That's a lot of sago."
	return "Another dip, or on to the arnibal."
