extends Node3D

## The neighbourhood Lolo Ben works.
##
## Built in code rather than in a .tscn on purpose. The whole town is boxes,
## and a hand-written .tscn full of Transform3D literals is exactly where this
## project has already lost an afternoon: Godot writes a basis **row by row**,
## so a transform typed as columns silently inverts. Setting `position` and
## `rotation_degrees` here cannot go wrong that way, and the layout stays
## readable as data.
##
## Everything shares a handful of materials and box meshes so the street stays
## inside the draw-call budget in section 7 of the plan.

## Half-width of the roadway. The pavement starts here.
const ROAD_HALF := 5.0
const EDGE := 62.0

## Facade colours. Washed-out pastel over bare concrete is what the street
## actually looks like; saturation here would read as a cartoon.
const FACADES := [
	Color(0.82, 0.76, 0.64), Color(0.70, 0.74, 0.70), Color(0.86, 0.72, 0.60),
	Color(0.74, 0.70, 0.76), Color(0.80, 0.80, 0.74), Color(0.66, 0.72, 0.78),
	Color(0.88, 0.80, 0.66), Color(0.72, 0.66, 0.60),
]

const AWNINGS := [
	Color(0.78, 0.24, 0.20), Color(0.20, 0.42, 0.66),
	Color(0.90, 0.68, 0.18), Color(0.22, 0.54, 0.36),
]

## Where a customer may stand: on the pavement, already facing the road.
var customer_spots: Array[Transform3D] = []

## Doorstep of Lolo Ben's house — the refill point, and where the day starts.
## Deliberately a few steps off the cross street rather than deep in a block:
## the first thing the player sees has to be the town, not a back wall.
var home_position := Vector3(-9.0, 0.0, 26.0)
var player_start := Vector3(-6.8, 0.0, 26.0)

var _mats := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20261103
	_build_sky()
	_build_ground()
	_build_roads()
	_build_blocks()
	_build_court()
	_build_home()
	_build_props()
	_build_bounds()
	_build_customer_spots()


# --- lighting and sky ------------------------------------------------------

func _build_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.52, 0.76)
	sky_mat.sky_horizon_color = Color(0.95, 0.74, 0.52)
	sky_mat.ground_horizon_color = Color(0.86, 0.68, 0.50)
	sky_mat.ground_bottom_color = Color(0.42, 0.36, 0.32)
	sky_mat.sun_angle_max = 24.0

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.38
	# Late afternoon haze. A cheap depth cue, and it hides the world's edge.
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.68, 0.55)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# One directional light, one shadow map — the whole lighting budget.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-34.0, 118.0, 0.0)
	sun.light_color = Color(1.0, 0.89, 0.74)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


# --- surfaces --------------------------------------------------------------

func _build_ground() -> void:
	_slab("Ground", Vector3(0, -0.1, 0), Vector3(EDGE * 2.2, 0.2, EDGE * 2.2),
		Color(0.44, 0.42, 0.37), true)


func _build_roads() -> void:
	var road := Color(0.26, 0.25, 0.26)
	_slab("RoadMain", Vector3(0, 0.005, 0), Vector3(EDGE * 2.2, 0.02, ROAD_HALF * 2.0),
		road, false)
	_slab("RoadCross", Vector3(0, 0.01, 0), Vector3(ROAD_HALF * 2.0, 0.02, EDGE * 2.2),
		road, false)

	# Centre dashes on the main street only.
	for i in 24:
		var x := -57.0 + i * 5.0
		if absf(x) < ROAD_HALF + 1.0:
			continue
		_slab("Dash%d" % i, Vector3(x, 0.02, 0), Vector3(2.2, 0.02, 0.22),
			Color(0.86, 0.82, 0.55), false)

	# Pavement, with a kerb lip that also keeps the player off the edge.
	for side in [-1.0, 1.0]:
		_slab("WalkH%d" % int(side), Vector3(0, 0.06, side * (ROAD_HALF + 1.8)),
			Vector3(EDGE * 2.2, 0.12, 3.0), Color(0.60, 0.58, 0.53), false)
		_slab("WalkV%d" % int(side), Vector3(side * (ROAD_HALF + 1.8), 0.07, 0),
			Vector3(3.0, 0.12, EDGE * 2.2), Color(0.60, 0.58, 0.53), false)
		_slab("KerbH%d" % int(side), Vector3(0, 0.08, side * (ROAD_HALF + 0.2)),
			Vector3(EDGE * 2.2, 0.16, 0.3), Color(0.72, 0.70, 0.64), false)
		_slab("KerbV%d" % int(side), Vector3(side * (ROAD_HALF + 0.2), 0.09, 0),
			Vector3(0.3, 0.16, EDGE * 2.2), Color(0.72, 0.70, 0.64), false)


