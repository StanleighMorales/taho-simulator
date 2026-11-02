extends Node3D

## Someone on the pavement who wants taho.
##
## Built in code like the rest of the placeholder art. A customer is a
## silhouette, a shout, and a radius: walk into the radius and the serving
## view takes over. The customer *types* are a table here for now; section 7
## of the plan wants them as `Resource` files, which is the right move once
## they carry more than a name and a line.

signal wants_service(customer: Node3D)

const RADIUS := 3.2

## name, shirt colour, height scale, the line they call you with.
const TYPES := [
	["Tita", Color(0.86, 0.52, 0.58), 1.0, "Taho! Konti lang ang asukal, ha?"],
	["Bata", Color(0.96, 0.82, 0.36), 0.74, "Kuya, taho! May barya ako!"],
	["Drayber", Color(0.32, 0.46, 0.68), 1.02, "Isa nga, bilisan mo, green na!"],
	["Guard", Color(0.38, 0.42, 0.40), 1.06, "Lolo! Dito muna, kain tayo."],
	["Estudyante", Color(0.52, 0.66, 0.54), 0.96, "Taho po — pwede GCash?"],
	["Tatay", Color(0.70, 0.56, 0.42), 1.04, "Dalawa, para sa anak ko."],
]

var type_name := ""
var line := ""

var _served := false
var _player_inside := false
var _shout_t := 0.0
var _area: Area3D


func _ready() -> void:
	var spec: Array = TYPES[randi() % TYPES.size()]
	type_name = spec[0]
	line = spec[3]
	_area = _build_body(spec[1], spec[2])
	_build_shout()

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _served:
		return
	# The shout bobs and the call-out sways, so a waiting customer is visible
	# from down the street without a minimap.
	_shout_t += delta
	var shout: Node3D = $Shout
	shout.position.y = 2.25 + sin(_shout_t * 2.6) * 0.09
	shout.rotation_degrees.z = sin(_shout_t * 1.7) * 5.0


func player_in_range() -> bool:
	return _player_inside and not _served


func is_waiting() -> bool:
	return not _served


## Called once the order is handed over: the customer stops asking and walks
## off, so the spawner can reuse the spot.
func mark_served() -> void:
	_served = true
	$Shout.visible = false
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position",
		position + global_transform.basis.z * -7.0, 3.0)
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 3.0).set_delay(2.2)
	tween.chain().tween_callback(queue_free)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	if not _served:
		wants_service.emit(self)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false


# --- the silhouette --------------------------------------------------------

## Returns the proximity area, which the caller connects.
func _build_body(shirt: Color, height: float) -> Area3D:
	var rig := Node3D.new()
	rig.name = "Rig"
	rig.scale = Vector3(1.0, height, 1.0)
	add_child(rig)

	var torso := CapsuleMesh.new()
	torso.radius = 0.2
	torso.height = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = torso
	mi.position = Vector3(0, 0.62, 0)
	mi.material_override = _flat(shirt)
	rig.add_child(mi)

	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	head.radial_segments = 10
	head.rings = 6
	var hmi := MeshInstance3D.new()
	hmi.mesh = head
	hmi.position = Vector3(0, 1.3, 0)
	hmi.material_override = _flat(Color(0.74, 0.58, 0.44))
	rig.add_child(hmi)

	var legs := BoxMesh.new()
	legs.size = Vector3(0.3, 0.3, 0.22)
	var lmi := MeshInstance3D.new()
	lmi.mesh = legs
	lmi.position = Vector3(0, 0.15, 0)
	lmi.material_override = _flat(Color(0.30, 0.32, 0.36))
	rig.add_child(lmi)

	var area := Area3D.new()
	area.name = "Area3D"
	# Own layer, so the camera arm and the tap-to-walk ray ignore customers.
	area.collision_layer = 4
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	shape.position = Vector3(0, 1.0, 0)
	area.add_child(shape)
	add_child(area)
	return area


func _build_shout() -> void:
	var shout := Node3D.new()
	shout.name = "Shout"
	shout.position = Vector3(0, 2.25, 0)
	add_child(shout)

	var label := Label3D.new()
	label.text = "Taho po!"
	label.font_size = 64
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.95, 0.72)
	# Keep the outline thin. Past roughly a tenth of the font size it stops
	# being a rim and fills the glyph box into a solid plate.
	label.outline_size = 6
	label.outline_modulate = Color(0.1, 0.08, 0.06, 0.9)
	# Readable through a jeepney, which matters more here than being correct.
	label.no_depth_test = true
	label.render_priority = 2
	shout.add_child(label)


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat
