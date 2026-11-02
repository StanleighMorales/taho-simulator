extends SceneTree

## Headless tests for the serving steps.
##
##     godot --headless --script res://tests/run_step_tests.gd
##
## Steps never touch nodes directly — they call methods on the view — so a stub
## view is enough to drive every mechanic and assert the scoring. This checks
## the rules; whether the pour *feels* good is a judgement only a human makes.

const DT := 1.0 / 60.0

var _failures := 0
var _checks := 0


class StubView:
	extends RefCounted

	var tilt := 0.0
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
	## The real material model, not a fake. It is a plain RefCounted, so the
	## shave tests can exercise the actual tofu instead of a stand-in.
	var block := TofuSurface.new()

	func bucket_screen_position() -> Vector2:
		return Vector2(200, 200)

	func bucket_screen_extent() -> float:
		return 100.0

	func set_ladle(active: bool, _u: float, _depth: float, _bite := 0.0) -> void:
		ladle_active = active

	func skim_splash() -> void:
		pass

	func set_dipper(_active: bool, _pos: Vector2, _bite := 0.0) -> void:
		pass

	func rest_dipper() -> void:
		pass

	func carve_tofu(u: float, effort: float) -> float:
		return block.carve(u, effort)

	func gouge_tofu(u: float, depth: float) -> void:
		block.gouge(u, depth)

	func tofu_remaining() -> float:
		return block.remaining()

	func set_cup_sheets(count: int) -> void:
		sheets = count

	func set_lid(open: float) -> void:
		lid_open = open

	func lid_opened() -> void:
		lid_steaming = true

	func set_bucket_tilt(v: float) -> void:
		tilt = v

	func set_bucket_water(v: float) -> void:
		water = v

	func spill(_is_losing: bool) -> void:
		pass

	func set_cup_tofu(v: float) -> void:
		tofu = v

	func shave_tick(_fill: float) -> void:
		pass

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
	_test_lid()
	_test_skim_shallow()
	_test_skim_too_deep()
	_test_skim_needs_lifting_out()
	_test_shave_smooth_beats_jerky()
	_test_shave_runs_dry()
	_test_sago_amount()
	_test_arnibal_timing()
	_test_swirl_sweet_spot()
	_test_serve()
	_test_grading()

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


func _run_until_done(step: ServingStep, max_frames: int) -> void:
	for i in max_frames:
		step.update(DT)
		if step.complete:
			return


func _make(step: ServingStep) -> StubView:
	var view := StubView.new()
	step.setup(view)
	step.begin()
	return view


# --- skim ------------------------------------------------------------------

## One scoop: dip to `depth` (in bucket radii), sweep across, lift back out.
func _scoop(step: SkimStep, depth: float) -> void:
	var centre := Vector2(200, 200)
	var e := 100.0
	step.pointer_down(centre + Vector2(-0.8 * e, 0.0))
	step.pointer_move(centre + Vector2(-0.4 * e, depth * e), Vector2.ZERO)
	step.pointer_move(centre + Vector2(0.4 * e, depth * e), Vector2.ZERO)
	step.pointer_up(centre + Vector2(0.8 * e, -0.3 * e))


## Always skim just inside the remaining water, as a careful vendor would.
func _skim_carefully() -> SkimStep:
	var step := SkimStep.new()
	_make(step)
	for i in 8:
		if step.water <= 0.02:
			break
		_scoop(step, maxf(step.band() - 0.12, 0.12))
		step.update(DT)
	_run_until_done(step, 200)
	return step


func _test_skim_shallow() -> void:
	print("skim — careful, inside the water")
	var step := _skim_carefully()
	_check("completes", step.complete)
	_check("bucket ends clean", step.water <= 0.02, "water=%.3f" % step.water)
	_check("takes several scoops", step.scoops >= 2, "scoops=%d" % step.scoops)
	_check("no tofu lifted", is_zero_approx(step.tofu_lost), "lost=%.4f" % step.tofu_lost)
	_check("scores near perfect", step.score > 0.95, "score=%.3f" % step.score)


func _test_skim_too_deep() -> void:
	print("skim — digging into the tofu")
	var careful := _skim_carefully()
	var step := SkimStep.new()
	_make(step)
	for i in 8:
		if step.water <= 0.02:
			break
		_scoop(step, 1.1)  # straight to the bottom every time
		step.update(DT)
	_run_until_done(step, 200)
	_check("completes", step.complete)
	_check("lifts tofu out", step.tofu_lost > 0.0, "lost=%.4f" % step.tofu_lost)
	_check("scores worse than careful", step.score < careful.score - 0.2,
		"deep=%.3f careful=%.3f" % [step.score, careful.score])


