extends SceneTree

## Headless tests for the serving steps.
##
##     godot --headless --script res://tests/run_step_tests.gd
##
## Steps never touch nodes directly — they call methods on the view — so a stub
## view is enough to drive every mechanic and assert the scoring. This checks
## the rules; whether the pour *feels* good is a judgement only a human makes.

const DT := 1.0 / 60.0

## Where the stub puts things on screen. The bucket is centred at (200, 200)
## with a 100px radius; the cup sits at (400, 300); the syrup bucket is at
## (600, 200), sago on its left half and arnibal on its right; and anywhere
## else is the street.
const TOFU := Vector2(200, 200)
const CUP := Vector2(400, 300)
const SAGO := Vector2(570, 200)
const ARNIBAL := Vector2(630, 200)
const STREET := Vector2(200, 600)

var _failures := 0
var _checks := 0


class StubView:
	extends RefCounted

	var water := 1.0
	var tofu := 0.0
	var sago := 0.0
	var arnibal := 0.0
	var mix := 0.0
	var delivered := false
	var ladle_active := false
	var lid_open := 0.0
	var lid_steaming := false
	var sheets := 0
	var capacity := 1.0
	var wanted := 20
	var picked := 0
	var wrong := 0
	var tips: Array[String] = []
	## The stub's tools go exactly where they are aimed, so the steps' rules
	## are tested without the lag. The lag itself is the feel tests' job.
	var tool_u := 0.0
	var tool_depth := 0.0
	var dipper_at := Vector2.ZERO
	## The real material model, not a fake. It is a plain RefCounted, so the
	## shave tests can exercise the actual tofu instead of a stand-in.
	var block := TofuSurface.new()

	func zone_at(pos: Vector2) -> String:
		if pos.distance_to(Vector2(400, 300)) < 80.0:
			return "cup"
		if pos.distance_to(Vector2(200, 200)) < 115.0:
			return "tofu"
		if pos.distance_to(Vector2(600, 200)) < 100.0:
			return "sago" if pos.x < 600.0 else "arnibal"
		return "ground"

	func wanted_price() -> int:
		return wanted

	func cup_capacity() -> float:
		return capacity

	func cup_at(pos: Vector2) -> int:
		for price in [10, 20, 50]:
			if pos.distance_to(Vector2(300 + (price / 10) * 20, 500)) < 15.0:
				return price
		return 0

	func pick_cup(price: int) -> void:
		picked = price

	func wrong_cup(_price: int) -> void:
		wrong += 1

	func bucket_screen_position() -> Vector2:
		return Vector2(200, 200)

	func bucket_screen_extent() -> float:
		return 100.0

	func set_ladle(active: bool, u: float, depth: float, _bite := 0.0) -> void:
		ladle_active = active
		tool_u = u
		tool_depth = depth

	func ladle_u() -> float:
		return tool_u

	func ladle_depth() -> float:
		return tool_depth

	func carry_ladle(_pos: Vector2) -> void:
		ladle_active = true

	func ladle_load(_kind: String, _amount: float) -> void:
		pass

	func tip_ladle(where: String) -> void:
		tips.append(where)
		ladle_active = false

	func set_dipper(_active: bool, pos: Vector2, _bite := 0.0) -> void:
		dipper_at = pos

	func dipper_screen_position() -> Vector2:
		return dipper_at

	func dip_dipper(_pos: Vector2) -> void:
		pass

	func dipper_load(_kind: String, _amount: float) -> void:
		pass

	func tip_dipper(where: String) -> void:
		tips.append(where)

	func rest_dipper() -> void:
		pass

	func carve_tofu(u: float, effort: float, thickness := 1.0) -> float:
		return block.carve(u, effort, thickness)

	func gouge_tofu(u: float, depth: float) -> void:
		block.gouge(u, depth)

	func tofu_remaining() -> float:
		return block.remaining()

	## The same geometry the view has: a 0.38-high block under a rim at 0.5,
	## a 0.12-high water layer, and 0.34 of depth per unit.
	func tofu_surface_depth() -> float:
		return (0.5 - 0.38 * block.highest()) / 0.34

	func water_surface_depth() -> float:
		return tofu_surface_depth() - 0.12 * water / 0.34

	func set_cup_sheets(count: int) -> void:
		sheets = count

	func set_lid(open: float) -> void:
		lid_open = open

	func lid_opened() -> void:
		lid_steaming = true

	func set_bucket_water(v: float) -> void:
		water = v

	func spill(_is_losing: bool) -> void:
		pass

	func set_cup_tofu(v: float) -> void:
		tofu = v

	func set_cup_sago(v: float) -> void:
		sago = v

	func sago_plop() -> void:
		pass

	func set_cup_arnibal(v: float) -> void:
		arnibal = v

	func pour_stream(_i: float) -> void:
		pass

	func set_cup_mix(v: float) -> void:
		mix = v

	func cup_screen_position() -> Vector2:
		return Vector2(400, 300)

	func customer_screen_position() -> Vector2:
		return Vector2(700, 200)

	func drag_cup_to(_p: Vector2) -> void:
		pass

	func deliver_cup() -> void:
		delivered = true

	func return_cup() -> void:
		pass