# --- buildings -------------------------------------------------------------

## One row of lots per side of each road, with alley gaps left in.
func _build_blocks() -> void:
	var front := ROAD_HALF + 3.4

	# Along the main street, shop fronts face north or south.
	for sz in [-1.0, 1.0]:
		var x := -52.0
		var i := 0
		while x < 52.0:
			var w := _rng.randf_range(6.0, 11.0)
			if absf(x + w * 0.5) < ROAD_HALF + 6.0:
				x += w + 1.0  # keep the junction clear
				continue
			if _rng.randf() < 0.18:
				x += _rng.randf_range(4.0, 7.0)  # alley
				continue
			_lot("MainB%d_%d" % [int(sz), i], Vector3(x + w * 0.5, 0.0, sz * front),
				w, _rng.randf_range(3.2, 8.5), _rng.randf_range(7.0, 11.0), sz < 0.0)
			x += w + _rng.randf_range(0.4, 1.4)
			i += 1

	# Along the cross street they face east or west. Rotating the lot is the
	# only difference, so the same builder does both.
	for sx in [-1.0, 1.0]:
		var z := -46.0
		var i := 0
		while z < 46.0:
			var w := _rng.randf_range(6.0, 10.0)
			# The south-west quadrant is left open for the house.
			if absf(z + w * 0.5) < ROAD_HALF + 6.0 or (sx < 0.0 and z > 13.0):
				z += w + 1.0
				continue
			if _rng.randf() < 0.22:
				z += _rng.randf_range(4.0, 8.0)
				continue
			_lot("CrossB%d_%d" % [int(sx), i], Vector3(sx * front, 0.0, z + w * 0.5),
				w, _rng.randf_range(3.0, 7.5), _rng.randf_range(7.0, 10.0),
				sx > 0.0, true)
			z += w + _rng.randf_range(0.5, 1.6)
			i += 1


## One building plus its awning and shuttered ground floor. `width` runs along
## the street, `depth` away from it; `flip` turns the shop front to face the
## other side of the road, and `sideways` swaps the two axes for the cross
## street.
func _lot(lot_name: String, at: Vector3, width: float, height: float, depth: float,
		flip: bool, sideways := false) -> void:
	var facade: Color = FACADES[_rng.randi() % FACADES.size()]
	var face_sign := -1.0 if flip else 1.0

	var size := Vector3(width, height, depth)
	var centre := at
	if sideways:
		size = Vector3(depth, height, width)
		centre += Vector3(face_sign * depth * 0.5, height * 0.5, 0.0)
	else:
		centre += Vector3(0.0, height * 0.5, face_sign * depth * 0.5)

	_slab(lot_name, centre, size, facade, true)

	# A darker ground-floor band, so a 7m box reads as a building with a shop
	# in it rather than as a crate.
	_slab(lot_name + "Base", Vector3(centre.x, 1.2, centre.z),
		Vector3(size.x * 0.99, 2.4, size.z * 0.99), facade.darkened(0.28), false)

	# Awning over the doorway, on the street-facing side.
	var awn: Color = AWNINGS[_rng.randi() % AWNINGS.size()]
	var out := 1.5
	if sideways:
		_slab(lot_name + "Awn",
			Vector3(centre.x - face_sign * (size.x * 0.5 + out * 0.5), 2.7, centre.z),
			Vector3(out, 0.12, width * 0.8), awn, false)
	else:
		_slab(lot_name + "Awn",
			Vector3(centre.x, 2.7, centre.z - face_sign * (size.z * 0.5 + out * 0.5)),
			Vector3(width * 0.8, 0.12, out), awn, false)


