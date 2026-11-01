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
	_test_drain_clean()
	_test_drain_spilled()
	_test_shave_smooth_beats_jerky()
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


# --- drain -----------------------------------------------------------------

func _drain_with_tilt(drag_pixels: float) -> DrainStep:
	var step := DrainStep.new()
	var view := _make(step)
	step.pointer_down(Vector2(400, 500))
	step.pointer_move(Vector2(400, 500 - drag_pixels), Vector2(0, -drag_pixels))
	# Hold the tilt while it pours.
	for i in 900:
		step.update(DT)
		if view.water <= 0.0:
			break
	step.pointer_up(Vector2.ZERO)
	_run_until_done(step, 300)
	return step


func _test_drain_clean() -> void:
	print("drain — careful tilt")
	var step := _drain_with_tilt(156.0)  # ~25 degrees, below the spill angle
	_check("completes", step.complete)
	_check("no tofu lost", is_zero_approx(step.tofu_lost), "lost=%.4f" % step.tofu_lost)
	_check("scores near perfect", step.score > 0.95, "score=%.3f" % step.score)


func _test_drain_spilled() -> void:
	print("drain — reckless tilt")
	var clean := _drain_with_tilt(156.0)
	var messy := _drain_with_tilt(290.0)  # past the spill angle
	_check("completes", messy.complete)
	_check("loses tofu", messy.tofu_lost > 0.0, "lost=%.4f" % messy.tofu_lost)
	_check("scores worse than careful", messy.score < clean.score,
		"messy=%.3f clean=%.3f" % [messy.score, clean.score])


# --- shave -----------------------------------------------------------------

func _shave(speeds: Array) -> ShaveStep:
	var step := ShaveStep.new()
	_make(step)
	step.pointer_down(Vector2(400, 400))
	var i := 0
	while step.fill < 1.0 and i < 4000:
		var dx: float = speeds[i % speeds.size()]
		step.pointer_move(Vector2(400, 400), Vector2(dx, 0))
		i += 1
	step.pointer_up(Vector2.ZERO)
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
		DrainStep.new(), ShaveStep.new(), SagoStep.new(),
		ArnibalStep.new(), SwirlStep.new(), ServeStep.new(),
	]
	for step in steps:
		step.score = value
	return steps
