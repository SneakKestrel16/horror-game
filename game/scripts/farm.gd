class_name Farm
extends RefCounted
## The farm: one small field of turnips, a planted corn patch, the barn, the
## tool shed, the generator, and the wild corn ring around it all with ragged
## strips reaching in. The layout is fixed, so every peer builds the same farm
## without being told anything; only harvesting the planted corn changes it.
## Also answers questions about it for the creature: where the corn is, how
## much corn lies between two points, and a walking grid around the buildings.
##
## The corn is a map of one-metre cells. A plain ring left nothing in the corn
## worth going in for, and planted corn in the field would have been an island
## the creature could not reach by day (2026-10-04 playtest), so the strips
## join the ring to the planted patch and bring cover near the barn, the
## generator and the field.

## The farm is spread out so every errand is a walk in the open: the second
## Phase 1 playtest found everything so close together that the night was easy.
const HALF := 52.0  ## Invisible walls stand here; dark trees beyond.
const CORN_IN := 30.0  ## The wild corn ring starts about this far out (by max(|x|, |z|)).
const CORN_OUT := 50.0
const CORN_HEIGHT := 2.5
## Strips of wild corn reaching in from the ring (x, z, width, depth), clear of
## the buildings, the barn door and the paths' ends.
const CORN_STRIPS: Array[Rect2] = [
	Rect2(11, 10, 19, 6),  # East of the field, through the planted corn.
	Rect2(13, -19, 17, 5),  # Toward the generator.
	Rect2(-16, -30, 6, 6),  # Behind the barn's west corner.
	Rect2(-30, 10, 14, 5),  # West of the field and the pump.
	Rect2(-3, 21, 6, 9),  # Behind the field.
]
const CORN_RAGGED := 2.5  ## Metres noise moves the strips' and the ring's edges in or out.
## The planted corn: four ripe plots east of the field, joined to the ring by
## the east strip. Corn takes 3 days to grow (design doc, Crops), longer than
## Phase 2's two days, so it starts ripe and does not come back once cut.
const CORN_PLOTS: Array[Vector3] = [
	Vector3(9.5, 0, 11.5), Vector3(12.5, 0, 11.5), Vector3(9.5, 0, 14.5), Vector3(12.5, 0, 14.5)
]
const CORN_PLOT_SIZE := 3.0
const EDGE_DEPTHS := 6  ## Corn cells this many steps in or fewer count as near the edge.

const BARN := Rect2(-6.0, -22.0, 12.0, 10.0)  ## x, z, width, depth; door on the +z side.
const BARN_DOOR := 3.2
const BARN_HEIGHT := 5.0
## Door on the +z side. Far west, with the fuel drum, so fuel runs cross open ground.
const SHED := Rect2(-25.0, -4.0, 4.0, 3.0)
const SHED_DOOR := 1.4
const SHED_HEIGHT := 2.6
const WALL := 0.25
const BARN_LIGHT := 1.6  ## Energy of each barn lamp.

const SPAWN := Vector3(0, 0, -15)  ## Inside the barn, so the dead come back under its lights.
## Where the creature stands to take traps: outside the shed door (it never goes in).
const SHED_DOOR_OUT := Vector3(-23.0, 0, 0.6)
## The pegboard on the shed's back wall, facing the door.
const PEGBOARD := Vector3(-23.0, 1.3, -3.66)
const GENERATOR := Vector3(7.4, 0, -13.4)
const FUEL_DRUM := Vector3(-19.8, 0, -2.6)
const PUMP := Vector3(-6.0, 0, 7.0)
const CRATE := Vector3(18.0, 0, 6.0)
const PLOT_SIZE := 2.2
## The small field: four columns by three rows of turnip plots.
const PLOTS: Array[Vector3] = [
	Vector3(-4.5, 0, 10),
	Vector3(-1.5, 0, 10),
	Vector3(1.5, 0, 10),
	Vector3(4.5, 0, 10),
	Vector3(-4.5, 0, 13),
	Vector3(-1.5, 0, 13),
	Vector3(1.5, 0, 13),
	Vector3(4.5, 0, 13),
	Vector3(-4.5, 0, 16),
	Vector3(-1.5, 0, 16),
	Vector3(1.5, 0, 16),
	Vector3(4.5, 0, 16),
]
## Where the tools start. Kinds are game.gd's item kinds.
const ITEMS: Array[Dictionary] = [
	{"kind": "watering_can", "position": Vector3(-5.0, 0, 8.0)},
	{"kind": "shovel", "position": Vector3(-24.2, 0, -3.1)},
	{"kind": "crowbar", "position": Vector3(-22.0, 0, -3.3)},
	{"kind": "fuel_can", "position": Vector3(-20.0, 0, -1.2)},
]