func _test_skim_needs_lifting_out() -> void:
	print("skim — releasing without lifting out")
	var step := SkimStep.new()
	_make(step)
	var centre := Vector2(200, 200)
	step.pointer_down(centre + Vector2(-80, 0))
	step.pointer_move(centre + Vector2(0, 40), Vector2.ZERO)
	step.pointer_up(centre + Vector2(40, 40))  # let go still down in the bucket
	_check("no scoop counted", step.scoops == 0)
	_check("water untouched", is_equal_approx(step.water, 1.0), "water=%.3f" % step.water)


# --- shave -----------------------------------------------------------------

## Sweep the blade back and forth across the bucket, taking one `speeds`
## entry per frame. The pointer has to actually travel now: the cup fills
## with what the scoop lifts, and a blade held in one place runs out of tofu
## it is allowed to take almost at once — which is the point of the surface.
func _sweep(step: ShaveStep, speeds: Array, frames: int) -> void:
	var x := 200.0
	var dir := 1.0
	step.pointer_down(Vector2(x, 400))
	var i := 0
	while step.fill < 1.0 and i < frames:
		var dx: float = speeds[i % speeds.size()] * dir
		x += dx
		# The stub puts the bucket centre at x=200 with a 100px radius.
		if x > 295.0:
			x = 295.0
			dir = -1.0
		elif x < 105.0:
			x = 105.0
			dir = 1.0
		step.pointer_move(Vector2(x, 400), Vector2(absf(dx), 0))
		i += 1
	step.pointer_up(Vector2(x, 400))


func _shave(speeds: Array) -> ShaveStep:
	var step := ShaveStep.new()
	_make(step)
	_sweep(step, speeds, 6000)
	_run_until_done(step, 300)
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
	_check("the sweep laid several sheets", smooth.sheets >= 3,
		"sheets=%d" % smooth.sheets)

	# Working one spot is the case the surface exists to rule out. Wiggling
	# back and forth in place, which is what grinding actually looks like —
	# a blade that never travels carves nothing at all, by design.
	var stuck := ShaveStep.new()
	var stuck_view := _make(stuck)
	stuck.pointer_down(Vector2(260, 400))
	for i in 600:
		var x := 260.0 + (8.0 if i % 2 == 0 else -8.0)
		stuck.pointer_move(Vector2(x, 400), Vector2(8, 0))
	_check("grinding one groove cannot fill the cup", stuck.fill < 0.35,
		"fill=%.2f" % stuck.fill)
	_check("and it leaves that groove lower than the rest",
		stuck_view.block.lowest() < stuck_view.block.highest() - 0.01,
		"low=%.3f high=%.3f" % [stuck_view.block.lowest(), stuck_view.block.highest()])


# --- sago ------------------------------------------------------------------

func _sago(taps: int) -> SagoStep:
	var step := SagoStep.new()
	_make(step)
	for i in taps:
		step.pointer_down(Vector2(400, 400))
		step.update(DT)
	_run_until_done(step, 300)
	return step


func _test_sago_amount() -> void:
	print("sago — knowing when to stop")
	var good := _sago(4)   # 4 x ~0.155 lands near the 0.62 target
	var greedy := _sago(9)
	_check("completes after settling", good.complete)
	_check("on-target scores well", good.score > 0.85, "score=%.3f" % good.score)
	_check("overloading scores badly", greedy.score < 0.25, "score=%.3f" % greedy.score)


# --- arnibal ---------------------------------------------------------------

func _arnibal(hold_frames: int) -> ArnibalStep:
	var step := ArnibalStep.new()
	_make(step)
	step.pointer_down(Vector2(400, 400))
	for i in hold_frames:
		step.update(DT)
	step.pointer_up(Vector2.ZERO)
	_run_until_done(step, 600)
	return step


func _test_arnibal_timing() -> void:
	print("arnibal — the drip keeps running")
	var early := _arnibal(83)    # release early, let the drip carry it to target
	var late := _arnibal(150)
	_check("completes", early.complete)
	_check("drip overshoots the release point", early.level > 0.44 * 83 * DT,
		"level=%.3f" % early.level)
	_check("releasing early scores well", early.score > 0.85, "score=%.3f" % early.score)
	_check("holding too long scores worse", late.score < early.score,
		"late=%.3f early=%.3f" % [late.score, early.score])


