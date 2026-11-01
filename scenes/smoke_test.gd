extends Node3D

## M0 smoke test.
##
## Proves the web export pipeline works end to end, and doubles as a probe for
## the two things the real game depends on: the Compatibility renderer, and
## pointer input that behaves identically under mouse and touch.
##
## Drag anywhere to spin the cube. On touch devices Godot emulates mouse events
## from touch (input_devices/pointing/emulate_mouse_from_touch), so handling the
## mouse events alone covers phones too.

const SPIN_SPEED := 1.2
const DRAG_SENSITIVITY := 0.01
const DRAG_DECAY := 3.0

var _dragging := false
var _drag_velocity := 0.0
var _pointer := Vector2.ZERO
var _drag_count := 0

@onready var _cube: MeshInstance3D = $Cube
@onready var _info: Label = $UI/Info


func _ready() -> void:
	_info.text = _build_report()
	print(_build_report())


func _process(delta: float) -> void:
	_cube.rotate_y(SPIN_SPEED * delta + _drag_velocity)
	_drag_velocity = move_toward(_drag_velocity, 0.0, DRAG_DECAY * delta * absf(_drag_velocity))
	_info.text = "%s\nfps: %d\npointer: %d, %d   drags: %d   held: %s" % [
		_build_report(),
		Engine.get_frames_per_second(),
		_pointer.x, _pointer.y, _drag_count, _dragging,
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_pointer = event.position
		if event.pressed:
			_drag_count += 1
	elif event is InputEventMouseMotion:
		_pointer = event.position
		if _dragging:
			_drag_velocity = -event.relative.x * DRAG_SENSITIVITY


func _build_report() -> String:
	var lines := [
		"TAHO SIMULATOR — M0 pipeline test",
		"drag to spin the cube",
		"",
		"godot: %s" % Engine.get_version_info().string,
		"renderer: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"adapter: %s" % RenderingServer.get_video_adapter_name(),
		"platform: %s" % OS.get_name(),
		"web: %s   threads: %s" % [OS.has_feature("web"), OS.has_feature("threads")],
	]
	return "\n".join(lines)