const GRID := Rect2i(-54, -54, 108, 108)  ## The walking grid, one cell per metre.
## Grid cells this close to a wall count as blocked. More would close the 3.2 m barn
## doorway on a one-metre grid.
const CLEARANCE := 0.3

static var _trap_spots := {}
# The corn map, shared by every user of the static helpers below. One farm
# exists at a time; each new one grows it afresh.
static var _corn_cells := PackedByteArray()  ## Per grid cell: 1 where corn grows.
static var _depth := PackedInt32Array()  ## Per corn cell: steps in from open farm ground.
static var _edge: Array[Vector2i] = []  ## Corn cells at most EDGE_DEPTHS steps in.
static var _deep: Array[Vector2i] = []  ## Corn cells at least 2 steps in.

var grid := AStarGrid2D.new()
var corn_grid := AStarGrid2D.new()  ## Only the corn: how it moves by day.
var barn_lights: Array[OmniLight3D] = []
var corn_patches: Array[Node3D] = []  ## Each planted corn plot's stalks.
var _barn_lit := false
var _haunted_until := {}  ## Barn lamp index -> msec a ghost's flicker lasts until.


func _init() -> void:
	_grow_corn()
	trap_spots()  # Cached from the corn as it starts, before any is cut.
	grid.region = GRID
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	_block_walls()
	corn_grid.region = GRID
	corn_grid.cell_size = Vector2.ONE
	corn_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	corn_grid.update()
	for x in range(GRID.position.x, GRID.end.x):
		for z in range(GRID.position.y, GRID.end.y):
			var cell := Vector2i(x, z)
			if maxf(absf(x + 0.5), absf(z + 0.5)) > HALF - 0.5:
				grid.set_point_solid(cell)
			if not in_corn(Vector3(x + 0.5, 0, z + 0.5)):
				corn_grid.set_point_solid(cell)