func _build_court() -> void:
	# The barangay court, in the open lot behind the north-east block.
	var c := Vector3(28.0, 0.0, -30.0)
	_slab("Court", c + Vector3(0, 0.03, 0), Vector3(17.0, 0.06, 26.0),
		Color(0.34, 0.40, 0.46), false)
	for z in [-8.0, 0.0, 8.0]:
		_slab("CourtLine%d" % int(z), c + Vector3(0, 0.05, z),
			Vector3(16.0, 0.06, 0.18), Color(0.92, 0.92, 0.88), false)

	for sz in [-1.0, 1.0]:
		var base := c + Vector3(0, 0, sz * 12.0)
		_slab("HoopPost%d" % int(sz), base + Vector3(0, 1.7, 0),
			Vector3(0.22, 3.4, 0.22), Color(0.30, 0.30, 0.32), true)
		_slab("HoopBoard%d" % int(sz), base + Vector3(0, 3.3, -sz * 0.6),
			Vector3(1.6, 1.0, 0.1), Color(0.90, 0.90, 0.86), false)


func _build_home() -> void:
	# Lolo Ben's house: deliberately the smallest building in town, and the
	# only one with a warm light on the porch.
	var h := home_position + Vector3(-5.0, 0.0, 0.0)
	_slab("Home", h + Vector3(0, 1.6, 0), Vector3(7.0, 3.2, 7.0),
		Color(0.78, 0.66, 0.50), true)
	_slab("HomeRoof", h + Vector3(0, 3.35, 0), Vector3(7.8, 0.3, 7.8),
		Color(0.48, 0.30, 0.22), false)
	_slab("HomePorch", home_position + Vector3(0, 0.08, 0), Vector3(3.6, 0.16, 2.8),
		Color(0.58, 0.52, 0.44), false)
	# Door on the east face, so it looks out at the street.
	_slab("HomeDoor", h + Vector3(3.52, 1.05, 0.0), Vector3(0.08, 2.1, 1.0),
		Color(0.34, 0.22, 0.16), false)

	var lamp := OmniLight3D.new()
	lamp.name = "PorchLight"
	lamp.position = home_position + Vector3(0, 2.6, 0.2)
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	add_child(lamp)

	# The refill trigger: the player only needs to stand on the porch.
	var area := Area3D.new()
	area.name = "HomeArea"
	area.position = home_position + Vector3(0, 1.5, 0)
	area.collision_layer = 0
	area.collision_mask = 2  # the player's layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 4.5)
	shape.shape = box
	area.add_child(shape)
	add_child(area)


func _build_props() -> void:
	# Lamp posts down both pavements, as one multimesh: dozens of identical
	# poles for the price of one draw call.
	var pole := BoxMesh.new()
	pole.size = Vector3(0.18, 5.0, 0.18)
	pole.material = _material(Color(0.32, 0.31, 0.30))

	# Set at the back of the pavement rather than on the kerb. A pole on the
	# kerb lands between the follow camera and the player constantly, which
	# is worse than it is authentic.
	var back := ROAD_HALF + 2.9
	var spots: Array[Vector3] = []
	for i in 11:
		var x := -50.0 + i * 10.0
		if absf(x) < ROAD_HALF + 3.0:
			continue
		spots.append(Vector3(x, 2.5, -back))
		spots.append(Vector3(x, 2.5, back))
	for i in 9:
		var z := -40.0 + i * 10.0
		if absf(z) < ROAD_HALF + 3.0:
			continue
		spots.append(Vector3(-back, 2.5, z))
		spots.append(Vector3(back, 2.5, z))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pole
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LampPosts"
	mmi.multimesh = mm
	add_child(mmi)

	# A few parked jeepneys along the kerb. Three boxes each is enough for the
	# silhouette at the distance the camera keeps.
	_jeepney(Vector3(-18.0, 0.0, -ROAD_HALF + 1.4), 0.0, Color(0.84, 0.26, 0.20))
	_jeepney(Vector3(14.0, 0.0, ROAD_HALF - 1.4), 180.0, Color(0.22, 0.46, 0.70))
	_jeepney(Vector3(-ROAD_HALF + 1.4, 0.0, 42.0), 90.0, Color(0.92, 0.72, 0.22))


