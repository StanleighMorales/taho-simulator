extends Node3D

## The neighbourhood Lolo Ben works.
##
## Laid out as a map of 10 m tiles (`MAP`), one letter a tile, and built from
## Kenney's City Kit (CC0, in assets/kenney/city). Reading the map is reading
## the town: two streets cross in the middle, a ring road goes round them, and
## every building turns to face whichever road it is next to. Road tiles work
## out their own piece -- straight, corner, junction -- from which of their
## neighbours are road too, so the map never has to say. Kenney trucks
## (`Car`) drive loops of it, and they do not stop for pedestrians.
##
## Every tile of one kind is a single MultiMesh, and the whole kit shares one
## colour-map texture, so the town is about fifteen draw calls: the one-atlas
## idea from section 2 of the plan, without having to draw the atlas.
##
## Built in code rather than in a .tscn on purpose. A hand-written .tscn full
## of Transform3D literals is where this project once lost an afternoon: Godot
## writes a basis **row by row**, so a transform typed as columns silently
## inverts.

## One tile, in metres. The kit is built on a unit grid; at 10 m its doors are
## 2 m tall and its road is as wide as a barangay street.
const TILE := 10.0
## The kit's ground pieces are thick for a toy city: at full scale a pavement
## would be a 50 cm step nobody could walk up. They are flattened by this
## instead: asphalt at ground level, a 10 cm kerb up to the pavement.
const FLAT := 2.0
## Anything standing on a base slab is sunk this far, so the slab sits level
## with the pavement instead of being a plinth.
const SINK := 0.4
## The kit only has lamp posts as part of a full-height road. Sunk this far,
## that road ends up under the flat one in the same tile, and only the posts
## come up through it.
const LAMP_SINK := 0.6

## Invisible walls, just inside the outer row of trees.
const EDGE := 64.0

## `#` road, `=` road with lamp posts, `a`-`d` buildings, `H` Lolo Ben's house,
## `t` `T` trees, `f` fountain, `,` grass, `_` pavement, `K` the court.
## Row 0 is the north edge (-z), column 0 the west (-x), and the middle tile
## is the origin. A road off the edge of the map carries on out of town.
const MAP := [
	"TtTtTt#tTtTtT",
	"Ttabcd#dacbtT",
	"Tt##=###=##tT",
	"Tb#cad=dKK#cT",
	"Ta=bfc#bKK=dT",
	"Td#adb#aKK#aT",
	"#=##=###=##=#",
	"Tc#dba#dcd#bT",
	"Tb=atH#atb=cT",
	"Ta#cdb#cad#aT",
	"Tt##=###=##tT",
	"Ttdabc#bdcatT",
	"TtTtTt#tTtTtT",
]

## Things that stand up off the ground. Lolo Ben's house is the garage: the
## smallest building in the kit, as it should be, and the only one used once.
const STANDING := {
	"a": "building-small-a", "b": "building-small-b", "c": "building-small-c",
	"d": "building-small-d", "H": "building-garage",
	"t": "grass-trees", "T": "grass-trees-tall", "f": "pavement-fountain",
}
const BUILDINGS := "abcdH"
const FLOOR := {",": "grass", "_": "pavement", "K": "pavement"}

## Each road piece and the sides it opens onto as it comes out of the kit,
## N 1, E 2, S 4, W 8.
const ROADS := {
	5: "road-straight", 12: "road-corner", 14: "road-split", 15: "road-intersection",
}
## The four neighbours by bit: N, E, S, W.
const SIDES := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Where a building built facing S faces after this many quarter turns about
## +Y: S, then E, N, W. Also the order roads are looked for in.
const TURNS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

## The loops the traffic drives round, as the tiles it turns at, (column,
## row) on MAP. All but one go clockwise, so wherever two share a street they
## share a lane too; the second goes the other way round the ring, so the
## ring has traffic both ways. Between them every street does.
const ROUTES := [
	{"cars": 3, "corners": [Vector2i(2, 2), Vector2i(10, 2), Vector2i(10, 10), Vector2i(2, 10)]},
	{"cars": 2, "corners": [Vector2i(2, 2), Vector2i(2, 10), Vector2i(10, 10), Vector2i(10, 2)]},
	{"cars": 1, "corners": [Vector2i(2, 6), Vector2i(10, 6), Vector2i(10, 10), Vector2i(2, 10)]},
	{"cars": 1, "corners": [Vector2i(10, 6), Vector2i(2, 6), Vector2i(2, 2), Vector2i(10, 2)]},
	{"cars": 1, "corners": [Vector2i(2, 2), Vector2i(6, 2), Vector2i(6, 10), Vector2i(2, 10)]},
	{"cars": 1, "corners": [Vector2i(10, 10), Vector2i(6, 10), Vector2i(6, 2), Vector2i(10, 2)]},
]
## Cars drive on the right, this far from the middle of the road.
const LANE := 2.0
const CARS := ["vehicle-truck-red", "vehicle-truck-yellow", "vehicle-truck-green",
	"vehicle-truck-purple"]