func _initialize() -> void:
	_test_tofu_surface()
	_test_cup()
	_test_lid()
	_test_drain_shallow()
	_test_drain_too_deep()
	_test_drain_where_it_goes()
	_test_drain_needs_lifting_out()
	_test_shave_smooth_beats_jerky()
	_test_shave_carry()
	_test_shave_runs_dry()
	_test_sago_amount()
	_test_arnibal()
	_test_swirl_sweet_spot()
	_test_serve()
	_test_grading()
	_test_focus()
	_test_free_serve()

	print("")
	if _failures == 0:
		print("ALL PASS  (%d checks)" % _checks)
	else:
		print("FAILED  %d of %d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


# --- helpers ---------------------------------------------------------------

func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _run(step: ServingStep, frames: int) -> void:
	for i in frames:
		step.update(DT)


func _make(step: ServingStep, capacity := 1.0) -> StubView:
	var view := StubView.new()
	view.capacity = capacity
	step.setup(view)
	step.begin()
	return view


## Hand the cup over: every tool settles what it did.
func _hand_over(step: ServingStep) -> void:
	step.settle()


# --- the cup ---------------------------------------------------------------

func _test_cup() -> void:
	print("cup — pick the size they asked for")

	var step := CupStep.new()
	var view := _make(step)
	step.pointer_down(Vector2(100, 100))
	_check("tapping the street picks nothing", not step.complete and view.wrong == 0)
	step.pointer_down(Vector2(340, 500))  # the P20 stack
	_check("the right cup completes the step", step.complete and view.picked == 20)
	_check("first time right is perfect", is_equal_approx(step.score, 1.0),
		"score=%.2f" % step.score)

	var fumble := CupStep.new()
	var fumble_view := _make(fumble)
	fumble.pointer_down(Vector2(400, 500))  # P50
	_check("the wrong cup is called out", fumble_view.wrong == 1)
	_check("and does not complete the step", not fumble.complete)
	fumble.pointer_down(Vector2(340, 500))
	_check("a fumble costs some of the score", fumble.complete and fumble.score < 1.0,
		"score=%.2f" % fumble.score)


# --- drain -----------------------------------------------------------------

## One trip: press in the water, drag down until the scoop is at `depth`,
## sweep across at that depth, pull up out of the bucket, carry it to `to`,
## let go. Works for a DrainStep or for a FreeServe routing to one.
func _scoop(step: ServingStep, depth: float, to: Vector2) -> void:
	var drain: DrainStep = step if step is DrainStep else step.drain
	var at := TOFU + Vector2(-40, 0)
	step.pointer_down(at)
	for i in 600:
		if drain._sink >= depth:
			break
		at.y += 1.0
		step.pointer_move(at, Vector2(0, 1))
		step.update(DT)
	step.pointer_move(Vector2(TOFU.x, at.y), Vector2(40, 0))
	step.pointer_move(Vector2(TOFU.x + 40, at.y), Vector2(40, 0))
	step.pointer_move(TOFU + Vector2(60, -150), Vector2.ZERO)  # pulled up and out
	step.pointer_move(to, Vector2.ZERO)
	step.pointer_up(to)
	step.update(DT)


## Always skim just inside the remaining water, as a careful vendor would, and
## throw it on the street.
func _drain_carefully() -> DrainStep:
	var step := DrainStep.new()
	_make(step)
	for i in 10:
		if step.water <= 0.05:
			break
		_scoop(step, step.band() + 0.02, STREET)
	_hand_over(step)
	return step


func _test_drain_shallow() -> void:
	print("drain — careful, inside the water")
	var step := _drain_carefully()
	_check("settles when the cup goes over", step.complete)
	_check("bucket ends clean", step.water <= 0.05, "water=%.3f" % step.water)
	_check("takes several trips", step.scoops >= 2, "scoops=%d" % step.scoops)
	_check("no tofu lifted", is_zero_approx(step.tofu_lost), "lost=%.4f" % step.tofu_lost)
	_check("scores near perfect", step.score > 0.95, "score=%.3f" % step.score)


func _test_drain_too_deep() -> void:
	print("drain — digging into the tofu")
	var careful := _drain_carefully()
	var step := DrainStep.new()
	_make(step)
	for i in 10:
		if step.water <= 0.05:
			break
		_scoop(step, 1.1, STREET)  # straight to the bottom every time
	_hand_over(step)
	_check("completes", step.complete)
	_check("lifts tofu out", step.tofu_lost > 0.0, "lost=%.4f" % step.tofu_lost)
	_check("scores worse than careful", step.score < careful.score - 0.2,
		"deep=%.3f careful=%.3f" % [step.score, careful.score])


func _test_drain_where_it_goes() -> void:
	print("drain — where you tip it")
	var careful := _drain_carefully()

	var into_cup := DrainStep.new()
	_make(into_cup)
	_scoop(into_cup, 0.3, CUP)
	for i in 10:
		if into_cup.water <= 0.05:
			break
		_scoop(into_cup, into_cup.band() + 0.02, STREET)
	_hand_over(into_cup)
	_check("water tipped into the cup is caught", into_cup.water_in_cup > 0.0)
	_check("and scores worse than throwing it on the street",
		into_cup.score < careful.score - 0.2,
		"cup=%.3f street=%.3f" % [into_cup.score, careful.score])

	var back := DrainStep.new()
	_make(back)
	_scoop(back, 0.3, TOFU)
	_check("tipping it back into the bucket puts the water back",
		is_equal_approx(back.water, 1.0), "water=%.3f" % back.water)

	var early := DrainStep.new()
	_make(early)
	_scoop(early, 0.3, STREET)
	_hand_over(early)
	_check("stopping with water still standing scores worse",
		early.complete and early.score < careful.score - 0.2,
		"early=%.3f careful=%.3f" % [early.score, careful.score])


func _test_drain_needs_lifting_out() -> void:
	print("drain — letting go without lifting out")
	var step := DrainStep.new()
	_make(step)
	step.pointer_down(TOFU + Vector2(-80, 0))
	step.pointer_move(TOFU + Vector2(0, 40), Vector2.ZERO)
	step.pointer_up(TOFU + Vector2(40, 40))  # let go still down in the bucket
	_check("nothing thrown", step.scoops == 0)
	_check("water untouched", is_equal_approx(step.water, 1.0), "water=%.3f" % step.water)

	var outside := DrainStep.new()
	_make(outside)
	outside.pointer_down(STREET)
	_check("pressing on the street does not pick the scoop up",
		not outside._dipping and not outside._carrying)

	# The depth is in the hand. Holding still is just holding still.
	var pushing := DrainStep.new()
	_make(pushing)
	pushing.pointer_down(TOFU)
	var top := pushing._sink
	_run(pushing, 120)
	_check("a still hand leaves the scoop where it is", is_equal_approx(pushing._sink, top),
		"moved %.3f" % (pushing._sink - top))
	pushing.pointer_move(TOFU + Vector2(0, 20), Vector2(0, 20))
	var water_push := pushing._sink - top
	pushing.pointer_move(TOFU + Vector2(0, 10), Vector2(0, -10))
	_check("drag down and it goes down, ease off and it comes back up",
		water_push > 0.0 and pushing._sink < top + water_push,
		"down=%.3f back=%.3f" % [water_push, pushing._sink - top])
	pushing.pointer_move(TOFU + Vector2(0, 200), Vector2(0, 190))
	var deep := pushing._sink
	pushing.pointer_move(TOFU + Vector2(0, 220), Vector2(0, 20))
	var tofu_push := pushing._sink - deep
	_check("the water gives way and the tofu pushes back",
		deep > pushing.band() and tofu_push < water_push * 0.5,
		"water=%.3f tofu=%.3f per 20px" % [water_push, tofu_push])
	pushing.pointer_move(TOFU + Vector2(0, -60), Vector2(0, -280))
	_check("pull up past where it went in and it comes out", pushing._carrying)

	var near := DrainStep.new()
	_make(near)
	near.pointer_down(TOFU + Vector2(0, 90))
	near.pointer_move(TOFU + Vector2(0, 160), Vector2(0, 70))
	_check("pushing down past the near rim is still pushing, not leaving",
		near._dipping and not near._carrying)


# --- shave -----------------------------------------------------------------

## Sweep the blade back and forth across the bucket, taking one `speeds` entry
## per frame, until the scoop is full or the bucket is.
func _sweep(step: ShaveStep, speeds: Array, frames: int, deep := false) -> int:
	var x := TOFU.x
	var dir := 1.0
	step.pointer_down(Vector2(x, TOFU.y))
	# Pushed down while it sweeps, so the blade bites to the full depth.
	var y := TOFU.y + (50.0 if deep else 0.0)
	if deep:
		step.pointer_move(Vector2(x, y), Vector2(0, 50))
	var i := 0
	while step.scooped < ShaveStep.SCOOP_CAP and i < frames:
		var dx: float = speeds[i % speeds.size()] * dir
		x += dx
		if x > TOFU.x + 95.0:
			x = TOFU.x + 95.0
			dir = -1.0
		elif x < TOFU.x - 95.0:
			x = TOFU.x - 95.0
			dir = 1.0
		step.pointer_move(Vector2(x, y), Vector2(absf(dx), 0))
		i += 1
		if step._view.tofu_remaining() <= 0.002:
			break
	return i


## Out of the bucket to the right, over to `to`, and let go.
func _carry(step: ShaveStep, to: Vector2) -> void:
	step.pointer_move(TOFU + Vector2(150, 0), Vector2(5, 0))
	step.pointer_move(to, Vector2.ZERO)
	step.pointer_up(to)


## Shave and carry scoopfuls until the cup is full, then press Done.
func _shave(speeds: Array, capacity := 1.0, deep := false) -> ShaveStep:
	var step := ShaveStep.new()
	_make(step, capacity)
	for trip in 20:
		if step.fill >= ShaveStep.FULL or step._view.tofu_remaining() <= 0.002:
			break
		_sweep(step, speeds, 3000, deep)
		_carry(step, CUP)
	_hand_over(step)
	return step


func _test_shave_smooth_beats_jerky() -> void:
	print("shave — smooth vs jerky")
	var smooth := _shave([12.0])
	var jerky := _shave([3.0, 34.0])
	_check("smooth completes", smooth.complete)
	_check("jerky completes", jerky.complete)
	_check("smooth scores well", smooth.score > 0.9, "score=%.3f" % smooth.score)
	_check("jerky scores worse", jerky.score < smooth.score - 0.2,
		"jerky=%.3f smooth=%.3f" % [jerky.score, smooth.score])
	_check("each scoopful laid a sheet", smooth.sheets >= 3, "sheets=%d" % smooth.sheets)

	# Working one spot is the case the surface exists to rule out. Wiggling
	# back and forth in place, which is what grinding actually looks like.
	var stuck := ShaveStep.new()
	var stuck_view := _make(stuck)
	stuck.pointer_down(TOFU + Vector2(60, 0))
	for i in 600:
		var x := TOFU.x + 60.0 + (8.0 if i % 2 == 0 else -8.0)
		stuck.pointer_move(Vector2(x, TOFU.y), Vector2(8, 0))
	_check("grinding one groove cannot fill the scoop",
		stuck.scooped < ShaveStep.SCOOP_CAP * 0.6, "scooped=%.2f" % stuck.scooped)
	_check("and it leaves that groove lower than the rest",
		stuck_view.block.lowest() < stuck_view.block.highest() - 0.01,
		"low=%.3f high=%.3f" % [stuck_view.block.lowest(), stuck_view.block.highest()])


func _test_shave_carry() -> void:
	print("shave — carrying it to the cup")

	var step := ShaveStep.new()
	var view := _make(step)
	_sweep(step, [12.0], 3000)
	_check("sweeping fills the scoop, not the cup",
		step.scooped >= ShaveStep.SCOOP_CAP and is_zero_approx(step.fill),
		"scooped=%.2f fill=%.2f" % [step.scooped, step.fill])
	_carry(step, CUP)
	_check("tipping it over the cup fills the cup", step.fill > 0.2 and step.scooped == 0.0,
		"fill=%.2f" % step.fill)
	_check("as one sheet", step.sheets == 1)
	_check("the view was told to tip into the cup", view.tips.back() == "cup")

	var dropped := ShaveStep.new()
	var dropped_view := _make(dropped)
	_sweep(dropped, [12.0], 3000)
	_carry(dropped, STREET)
	_check("tipping it on the street wastes it",
		dropped.wasted > 0.0 and is_zero_approx(dropped.fill),
		"wasted=%.2f" % dropped.wasted)
	_check("the view was told it hit the ground", dropped_view.tips.back() == "ground")

	var skim := ShaveStep.new()
	_make(skim)
	var skim_moves := _sweep(skim, [12.0], 3000)
	var bitten := ShaveStep.new()
	_make(bitten)
	var bite_moves := _sweep(bitten, [12.0], 3000, true)
	_check("pushing down bites deeper", bitten.bite > 0.99, "bite=%.2f" % bitten.bite)
	_check("and a deep bite fills the scoop in fewer sweeps", bite_moves < skim_moves * 0.7,
		"deep=%d skim=%d moves" % [bite_moves, skim_moves])
	var rough := _shave([12.0], 1.0, true)
	var silky := _shave([12.0])
	_check("but its sheets are rougher", rough.score < silky.score - 0.15,
		"deep=%.3f skim=%.3f" % [rough.score, silky.score])

	var small := _trips(0.6)
	var large := _trips(1.8)
	_check("a P50 cup takes more trips than a P10", large > small,
		"P10=%d P50=%d" % [small, large])

	var good := _shave([12.0])
	var greedy := _shave([12.0])
	for i in 3:
		_sweep(greedy, [12.0], 3000)
		_carry(greedy, CUP)
	greedy.settle()
	_check("piling on past full spills over the rim", greedy.overfill > 0.0,
		"overfill=%.2f" % greedy.overfill)
	_check("and scores worse than stopping", greedy.score < good.score - 0.2,
		"greedy=%.3f good=%.3f" % [greedy.score, good.score])


func _trips(capacity: float) -> int:
	var step := ShaveStep.new()
	_make(step, capacity)
	for trip in 30:
		if step.fill >= ShaveStep.FULL:
			return trip
		_sweep(step, [12.0], 3000)
		_carry(step, CUP)
	return 30


# --- sago ------------------------------------------------------------------

func _dip(step: ServingStep, from: Vector2, to: Vector2, hold_frames := 0) -> void:
	step.pointer_down(from)
	_run(step, hold_frames)
	step.pointer_move(to, Vector2.ZERO)
	step.pointer_up(to)
	step.update(DT)


func _sago(dips: int, capacity := 1.0) -> SagoStep:
	var step := SagoStep.new()
	_make(step, capacity)
	for i in dips:
		_dip(step, SAGO, CUP)
	_hand_over(step)
	return step


func _test_sago_amount() -> void:
	print("sago — knowing when to stop")
	var good := _sago(3)   # 3 x ~0.2 lands near the 0.62 target
	var greedy := _sago(9)
	_check("settles when the cup goes over", good.complete)
	_check("on-target scores well", good.score > 0.85, "score=%.3f" % good.score)
	_check("overloading scores badly", greedy.score < 0.25, "score=%.3f" % greedy.score)

	var spilled := SagoStep.new()
	_make(spilled)
	_dip(spilled, SAGO, STREET)
	_check("a dip tipped on the street adds nothing", is_zero_approx(spilled.amount))

	var nowhere := SagoStep.new()
	_make(nowhere)
	_dip(nowhere, ARNIBAL, CUP)
	_check("dipping the wrong side adds no sago", is_zero_approx(nowhere.amount))

	var big := SagoStep.new()
	_make(big, 1.8)
	var dips := 0
	while absf(big.amount - SagoStep.TARGET) > 0.1 and dips < 20:
		_dip(big, SAGO, CUP)
		dips += 1
	_check("a P50 cup takes more dips than a P20", dips > 3, "dips=%d" % dips)


# --- arnibal ---------------------------------------------------------------

func _arnibal(holds: Array) -> ArnibalStep:
	var step := ArnibalStep.new()
	_make(step)
	for hold in holds:
		_dip(step, ARNIBAL, CUP, hold)
		_run(step, 180)
	_hand_over(step)
	return step


func _test_arnibal() -> void:
	print("arnibal — judging the load")
	var full := int(ArnibalStep.FILL_TIME / DT) + 5
	var right := _arnibal([full, full])   # two full dippers is a P20 cup
	var heavy := _arnibal([full, full, full])
	var light := _arnibal([full / 3])
	_check("settles when the cup goes over", right.complete)
	_check("two full dippers scores well", right.score > 0.85, "score=%.3f" % right.score)
	_check("a third one is too sweet", heavy.score < right.score - 0.3,
		"heavy=%.3f right=%.3f" % [heavy.score, right.score])
	_check("a short dip is not enough", light.score < right.score - 0.3,
		"light=%.3f right=%.3f" % [light.score, right.score])

	# Thick syrup keeps running after the tip.
	var step := ArnibalStep.new()
	_make(step)
	step.pointer_down(ARNIBAL)
	_run(step, full)
	_check("holding it down fills the dipper", step.dipper > 0.95, "dipper=%.2f" % step.dipper)
	step.pointer_move(CUP, Vector2.ZERO)
	step.pointer_up(CUP)
	step.update(DT)
	var just_after := step.level
	_run(step, 60)
	_check("the syrup is still running after the tip", step.level > just_after + 0.1,
		"after 1 frame=%.3f after 1s=%.3f" % [just_after, step.level])

	var missed := ArnibalStep.new()
	_make(missed)
	_dip(missed, ARNIBAL, STREET, full)
	_run(missed, 120)
	_check("tipped on the street, none reaches the cup", is_zero_approx(missed.level))


# --- swirl -----------------------------------------------------------------

func _swirl(steps_of_angle: int) -> SwirlStep:
	var step := SwirlStep.new()
	_make(step)
	var angle := 0.0
	step.pointer_down(CUP + Vector2(100, 0))
	for i in steps_of_angle:
		angle += 0.2
		step.pointer_move(CUP + Vector2(cos(angle), sin(angle)) * 100.0, Vector2.ZERO)
	step.pointer_up(Vector2.ZERO)
	_run(step, 120)
	_hand_over(step)
	return step


func _test_swirl_sweet_spot() -> void:
	print("swirl — the skill is stopping")
	var just_right := _swirl(61)
	var overdone := _swirl(140)
	_check("settles when the cup goes over", just_right.complete)
	_check("marbled scores well", just_right.score > 0.85, "score=%.3f" % just_right.score)
	_check("over-mixed scores worse", overdone.score < just_right.score - 0.3,
		"over=%.3f right=%.3f" % [overdone.score, just_right.score])

	var idle := SwirlStep.new()
	_make(idle)
	idle.pointer_down(CUP + Vector2(100, 0))
	for i in 61:
		idle.pointer_move(CUP + Vector2(cos(i * 0.2), sin(i * 0.2)) * 100.0, Vector2.ZERO)
	idle.pointer_up(Vector2.ZERO)
	_run(idle, 600)
	_check("it does not finish by itself any more", not idle.complete)


# --- serve -----------------------------------------------------------------

func _test_serve() -> void:
	print("serve — handover")
	var step := ServeStep.new()
	var view := _make(step)
	step.pointer_down(Vector2(400, 300))
	step.pointer_move(Vector2(600, 240), Vector2.ZERO)
	step.pointer_up(Vector2(700, 200))
	_run(step, 60)
	_check("delivers to the customer", view.delivered)
	_check("completes", step.complete)

	var missed := ServeStep.new()
	_make(missed)
	missed.pointer_down(Vector2(400, 300))
	missed.pointer_up(Vector2(100, 600))
	_run(missed, 60)
	_check("dropping it elsewhere does not complete", not missed.complete)


# --- grading ---------------------------------------------------------------

func _test_grading() -> void:
	print("grading")
	var perfect := _scored_steps(1.0)
	var awful := _scored_steps(0.0)
	_check("perfect is 1.0", is_equal_approx(Grading.sarap(perfect), 1.0))
	_check("awful is 0.0", is_zero_approx(Grading.sarap(awful)))
	_check("perfect pays more", Grading.payment(1.0, 20) > Grading.payment(0.0, 20),
		"%d vs %d" % [Grading.payment(1.0, 20), Grading.payment(0.0, 20)])
	_check("a bad cup is still paid its price", Grading.payment(0.0, 50) == 50)
	_check("a P50 cup pays more than a P10", Grading.payment(1.0, 50) > Grading.payment(1.0, 10),
		"%d vs %d" % [Grading.payment(1.0, 50), Grading.payment(1.0, 10)])
	_check("perfect reads SARAP!", Grading.grade_label(1.0) == "SARAP!")


func _scored_steps(value: float) -> Array:
	var steps: Array = [
		CupStep.new(), LidStep.new(), DrainStep.new(), ShaveStep.new(),
		SagoStep.new(), ArnibalStep.new(), SwirlStep.new(), ServeStep.new(),
	]
	for step in steps:
		step.score = value
	return steps


# --- focus -----------------------------------------------------------------

func _test_focus() -> void:
	print("focus — the cups, the lid, then wherever the hand is")
	var order := [CupStep.new().focus, LidStep.new().focus, FreeServe.new().focus]
	_check("cups, then the tofu bucket, then the whole setup",
		order == ["cups", "tofu", "work"], str(order))

	var free := FreeServe.new()
	_make(free)
	free.pointer_down(SAGO)
	_check("holding the dipper in the sago lights the syrup bucket",
		free.working() == "syrup", free.working())
	free.pointer_up(SAGO)
	_check("and letting go lights nothing", free.working() == "")


# --- the free serve --------------------------------------------------------

## A shave trip through the free serve: sweep until the scoop is full, then
## carry it to the cup.
func _free_shave(free: FreeServe) -> void:
	var x := TOFU.x
	var dir := 1.0
	free.pointer_down(TOFU)
	for i in 3000:
		if free.shave.scooped >= ShaveStep.SCOOP_CAP:
			break
		x += 12.0 * dir
		if absf(x - TOFU.x) > 95.0:
			dir = -dir
		free.pointer_move(Vector2(x, TOFU.y), Vector2(12, 0))
	free.pointer_move(TOFU + Vector2(150, 0), Vector2(5, 0))
	free.pointer_move(CUP, Vector2.ZERO)
	free.pointer_up(CUP)
	free.update(DT)


func _test_free_serve() -> void:
	print("free serve — any bucket, any order")
	var free := FreeServe.new()
	var view := _make(free)

	free.pointer_down(TOFU)
	_check("with water on top, the scoop goes in to drain", free._owner == free.drain)
	free.pointer_up(TOFU)
	for i in 10:
		if free.drain.water <= 0.001:
			break
		_scoop(free, free.drain.band() + 0.02, STREET)
	_check("the water can all be thrown out", free.drain.water <= 0.001,
		"water=%.3f" % free.drain.water)

	free.pointer_down(TOFU)
	_check("with the water gone, the same scoop shaves", free._owner == free.shave)
	free.pointer_up(TOFU)

	# Syrup before the tofu is finished, then back for more tofu: the order
	# is the player's.
	_free_shave(free)
	_dip(free, SAGO, CUP)
	_check("the gauge follows the tool last used", free.gauge_name() == "Sago"
		and is_equal_approx(free.gauge(), free.sago.amount), free.gauge_name())
	var before := free.shave.fill
	_free_shave(free)
	_check("tofu can still go in after the sago", free.shave.fill > before,
		"before=%.2f after=%.2f" % [before, free.shave.fill])
	_check("and the sago is still there", free.sago.amount > 0.0)

	# A press in the cup is a stir; pulled out of it, the cup comes too.
	free.pointer_down(CUP + Vector2(20, 0))
	_check("a press in the cup stirs", free._owner == free.swirl)
	free.pointer_move(CUP + Vector2(30, 20), Vector2.ZERO)
	free.pointer_move(Vector2(600, 240), Vector2.ZERO)
	_check("pulling out of the cup picks it up", free._owner == free.serve)
	free.pointer_up(Vector2(700, 200))
	free.update(DT)
	_check("handing it to the customer ends the order", free.complete and view.delivered)

	var judged := free.scored()
	_check("every tool is judged when the cup goes over", judged.size() == 6)
	_check("the customer names what was wrong",
		Grading.reaction(Grading.sarap(judged), judged) == "\"Matabang po.\"",
		Grading.reaction(Grading.sarap(judged), judged))

	var dry := FreeServe.new()
	_make(dry)
	dry.pointer_down(CUP)
	dry.pointer_move(Vector2(700, 200), Vector2.ZERO)
	dry.pointer_up(Vector2(700, 200))
	dry.update(DT)
	var empty := dry.scored()
	_check("an empty cup can be handed over, and it is graded as one",
		dry.complete and Grading.sarap(empty) < 0.35,
		"sarap=%.2f" % Grading.sarap(empty))


# --- lid -------------------------------------------------------------------

## Drag upward by `radii` bucket radii, in one go.
func _lift(step: LidStep, radii: float) -> void:
	step.pointer_down(Vector2(200, 240))
	# The stub reports a 100px bucket radius, and up the screen is -y.
	step.pointer_move(Vector2(200, 240 - radii * 100.0), Vector2(0, -radii * 100.0))
	step.pointer_up(Vector2(200, 240 - radii * 100.0))


func _test_lid() -> void:
	print("lid — opening the bucket")

	var step := LidStep.new()
	var view := _make(step)
	_check("starts shut", is_equal_approx(view.lid_open, 0.0))

	_lift(step, 0.5)
	step.update(DT)
	_check("a short pull only cracks it open",
		view.lid_open > 0.0 and view.lid_open < 1.0, "open=%.2f" % view.lid_open)
	_check("and does not finish the step", step.complete == false)

	_lift(step, 2.0)
	step.update(DT)
	_check("pulling it the rest of the way opens it",
		is_equal_approx(view.lid_open, 1.0), "open=%.2f" % view.lid_open)
	_check("which completes the step", step.complete)
	_check("and lets the steam out", view.lid_steaming)

	# Dragging the other way is not how you lift a lid.
	var down := LidStep.new()
	var down_view := _make(down)
	down.pointer_down(Vector2(200, 200))
	down.pointer_move(Vector2(200, 400), Vector2(0, 200))
	down.update(DT)
	_check("dragging downward does nothing",
		is_equal_approx(down_view.lid_open, 0.0), "open=%.2f" % down_view.lid_open)

	_check("opening the lid is not graded",
		Grading.WEIGHTS.get("Open the bucket", 1.0) == 0.0)


# --- the tofu itself -------------------------------------------------------

## One full pass of the blade across the bucket, left wall to right wall.
func _pass(surface: TofuSurface) -> float:
	var taken := 0.0
	var steps := 40
	for i in steps + 1:
		var u := lerpf(-1.0, 1.0, float(i) / float(steps))
		taken += surface.carve(u, 2.0 / float(steps))
	return taken


func _test_tofu_surface() -> void:
	print("tofu — a surface, not a number")

	var fresh := TofuSurface.new()
	_check("a full bucket is full", is_equal_approx(fresh.remaining(), 1.0))
	_check("and level", is_equal_approx(fresh.levelness(), 1.0))

	var first := _pass(fresh)
	_check("a pass lifts tofu", first > 0.0, "took=%.3f" % first)
	_check("and takes it off the whole width",
		fresh.remaining() < 1.0 and fresh.levelness() > 0.9,
		"left=%.3f level=%.2f" % [fresh.remaining(), fresh.levelness()])

	var second := _pass(fresh)
	_check("a second pass lifts about as much again",
		absf(second - first) < first * 0.35, "first=%.3f second=%.3f" % [first, second])

	# The rule that makes the bucket a place rather than a meter: a flat blade
	# rides the high points, so it cannot dig a well in one spot.
	var ground := TofuSurface.new()
	var ground_take := 0.0
	for i in 400:
		ground_take += ground.carve(0.0, 0.05)
	_check("grinding one spot stops paying", ground_take < first,
		"ground=%.3f one sweep=%.3f" % [ground_take, first])
	_check("and most of the bucket is untouched",
		ground.remaining() > 0.85, "left=%.3f" % ground.remaining())

	# Gouging is the opposite case: draining too deep *should* leave a dent.
	var dug := TofuSurface.new()
	dug.gouge(0.0, 0.3)
	_check("a gouge leaves a dent", dug.levelness() < 0.9,
		"level=%.2f" % dug.levelness())

	# An empty bucket has nothing left to give.
	var empty := TofuSurface.new()
	for p in 90:
		_pass(empty)
	_check("a bucket can be emptied", empty.remaining() < 0.05,
		"left=%.3f" % empty.remaining())
	_check("and then gives nothing", is_equal_approx(empty.carve(0.0, 1.0), 0.0))

	# The block and the inventory have to be the same bucket.
	var part := TofuSurface.new()
	part.set_level(0.5)
	_check("a half-used load is a half-full block",
		is_equal_approx(part.remaining(), 0.5), "left=%.3f" % part.remaining())
	var cups := 0.0
	for p in 400:
		cups += _pass(part)
	_check("and half a load is about six P20 cups",
		absf(cups / TofuSurface.PER_CUP - 6.0) < 1.0,
		"cups=%.1f" % (cups / TofuSurface.PER_CUP))

	var load := TofuSurface.new()
	var whole := 0.0
	for p in 400:
		whole += _pass(load)
	_check("a full load is about twelve P20 cups, which is what LOAD_SIZE says",
		absf(whole / TofuSurface.PER_CUP - 12.0) < 1.0,
		"cups=%.1f" % (whole / TofuSurface.PER_CUP))


# --- the last cup of a load ------------------------------------------------

func _test_shave_runs_dry() -> void:
	print("shave — scraping out the last of it")

	var step := ShaveStep.new()
	var view := _make(step)
	# A tenth of a load: not enough for a whole cup.
	view.block.set_level(0.04)
	for trip in 10:
		if view.block.remaining() <= 0.002:
			break
		_sweep(step, [12.0], 3000)
		_carry(step, CUP)
	_hand_over(step)

	_check("the step can still be finished", step.complete)
	_check("but the cup is short", step.fill < ShaveStep.FULL, "fill=%.2f" % step.fill)
	_check("the bucket is scraped out", view.block.remaining() < 0.01,
		"left=%.4f" % view.block.remaining())
	_check("and a short cup scores worse than a full one", step.score < 0.8,
		"score=%.3f" % step.score)