## Adds the farm's meshes, colliders and lights under parent.
func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Farm"
	parent.add_child(root)

	var ground := StaticBody3D.new()
	var plane := CollisionShape3D.new()
	plane.shape = WorldBoundaryShape3D.new()
	ground.add_child(plane)
	root.add_child(ground)
	_add_box(root, Vector3(0, -0.05, 0), Vector3(140, 0.1, 140), Color(0.28, 0.33, 0.16), false)
	# A worn dirt yard between the barn, shed and field.
	_add_box(root, Vector3(-4, -0.04, -4), Vector3(44, 0.1, 18), Color(0.36, 0.3, 0.2), false)
	for plot in PLOTS:
		_add_box(root, plot + Vector3(0, -0.02, 0), Vector3(2.4, 0.1, 2.4), Color(0.22, 0.15, 0.09))

	for wall in _walls():
		var box: AABB = wall
		var colour := (
			Color(0.42, 0.1, 0.08) if box.size.y > SHED_HEIGHT + 0.5 else Color(0.4, 0.37, 0.3)
		)
		_add_box(root, box.get_center(), box.size, colour, true)
	# Roofs: overhanging slabs, no colliders needed above head height.
	_add_box(
		root, _rect_center(BARN, BARN_HEIGHT + 0.2), Vector3(13, 0.4, 11), Color(0.2, 0.2, 0.22)
	)
	_add_box(
		root, _rect_center(SHED, SHED_HEIGHT + 0.1), Vector3(4.6, 0.2, 3.6), Color(0.25, 0.22, 0.2)
	)
	# Hay inside the barn, and a door frame lamp outside it.
	var middle := _rect_center(BARN, 0.0)
	for side: float in [-4.2, 4.2]:
		var hay := middle + Vector3(side, 0.5, -3.6)
		_add_box(root, hay, Vector3(2.4, 1.0, 1.2), Color(0.75, 0.62, 0.3), true)
	for spot: Vector3 in [
		middle + Vector3(-2.5, 4.2, -0.5),
		middle + Vector3(2.5, 4.2, -0.5),
		Vector3(0, 3.6, BARN.end.y + 0.6),
	]:
		var light := OmniLight3D.new()
		light.position = spot
		light.light_color = Color(1.0, 0.82, 0.55)
		light.light_energy = BARN_LIGHT
		light.omni_range = 9.0
		light.shadow_enabled = true
		light.visible = false
		root.add_child(light)
		barn_lights.append(light)

	_add_box(
		root, GENERATOR + Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 0.8), Color(0.55, 0.5, 0.15), true
	)
	var drum := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.35
	cylinder.bottom_radius = 0.35
	cylinder.height = 1.0
	cylinder.material = _material(Color(0.6, 0.12, 0.08))
	drum.mesh = cylinder
	drum.position = FUEL_DRUM + Vector3(0, 0.5, 0)
	root.add_child(drum)
	_add_box(
		root, PUMP + Vector3(0, 0.6, 0), Vector3(0.25, 1.2, 0.25), Color(0.25, 0.3, 0.32), true
	)
	_add_box(root, PUMP + Vector3(0, 1.1, 0.3), Vector3(0.12, 0.12, 0.6), Color(0.25, 0.3, 0.32))
	_add_box(root, CRATE + Vector3(0, 0.4, 0), Vector3(1.4, 0.8, 1.0), Color(0.5, 0.36, 0.2), true)

	for side in 4:
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(HALF * 2.0 + 2.0, 6.0, 1.0)
		shape.shape = box
		wall.add_child(shape)
		wall.rotation.y = side * PI / 2.0
		wall.position = Vector3(0, 3, HALF + 0.5).rotated(Vector3.UP, side * PI / 2.0)
		root.add_child(wall)
	root.add_child(_corn())
	for i in CORN_PLOTS.size():
		var rect := corn_plot_rect(i)
		_add_box(
			root,
			Vector3(rect.get_center().x, -0.03, rect.get_center().y),
			Vector3(rect.size.x, 0.1, rect.size.y),
			Color(0.22, 0.15, 0.09)
		)
		corn_patches.append(_corn_patch(i))
		root.add_child(corn_patches[i])
	root.add_child(_trees())


## Lights the barn (the creature will not go in) or leaves it dark.
func set_barn_lit(lit: bool) -> void:
	_barn_lit = lit
	for light in barn_lights:
		light.visible = lit
	_fill(BARN.grow(-WALL), lit)
	_block_walls()  # Clearing the inside cleared the wall cells it overlaps.


## Low fuel: the barn lights stutter now and then (cosmetic, per peer). A lamp
## a ghost is flickering (haunt) stutters hard whatever the fuel.
func flicker(on: bool) -> void:
	var now := Time.get_ticks_msec()
	for i in barn_lights.size():
		var haunted: bool = _haunted_until.get(i, 0) > now
		var chance := 0.5 if haunted else (0.1 if on else 0.0)
		var low := randf_range(0.0, 0.3) if haunted else randf_range(0.05, 0.4)
		barn_lights[i].light_energy = BARN_LIGHT * (low if randf() < chance else 1.0)


## Every peer: a ghost flickers barn lamp index for a moment.
func haunt(index: int, seconds: float) -> void:
	_haunted_until[index] = Time.get_ticks_msec() + roundi(seconds * 1000.0)


func barn_lit() -> bool:
	return _barn_lit