func _jeepney(at: Vector3, yaw: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = "Jeepney"
	body.position = at
	body.rotation_degrees = Vector3(0, yaw, 0)
	add_child(body)

	_child_box(body, Vector3(0, 0.8, 0), Vector3(2.1, 1.1, 5.4), color, true)
	_child_box(body, Vector3(0, 1.5, -1.1), Vector3(1.9, 0.9, 2.6), color.lightened(0.12), false)
	_child_box(body, Vector3(0, 1.75, 1.2), Vector3(2.2, 0.12, 3.2), Color(0.86, 0.86, 0.82), false)


## Invisible walls at the town's edge. Cheaper and more reliable than making
## the ground big enough that nobody walks off it.
func _build_bounds() -> void:
	for spec in [
		[Vector3(0, 6, -EDGE), Vector3(EDGE * 2.0, 12.0, 1.0)],
		[Vector3(0, 6, EDGE), Vector3(EDGE * 2.0, 12.0, 1.0)],
		[Vector3(-EDGE, 6, 0), Vector3(1.0, 12.0, EDGE * 2.0)],
		[Vector3(EDGE, 6, 0), Vector3(1.0, 12.0, EDGE * 2.0)],
	]:
		var body := StaticBody3D.new()
		body.name = "Bound"
		body.position = spec[0]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		body.add_child(shape)
		add_child(body)


## Pavement positions a customer can wait at, each already facing the road, so
## the spawner only has to pick one.
func _build_customer_spots() -> void:
	var specs := [
		[Vector3(-30.0, 0.0, -(ROAD_HALF + 2.0)), 180.0],
		[Vector3(-12.0, 0.0, ROAD_HALF + 2.0), 0.0],
		[Vector3(16.0, 0.0, -(ROAD_HALF + 2.0)), 180.0],
		[Vector3(34.0, 0.0, ROAD_HALF + 2.0), 0.0],
		[Vector3(ROAD_HALF + 2.0, 0.0, -24.0), 270.0],
		[Vector3(-(ROAD_HALF + 2.0), 0.0, -34.0), 90.0],
		[Vector3(ROAD_HALF + 2.0, 0.0, 22.0), 270.0],
		[Vector3(24.0, 0.0, -19.0), 200.0],
		[Vector3(-40.0, 0.0, ROAD_HALF + 2.0), 0.0],
		[Vector3(44.0, 0.0, -(ROAD_HALF + 2.0)), 180.0],
	]
	for spec in specs:
		var t := Transform3D.IDENTITY.rotated(Vector3.UP, deg_to_rad(spec[1]))
		t.origin = spec[0]
		customer_spots.append(t)


# --- building blocks -------------------------------------------------------

## A box. `solid` gives it collision; decoration (road paint, awnings, bands)
## does not need any, and leaving it out keeps the physics world small.
func _slab(slab_name: String, centre: Vector3, size: Vector3, color: Color, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size

	var mi := MeshInstance3D.new()
	mi.name = slab_name
	mi.mesh = mesh
	mi.material_override = _material(color)

	if not solid:
		mi.position = centre
		add_child(mi)
		return

	var body := StaticBody3D.new()
	body.name = slab_name
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_child(mi)
	add_child(body)


func _child_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = _material(color)
	parent.add_child(mi)
	if not solid:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	parent.add_child(shape)


## Materials are cached by colour, so the hundred-odd boxes in town share a
## couple of dozen materials instead of owning one each.
func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	_mats[key] = mat
	return mat