# --- swirl -----------------------------------------------------------------

func _swirl(steps_of_angle: int) -> SwirlStep:
	var step := SwirlStep.new()
	_make(step)
	var centre := Vector2(400, 300)
	var angle := 0.0
	step.pointer_down(centre + Vector2(100, 0))
	for i in steps_of_angle:
		angle += 0.2
		step.pointer_move(centre + Vector2(cos(angle), sin(angle)) * 100.0, Vector2.ZERO)
	step.pointer_up(Vector2.ZERO)
	_run_until_done(step, 300)
	return step


func _test_swirl_sweet_spot() -> void:
	print("swirl — the skill is stopping")
	var just_right := _swirl(61)
	var overdone := _swirl(140)
	_check("completes", just_right.complete)
	_check("marbled scores well", just_right.score > 0.85, "score=%.3f" % just_right.score)
	_check("over-mixed scores worse", overdone.score < just_right.score - 0.3,
		"over=%.3f right=%.3f" % [overdone.score, just_right.score])


# --- serve -----------------------------------------------------------------

func _test_serve() -> void:
	print("serve — handover")
	var step := ServeStep.new()
	var view := _make(step)
	step.pointer_down(Vector2(400, 300))
	step.pointer_move(Vector2(600, 240), Vector2.ZERO)
	step.pointer_up(Vector2(700, 200))
	_run_until_done(step, 60)
	_check("delivers to the customer", view.delivered)
	_check("completes", step.complete)

	var missed := ServeStep.new()
	_make(missed)
	missed.pointer_down(Vector2(400, 300))
	missed.pointer_up(Vector2(100, 600))
	_run_until_done(missed, 60)
	_check("dropping it elsewhere does not complete", not missed.complete)


# --- grading ---------------------------------------------------------------

func _test_grading() -> void:
	print("grading")
	var perfect := _scored_steps(1.0)
	var awful := _scored_steps(0.0)
	_check("perfect is 1.0", is_equal_approx(Grading.sarap(perfect), 1.0))
	_check("awful is 0.0", is_zero_approx(Grading.sarap(awful)))
	_check("perfect pays more", Grading.payment(1.0) > Grading.payment(0.0),
		"%d vs %d" % [Grading.payment(1.0), Grading.payment(0.0)])
	_check("perfect reads SARAP!", Grading.grade_label(1.0) == "SARAP!")


func _scored_steps(value: float) -> Array:
	var steps: Array = [
		SkimStep.new(), ShaveStep.new(), SagoStep.new(),
		ArnibalStep.new(), SwirlStep.new(), ServeStep.new(),
	]
	for step in steps:
		step.score = value
	return steps


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
	_check("so sweeping the bucket beats working a groove",
		first > ground_take, "sweep=%.3f groove=%.3f" % [first, ground_take])

	# Gouging is the opposite case: step 1 digging in *should* leave a dent.
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
	_check("and half a load is about six cups",
		absf(cups / TofuSurface.PER_CUP - 6.0) < 1.0,
		"cups=%.1f" % (cups / TofuSurface.PER_CUP))

	var load := TofuSurface.new()
	var whole := 0.0
	for p in 400:
		whole += _pass(load)
	_check("a full load is about twelve cups, which is what LOAD_SIZE says",
		absf(whole / TofuSurface.PER_CUP - 12.0) < 1.0,
		"cups=%.1f" % (whole / TofuSurface.PER_CUP))


# --- the last cup of a load ------------------------------------------------

func _test_shave_runs_dry() -> void:
	print("shave — scraping out the last of it")

	var step := ShaveStep.new()
	var view := _make(step)
	# A tenth of a load: not enough for a whole cup.
	view.block.set_level(0.04)
	_sweep(step, [12.0], 6000)
	_run_until_done(step, 300)

	_check("the step still finishes", step.complete)
	_check("but the cup is short", step.fill < 1.0, "fill=%.2f" % step.fill)
	_check("the bucket is scraped out", view.block.remaining() < 0.01,
		"left=%.4f" % view.block.remaining())
	_check("and a short cup scores worse than a full one", step.score < 0.8,
		"score=%.3f" % step.score)