## Whether a and b are within reach of each other, ignoring height.
static func near(a: Vector3, b: Vector3, reach: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= reach


static func in_barn(point: Vector3) -> bool:
	return BARN.grow(-WALL).has_point(Vector2(point.x, point.z))


static func in_corn(point: Vector3) -> bool:
	var cell := Vector2i(floori(point.x), floori(point.z))
	if not GRID.has_point(cell):
		return false
	if _corn_cells.is_empty():
		_grow_corn()
	return _corn_cells[_index(cell)] == 1


## Host and peers: a planted corn plot was cut; it is open ground from now on.
func cut_corn(index: int) -> void:
	var rect := corn_plot_rect(index)
	for x in range(floori(rect.position.x), ceili(rect.end.x)):
		for z in range(floori(rect.position.y), ceili(rect.end.y)):
			var cell := Vector2i(x, z)
			if rect.has_point(Vector2(x + 0.5, z + 0.5)):
				_corn_cells[_index(cell)] = 0
				corn_grid.set_point_solid(cell)
	_measure_corn()
	if index < corn_patches.size():
		corn_patches[index].visible = false


## A planted corn plot's ground (x, z).
static func corn_plot_rect(index: int) -> Rect2:
	var at := CORN_PLOTS[index]
	var half := CORN_PLOT_SIZE / 2.0
	return Rect2(at.x - half, at.z - half, CORN_PLOT_SIZE, CORN_PLOT_SIZE)


static func _index(cell: Vector2i) -> int:
	return (cell.x - GRID.position.x) + (cell.y - GRID.position.y) * GRID.size.x


## Fills the corn map: the ring and the strips, their edges roughened by
## noise, and the planted plots.
static func _grow_corn() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 3  # Fixed, so every peer grows the same corn.
	noise.frequency = 0.12
	_corn_cells.resize(GRID.size.x * GRID.size.y)
	for x in range(GRID.position.x, GRID.end.x):
		for z in range(GRID.position.y, GRID.end.y):
			var at := Vector2(x + 0.5, z + 0.5)
			var rough := noise.get_noise_2d(at.x, at.y) * CORN_RAGGED
			var ring := maxf(absf(at.x), absf(at.y))
			var corn := ring >= CORN_IN + rough and ring <= CORN_OUT
			for strip in CORN_STRIPS:
				corn = corn or _signed_distance(strip, at) <= rough
			for i in CORN_PLOTS.size():
				corn = corn or corn_plot_rect(i).has_point(at)
			_corn_cells[_index(Vector2i(x, z))] = 1 if corn else 0
	_measure_corn()


## How far point lies outside rect; negative inside.
static func _signed_distance(rect: Rect2, point: Vector2) -> float:
	var out := Vector2(
		maxf(rect.position.x - point.x, point.x - rect.end.x),
		maxf(rect.position.y - point.y, point.y - rect.end.y)
	)
	return out.max(Vector2.ZERO).length() + minf(maxf(out.x, out.y), 0.0)


## How many steps each corn cell lies in from the farm's open ground, and the
## lists of edge and deep cells built from that.
static func _measure_corn() -> void:
	_depth.resize(_corn_cells.size())
	_depth.fill(0)
	var queue: Array[Vector2i] = []
	for x in range(GRID.position.x, GRID.end.x):
		for z in range(GRID.position.y, GRID.end.y):
			var cell := Vector2i(x, z)
			# Open ground on the farm side; the strip past the ring's outside isn't.
			if _corn_cells[_index(cell)] == 0 and maxi(absi(x), absi(z)) < CORN_OUT:
				queue.append(cell)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var next_depth := _depth[_index(cell)] + 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if not GRID.has_point(next):
				continue
			var i := _index(next)
			if _corn_cells[i] == 1 and _depth[i] == 0:
				_depth[i] = next_depth
				queue.append(next)
	_edge.clear()
	_deep.clear()
	for x in range(GRID.position.x, GRID.end.x):
		for z in range(GRID.position.y, GRID.end.y):
			var cell := Vector2i(x, z)
			var depth := _depth[_index(cell)]
			if _corn_cells[_index(cell)] == 0:
				continue
			if depth >= 1 and depth <= EDGE_DEPTHS:
				_edge.append(cell)
			if depth == 0 or depth >= 2:
				_deep.append(cell)


## Metres of corn the straight line from a to b passes through.
static func corn_between(a: Vector3, b: Vector3) -> float:
	var length := Vector2(a.x - b.x, a.z - b.z).length()
	var steps := maxi(1, ceili(length / 0.5))
	var inside := 0
	for i in steps:
		if in_corn(a.lerp(b, (i + 0.5) / steps)):
			inside += 1
	return length * inside / steps


## The point just inside the corn nearest to point (point itself if it is in
## the corn already), depth metres in from the edge.
## The strips are only a few cells across, so a depth deeper than they go
## finds the strip's middle when it is much nearer than the ring.
static func corn_edge_near(point: Vector3, depth := 1.5) -> Vector3:
	if in_corn(point):
		return point
	var want := roundi(depth + 0.5)  # A cell n steps in has its centre about n - 0.5 m in.
	var flat := Vector2(point.x, point.z)
	var best := Vector2i.MAX
	var best_score := INF
	for cell in _edge:
		var miss := absi(_depth[_index(cell)] - want)
		var score := flat.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) + miss * 2.0
		if score < best_score:
			best_score = score
			best = cell
	return Vector3(best.x + 0.5, 0, best.y + 0.5)