## Where a customer may stand: on the pavement, already facing the road.
var customer_spots: Array[Transform3D] = []

## Doorstep of Lolo Ben's house -- the refill point, and where the day starts.
## Both come from the `H` on the map.
var home_position := Vector3.ZERO
var player_start := Vector3.ZERO

var _mats := {}
var _kit := {}


func _ready() -> void:
	_build_sky()
	_build_ground()
	_build_tiles()
	_build_court()
	_build_home()
	_build_traffic()
	_build_bounds()


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


# --- the map ---------------------------------------------------------------

## Inside the town every tile covers the ground, but it is what everyone
## stands on, and it runs on under the fog past the last row of trees. What
## you see of it sits a little lower than what you stand on: the kit's asphalt
## is at ground level, and two surfaces at the same height flicker.
func _build_ground() -> void:
	_slab("Ground", Vector3(0, -0.15, 0), Vector3(EDGE * 4.0, 0.2, EDGE * 4.0),
		Color(0.44, 0.42, 0.37), false)
	_wall("Floor", Vector3(0, -0.1, 0), Vector3(EDGE * 4.0, 0.2, EDGE * 4.0))


func _build_tiles() -> void:
	var placed := {}
	for r in MAP.size():
		for c in MAP[r].length():
			var ch: String = MAP[r][c]
			var at := _centre(Vector2i(c, r))

			if ch == "#" or ch == "=":
				var piece := _road_piece(r, c)
				_place(placed, piece[0], at, piece[1], FLAT, 0.0)
				if ch == "=":
					_place(placed, "road-straight-lightposts", at, piece[1], TILE, LAMP_SINK)
			elif STANDING.has(ch):
				var turn := _facing(r, c)
				_place(placed, STANDING[ch], at, turn, TILE, SINK)
				if ch in BUILDINGS:
					_building(ch, at, turn)
			else:
				_place(placed, FLOOR.get(ch, "grass"), at, 0, FLAT, 0.0)

	for model in placed:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _kit_mesh(model)
		mm.instance_count = placed[model].size()
		for i in placed[model].size():
			mm.set_instance_transform(i, placed[model][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = model
		mmi.multimesh = mm
		# Roads, grass and pavement are too flat to throw a shadow worth the
		# pass, and flattened this thin they only throw acne on themselves.
		if model in ROADS.values() or model in FLOOR.values():
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## One tile of `model`, turned `turn` quarter turns, scaled up to a tile across
## and `height` metres tall per kit unit.
func _place(placed: Dictionary, model: String, at: Vector3, turn: int, height: float,
		sink: float) -> void:
	var basis := Basis(Vector3.UP, turn * PI * 0.5).scaled(Vector3(TILE, height, TILE))
	if not placed.has(model):
		placed[model] = []
	placed[model].append(Transform3D(basis, at - Vector3(0, sink, 0)))


## A building is solid, and the pavement in front of a shop is where a
## customer waits -- off to one side, because on a lamp road the post stands
## dead centre.
func _building(ch: String, at: Vector3, turn: int) -> void:
	var front: Vector2i = TURNS[turn]
	var out := Vector3(front.x, 0.0, front.y)
	var height := _kit_mesh(STANDING[ch]).get_aabb().size.y * TILE - SINK
	_wall("Building", at + Vector3(0, height * 0.5, 0),
		Vector3(TILE * 0.92, height, TILE * 0.92))

	if ch == "H":
		home_position = at + out * (TILE * 0.5 + 0.4)
		# On the pavement, clear of the traffic.
		player_start = home_position + out * 0.5
		return

	var spot := Transform3D.IDENTITY.rotated(Vector3.UP, atan2(-out.x, -out.z))
	spot.origin = at + out * (TILE * 0.5 + 0.5) + out.cross(Vector3.UP) * 2.5 \
		+ Vector3(0, 0.1, 0)
	customer_spots.append(spot)


## The road piece for a tile and how far to turn it, from which of its four
## neighbours are road too.
func _road_piece(r: int, c: int) -> Array:
	var open := 0
	for i in 4:
		if _is_road(r + SIDES[i].y, c + SIDES[i].x):
			open |= 1 << i
	for sides in ROADS:
		# A quarter turn moves every opening one side round: E to N, N to W.
		var turned: int = sides
		for turn in 4:
			if turned == open:
				return [ROADS[sides], turn]
			turned = (turned >> 1) | ((turned & 1) << 3)
	# A dead end: a straight piece the right way round.
	return ["road-straight", 0 if open & 5 else 1]


## Quarter turns that face a building (built facing S) onto a road next to it.
func _facing(r: int, c: int) -> int:
	for turn in 4:
		if _is_road(r + TURNS[turn].y, c + TURNS[turn].x):
			return turn
	return 0


func _is_road(r: int, c: int) -> bool:
	if r < 0 or r >= MAP.size() or c < 0 or c >= MAP[r].length():
		return true
	return MAP[r][c] == "#" or MAP[r][c] == "="


## The mesh out of one of the kit's .glb files. Each is a single mesh with
## the kit's shared material already on it.
func _kit_mesh(model: String) -> Mesh:
	if not _kit.has(model):
		var scene: Node = load("res://assets/kenney/city/%s.glb" % model).instantiate()
		_kit[model] = scene.find_children("*", "MeshInstance3D", true, false)[0].mesh
		scene.free()
	return _kit[model]


# --- places ----------------------------------------------------------------

func _build_court() -> void:
	# The barangay court, open to the ring road in the north-east block.
	var c := Vector3(25.0, 0.0, -20.0)
	_slab("Court", c + Vector3(0, 0.13, 0), Vector3(17.0, 0.02, 26.0),
		Color(0.34, 0.40, 0.46), false)
	for z in [-8.0, 0.0, 8.0]:
		_slab("CourtLine%d" % int(z), c + Vector3(0, 0.145, z),
			Vector3(16.0, 0.01, 0.18), Color(0.92, 0.92, 0.88), false)

	for sz in [-1.0, 1.0]:
		var base := c + Vector3(0, 0, sz * 12.0)
		_slab("HoopPost%d" % int(sz), base + Vector3(0, 1.7, 0),
			Vector3(0.22, 3.4, 0.22), Color(0.30, 0.30, 0.32), true)
		_slab("HoopBoard%d" % int(sz), base + Vector3(0, 3.3, -sz * 0.6),
			Vector3(1.6, 1.0, 0.1), Color(0.90, 0.90, 0.86), false)


## The house itself is the `H` tile. This is the warm light on the doorstep --
## the only one in town -- and the refill trigger.
func _build_home() -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "PorchLight"
	lamp.position = home_position + Vector3(0, 2.6, 0)
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	add_child(lamp)

	# The player only needs to stand on the doorstep.
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


## The traffic: each route's cars spread evenly round it, each route started
## at a different point so no two cars begin on top of each other.
func _build_traffic() -> void:
	var traffic := Node3D.new()
	traffic.name = "Traffic"
	add_child(traffic)
	var n := 0
	for r in ROUTES.size():
		var lane := _lane(ROUTES[r]["corners"])
		for i in ROUTES[r]["cars"]:
			var car := Car.new()
			car.name = "Car%d" % n
			car.setup(load("res://assets/kenney/vehicles/%s.glb" % CARS[n % CARS.size()]),
				lane, (i + r * 0.13) / ROUTES[r]["cars"])
			traffic.add_child(car)
			n += 1


## A route's corners moved into its lane: to the right of the way in to each
## one and of the way out of it.
func _lane(corners: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in corners.size():
		var at := _centre(corners[i])
		var into := (at - _centre(corners[i - 1])).normalized()
		var onto := (_centre(corners[(i + 1) % corners.size()]) - at).normalized()
		points.append(at + (into + onto).cross(Vector3.UP) * LANE)
	return points


func _centre(tile: Vector2i) -> Vector3:
	return Vector3((tile.x - 6) * TILE, 0.0, (tile.y - 6) * TILE)


## Invisible walls at the town's edge. Cheaper and more reliable than making
## the ground big enough that nobody walks off it.
func _build_bounds() -> void:
	_wall("Bound", Vector3(0, 6, -EDGE), Vector3(EDGE * 2.0, 12.0, 1.0))
	_wall("Bound", Vector3(0, 6, EDGE), Vector3(EDGE * 2.0, 12.0, 1.0))
	_wall("Bound", Vector3(-EDGE, 6, 0), Vector3(1.0, 12.0, EDGE * 2.0))
	_wall("Bound", Vector3(EDGE, 6, 0), Vector3(1.0, 12.0, EDGE * 2.0))


# --- building blocks -------------------------------------------------------

## A box. `solid` gives it collision; decoration (court paint, hoop boards)
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

	_wall(slab_name, centre, size)
	get_child(-1).add_child(mi)


## Collision with nothing of its own to see: the kit's buildings, and the
## town's edge.
func _wall(wall_name: String, centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## Materials are cached by colour, so the boxes in town share a handful of
## materials instead of owning one each.
func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	_mats[key] = mat
	return mat