## Candidate trap spots, built once: {"corn": just inside the wild corn on the
## farm side, "path": along the ways between the barn, shed, field, generator
## and crate, "rows": between the field's plots}. None near a landmark.
static func trap_spots() -> Dictionary:
	if not _trap_spots.is_empty():
		return _trap_spots
	var door := Vector3(0, 0, BARN.end.y + 1.5)
	var field := Vector3(0, 0, 13)
	var corn: Array[Vector3] = []
	for cell in _edge:
		# One or two steps in, about one cell in three.
		if _depth[_index(cell)] <= 2 and posmod(cell.x + cell.y * 2, 3) == 0:
			corn.append(Vector3(cell.x + 0.5, 0, cell.y + 0.5))
	var path: Array[Vector3] = []
	for way: Array in [
		[door, SHED_DOOR_OUT],
		[door, field],
		[field, CRATE],
		[door, GENERATOR],
		[SHED_DOOR_OUT, PUMP]
	]:
		var from: Vector3 = way[0]
		var to: Vector3 = way[1]
		var steps := floori(from.distance_to(to) / 2.0)
		for i in range(1, steps):
			path.append(from.lerp(to, float(i) / steps))
	var rows: Array[Vector3] = []
	for x: float in [-3.0, 0.0, 3.0]:
		for z: float in [10.0, 11.5, 13.0, 14.5, 16.0]:
			rows.append(Vector3(x, 0, z))
	var landmarks: Array[Vector3] = [door, SHED_DOOR_OUT, GENERATOR, FUEL_DRUM, PUMP, CRATE, SPAWN]
	var clear := func(at: Vector3) -> bool:
		return landmarks.all(func(mark: Vector3) -> bool: return mark.distance_to(at) > 3.0)
	_trap_spots = {"corn": corn.filter(clear), "path": path.filter(clear), "rows": rows}
	return _trap_spots


## A random walkable point in the corn, at least two steps in.
static func random_corn_point(rng: RandomNumberGenerator) -> Vector3:
	var cell := _deep[rng.randi() % _deep.size()]
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)


## Waypoints from one point to another round the buildings, empty if there
## is no way (a lit barn's inside is blocked). corn_only keeps to the corn.
func route(from: Vector3, to: Vector3, corn_only := false) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var walk := corn_grid if corn_only else grid
	var start := _open_cell_near(walk, _cell(from))
	var goal := _open_cell_near(walk, _cell(to))
	if start == Vector2i.MAX or goal == Vector2i.MAX:
		return path
	for point in walk.get_point_path(start, goal):
		path.append(Vector3(point.x + 0.5, 0, point.y + 0.5))
	if not path.is_empty():
		path.pop_front()  # The cell it stands in.
	return path


func _cell(point: Vector3) -> Vector2i:
	var cell := Vector2i(floori(point.x), floori(point.z))
	return cell.clamp(GRID.position, GRID.end - Vector2i.ONE)


## cell itself if it is open, else the nearest open cell (Vector2i.MAX if none).
static func _open_cell_near(walk: AStarGrid2D, cell: Vector2i) -> Vector2i:
	if not walk.is_point_solid(cell):
		return cell
	for radius in range(1, 24):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var next := cell + Vector2i(dx, dz)
				if walk.is_in_boundsv(next) and not walk.is_point_solid(next):
					return next
	return Vector2i.MAX


func _block_walls() -> void:
	for wall in _walls():
		var box: AABB = wall
		var area := Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(CLEARANCE)
		_fill(area, true)
	for prop in props():
		_fill(prop.grow(CLEARANCE), true)


## The solid things standing about the farm (x, z footprints): the hay in the
## barn, the generator, the pump and the shipping crate. Routes go round them;
## left off the grid, the creature walked into them and stuck (2026-10-04).
static func props() -> Array[Rect2]:
	var middle := BARN.get_center()
	var rects: Array[Rect2] = []
	for side: float in [-4.2, 4.2]:
		rects.append(Rect2(middle.x + side - 1.2, middle.y - 3.6 - 0.6, 2.4, 1.2))
	rects.append(Rect2(GENERATOR.x - 0.6, GENERATOR.z - 0.4, 1.2, 0.8))
	rects.append(Rect2(PUMP.x - 0.125, PUMP.z - 0.125, 0.25, 0.25))
	rects.append(Rect2(CRATE.x - 0.7, CRATE.z - 0.5, 1.4, 1.0))
	return rects


## Whether a straight walk from a to b crosses nothing solid on the walking grid.
func clear_line(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, ceili(Vector2(a.x - b.x, a.z - b.z).length() / 0.5))
	for i in steps + 1:
		var at := a.lerp(b, float(i) / steps)
		if grid.is_point_solid(_cell(at)):
			return false
	return true


func _fill(area: Rect2, solid: bool) -> void:
	for x in range(floori(area.position.x), ceili(area.end.x)):
		for z in range(floori(area.position.y), ceili(area.end.y)):
			if grid.is_in_boundsv(Vector2i(x, z)):
				grid.set_point_solid(Vector2i(x, z), solid)


## The barn's and shed's walls as boxes, with a doorway in each +z wall.
static func _walls() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for building: Array in [[BARN, BARN_DOOR, BARN_HEIGHT], [SHED, SHED_DOOR, SHED_HEIGHT]]:
		var rect: Rect2 = building[0]
		var door: float = building[1]
		var height: float = building[2]
		var x0 := rect.position.x
		var z0 := rect.position.y
		var x1 := rect.end.x
		var z1 := rect.end.y
		boxes.append(AABB(Vector3(x0, 0, z0), Vector3(rect.size.x, height, WALL)))
		boxes.append(AABB(Vector3(x0, 0, z0), Vector3(WALL, height, rect.size.y)))
		boxes.append(AABB(Vector3(x1 - WALL, 0, z0), Vector3(WALL, height, rect.size.y)))
		var side := (rect.size.x - door) / 2.0
		boxes.append(AABB(Vector3(x0, 0, z1 - WALL), Vector3(side, height, WALL)))
		boxes.append(AABB(Vector3(x1 - side, 0, z1 - WALL), Vector3(side, height, WALL)))
	return boxes


static func _rect_center(rect: Rect2, y: float) -> Vector3:
	var center := rect.get_center()
	return Vector3(center.x, y, center.y)


## Rows of wild corn filling the ring and the strips, as one MultiMesh. Corn
## has no collider: players and the creature walk through it, and it hides
## whoever is inside.
func _corn() -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1  # Fixed, so every peer grows the same corn.
	var spots: Array[Transform3D] = []
	var colours: Array[Color] = []
	var z := -CORN_OUT
	while z <= CORN_OUT:
		var x := -CORN_OUT
		while x <= CORN_OUT:
			var at := Vector3(x + rng.randf_range(-0.15, 0.15), 0, z + rng.randf_range(-0.1, 0.1))
			if in_corn(at) and _corn_plot_at(at) < 0:
				var scale := rng.randf_range(0.85, 1.15)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, scale, 1))
				basis = basis.rotated(Vector3.RIGHT, rng.randf_range(-0.06, 0.06))
				spots.append(Transform3D(basis, at))
				var dry := rng.randf()
				colours.append(Color(0.3, 0.42, 0.14).lerp(Color(0.55, 0.5, 0.25), dry * 0.6))
			x += 0.55
		z += 0.9  # Rows run along x.
	var instance := _stalks(spots, colours)
	instance.name = "Corn"
	return instance


## One planted plot's corn: straight, even rows, greener than the wild corn.
func _corn_patch(index: int) -> MultiMeshInstance3D:
	var rect := corn_plot_rect(index).grow(-0.2)
	var spots: Array[Transform3D] = []
	var colours: Array[Color] = []
	var z := rect.position.y
	while z <= rect.end.y:
		var x := rect.position.x
		while x <= rect.end.x:
			spots.append(Transform3D(Basis(Vector3.UP, (x + z) * 2.0), Vector3(x, 0, z)))
			colours.append(Color(0.28, 0.48, 0.14))
			x += 0.5
		z += 0.75
	return _stalks(spots, colours)


## Which planted corn plot point is in, or -1.
static func _corn_plot_at(point: Vector3) -> int:
	for i in CORN_PLOTS.size():
		if corn_plot_rect(i).has_point(Vector2(point.x, point.z)):
			return i
	return -1


func _stalks(spots: Array[Transform3D], colours: Array[Color]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _stalk_mesh()
	multimesh.instance_count = spots.size()
	for i in spots.size():
		multimesh.set_instance_transform(i, spots[i])
		multimesh.set_instance_color(i, colours[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## One stalk: two crossed tapering quads and four drooping leaves.
static func _stalk_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for turn in 2:
		var across := Vector3.RIGHT.rotated(Vector3.UP, turn * PI / 2.0)
		_quad(
			tool,
			[
				across * -0.05,
				across * 0.05,
				across * 0.02 + Vector3.UP * CORN_HEIGHT,
				across * -0.02 + Vector3.UP * CORN_HEIGHT
			]
		)
	for leaf in 4:
		var out := Vector3.FORWARD.rotated(Vector3.UP, leaf * 1.7)
		var side := out.cross(Vector3.UP) * 0.06
		var base := Vector3.UP * (0.7 + leaf * 0.38)
		var tip := base + out * 0.55 + Vector3.UP * 0.15
		_quad(
			tool,
			[
				base - side,
				base + side,
				tip + side * 0.3 + Vector3.DOWN * 0.25,
				tip - side * 0.3 + Vector3.DOWN * 0.25
			]
		)
	tool.generate_normals()
	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	mesh.surface_set_material(0, material)
	return mesh


static func _quad(tool: SurfaceTool, corners: Array) -> void:
	for index: int in [0, 1, 2, 0, 2, 3]:
		tool.set_color(Color.WHITE)
		tool.add_vertex(corners[index])


## A dark wall of trees past the corn, so the world has an edge.
static func _trees() -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.2
	cone.height = 9.0
	cone.material = _material(Color(0.07, 0.11, 0.07))
	multimesh.mesh = cone
	var spots: Array[Vector3] = []
	var along := -HALF - 4.0
	while along <= HALF + 4.0:
		for side in 4:
			var at := Vector3(along, 4.5, HALF + rng.randf_range(1.5, 4.0))
			spots.append(at.rotated(Vector3.UP, side * PI / 2.0))
		along += 2.6
	multimesh.instance_count = spots.size()
	for i in spots.size():
		var scale := rng.randf_range(0.8, 1.4)
		multimesh.set_instance_transform(
			i, Transform3D(Basis.from_scale(Vector3.ONE * scale), spots[i])
		)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	return instance


static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	return material


static func _add_box(
	parent: Node3D, center: Vector3, size: Vector3, colour: Color, solid := false
) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(colour)
	mesh.mesh = box
	mesh.position = center
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var collider := BoxShape3D.new()
		collider.size = size
		shape.shape = collider
		body.add_child(shape)
		body.position = center
		parent.add_child(body)
