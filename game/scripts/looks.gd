class_name Looks
extends RefCounted
## Placeholder models for the things game.gd keeps track of: tools, crops
## and traps, built from primitive meshes. Also the sun and moon, and the sky
## (drawn by assets/shaders/sky.gdshader).

## Each item kind's parts: [mesh class, position, size, colour].
const ITEM_PARTS := {
	"watering_can":
	[
		["cylinder", Vector3(0, 0.15, 0), Vector3(0.28, 0.15, 0.28), Color(0.3, 0.45, 0.5)],
		["box", Vector3(0, 0.22, -0.2), Vector3(0.04, 0.04, 0.3), Color(0.3, 0.45, 0.5)],
	],
	"shovel":
	[
		["box", Vector3(0, 0.6, 0), Vector3(0.04, 1.0, 0.04), Color(0.5, 0.35, 0.2)],
		["box", Vector3(0, 0.05, 0), Vector3(0.22, 0.28, 0.03), Color(0.45, 0.45, 0.48)],
	],
	"crowbar":
	[
		["box", Vector3(0, 0.4, 0), Vector3(0.035, 0.8, 0.035), Color(0.55, 0.12, 0.1)],
		["box", Vector3(0, 0.8, -0.05), Vector3(0.035, 0.035, 0.12), Color(0.55, 0.12, 0.1)],
	],
	"fuel_can": [["box", Vector3(0, 0.2, 0), Vector3(0.3, 0.4, 0.15), Color(0.75, 0.15, 0.1)]],
	"bear_trap":
	[
		["torus", Vector3(0, 0.25, 0), Vector3(0.45, 0.5, 0.45), Color(0.32, 0.3, 0.28)],
		["box", Vector3(0, 0.25, 0), Vector3(0.05, 0.4, 0.45), Color(0.32, 0.3, 0.28)],
	],
	"turnip":
	[
		["sphere", Vector3(0, 0.12, 0), Vector3(0.22, 0.2, 0.22), Color(0.88, 0.85, 0.9)],
		["sphere", Vector3(0, 0.12, 0.1), Vector3(0.2, 0.18, 0.2), Color(0.75, 0.45, 0.75)],
		["box", Vector3(0, 0.3, 0), Vector3(0.05, 0.2, 0.05), Color(0.3, 0.55, 0.2)],
	],
	"corn":  # A bundle of ears in their husks.
	[
		["cylinder", Vector3(-0.07, 0.18, 0), Vector3(0.09, 0.18, 0.09), Color(0.9, 0.78, 0.3)],
		["cylinder", Vector3(0.07, 0.18, 0), Vector3(0.09, 0.18, 0.09), Color(0.9, 0.78, 0.3)],
		["box", Vector3(0, 0.2, 0.04), Vector3(0.24, 0.3, 0.03), Color(0.55, 0.6, 0.3)],
	],
	"pumpkin":
	[
		["sphere", Vector3(0, 0.16, 0), Vector3(0.36, 0.28, 0.36), Color(0.9, 0.45, 0.08)],
		["cylinder", Vector3(0, 0.33, 0), Vector3(0.04, 0.06, 0.04), Color(0.35, 0.3, 0.15)],
	],
	"moonflower":  # A bunch of pale blooms; Looks.item makes them glow.
	[
		["box", Vector3(0, 0.15, 0), Vector3(0.04, 0.3, 0.04), Color(0.3, 0.45, 0.35)],
		["sphere", Vector3(0, 0.32, 0), Vector3(0.22, 0.1, 0.22), Color(0.75, 0.85, 1.0)],
	],
	"turnip_seeds": [["box", Vector3(0, 0.1, 0), Vector3(0.16, 0.22, 0.04), Color(0.7, 0.45, 0.7)]],
	"pumpkin_seeds":
	[["box", Vector3(0, 0.1, 0), Vector3(0.16, 0.22, 0.04), Color(0.9, 0.5, 0.15)]],
	"moonflower_seeds":
	[["box", Vector3(0, 0.1, 0), Vector3(0.16, 0.22, 0.04), Color(0.35, 0.4, 0.75)]],
	"crow":  # Body and two spread wings; it only flaps past (Director fake-out).
	[
		["sphere", Vector3.ZERO, Vector3(0.22, 0.18, 0.4), Color(0.04, 0.04, 0.05)],
		["box", Vector3(-0.3, 0.05, 0), Vector3(0.45, 0.03, 0.2), Color(0.04, 0.04, 0.05)],
		["box", Vector3(0.3, 0.05, 0), Vector3(0.45, 0.03, 0.2), Color(0.04, 0.04, 0.05)],
	],
}
const METAL := Color(0.32, 0.3, 0.28)


static func item(parent: Node3D, kind: String) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	for part: Array in ITEM_PARTS[kind]:
		mesh(node, part[0], part[1], part[2], part[3])
	if kind == "moonflower":  # Picked, they still glow: a light to carry in the dark.
		var bloom: Array = ITEM_PARTS[kind][1]
		glow(node, bloom[1], bloom[2], bloom[3])
	return node


## Rebuilds a plot's soil and crop for its Chores.Stage: turnips, pumpkins
## or moonflowers (pale, and glowing once ripe); weeds while it is LOCKED.
static func plot(node: Node3D, stage: int, crop: String) -> void:
	_clear(node)
	var soil := Color(0.16, 0.1, 0.06) if stage == Chores.Stage.GROWING else Color(0.22, 0.15, 0.09)
	mesh(node, "box", Vector3(0, 0.035, 0), Vector3(2.3, 0.02, 2.3), soil)
	if stage == Chores.Stage.EMPTY:
		return
	if stage == Chores.Stage.LOCKED:
		for i in 14:  # Weeds, at fixed spots so every peer sees the same.
			var at := Vector3(fmod(i * 0.83, 2.0) - 1.0, 0.3, fmod(i * 0.57, 2.0) - 1.0)
			mesh(node, "box", at, Vector3(0.06, 0.6, 0.06), Color(0.32, 0.36, 0.14))
		return
	var ripe := stage == Chores.Stage.RIPE
	var leaf := 0.35 if ripe else 0.18
	for x in 3:
		for z in 3:
			var at := Vector3((x - 1) * 0.65, leaf / 2.0, (z - 1) * 0.65)
			match crop:
				"pumpkin":
					if x != 1 or z != 1:
						continue  # Sprawling vines, fewer fruit.
					mesh(
						node, "sphere", at, Vector3(leaf, leaf, leaf) * 1.6, Color(0.2, 0.45, 0.15)
					)
					if ripe:
						var fruit := at + Vector3(0.35, -0.05, 0.3)
						mesh(node, "sphere", fruit, Vector3(0.5, 0.36, 0.5), Color(0.9, 0.45, 0.08))
				"moonflower":
					var stem := Vector3(0.04, leaf * 1.6, 0.04)
					mesh(node, "box", at, stem, Color(0.3, 0.45, 0.35))
					if ripe:
						var bloom := at + Vector3(0, leaf * 0.8, 0)
						glow(node, bloom, Vector3(0.22, 0.08, 0.22), Color(0.75, 0.85, 1.0))
				_:
					mesh(node, "sphere", at, Vector3(leaf, leaf, leaf), Color(0.25, 0.55, 0.2))
					if ripe:
						var top := at + Vector3(0.1, -leaf / 2.0 + 0.05, 0.1)
						mesh(node, "sphere", top, Vector3(0.14, 0.1, 0.14), Color(0.8, 0.5, 0.8))


## A glowing part (a ripe moonflower).
static func glow(parent: Node3D, at: Vector3, size: Vector3, colour: Color) -> void:
	mesh(parent, "sphere", at, size, colour)
	var part := parent.get_child(parent.get_child_count() - 1) as MeshInstance3D
	var material := (part.mesh as PrimitiveMesh).material as StandardMaterial3D
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 1.5


## Rebuilds a trap for its TrapField.State. An armed pit is husks over a hole,
## only a little paler than the dirt; an armed bear trap lies open and flat.
static func trap(node: Node3D, kind: String, state: int) -> void:
	_clear(node)
	if state == TrapField.State.HIDDEN:
		return
	if kind == "pit":
		match state:
			TrapField.State.ARMED:
				mesh(
					node,
					"box",
					Vector3(0, 0.02, 0),
					Vector3(1.1, 0.03, 1.0),
					Color(0.42, 0.36, 0.22)
				)
			TrapField.State.SPRUNG:
				mesh(
					node,
					"cylinder",
					Vector3(0, 0.015, 0),
					Vector3(1, 0.01, 1),
					Color(0.02, 0.02, 0.01)
				)
			TrapField.State.DISARMED:
				mesh(node, "sphere", Vector3.ZERO, Vector3(1.0, 0.18, 1.0), Color(0.3, 0.2, 0.12))
		return
	mesh(node, "torus", Vector3(0, 0.03, 0), Vector3(0.55, 0.3, 0.55), METAL)
	if state == TrapField.State.ARMED:
		mesh(node, "box", Vector3(-0.22, 0.03, 0), Vector3(0.18, 0.02, 0.5), METAL)
		mesh(node, "box", Vector3(0.22, 0.03, 0), Vector3(0.18, 0.02, 0.5), METAL)
		mesh(
			node, "cylinder", Vector3(0, 0.03, 0), Vector3(0.12, 0.01, 0.12), Color(0.5, 0.45, 0.35)
		)
	else:  # Jaws shut, standing up.
		mesh(node, "box", Vector3(0, 0.14, 0), Vector3(0.06, 0.24, 0.5), METAL)


## A primitive ("box", "sphere", "cylinder" or "torus") scaled to size.
static func mesh(parent: Node3D, shape: String, at: Vector3, size: Vector3, colour: Color) -> void:
	var primitive: PrimitiveMesh
	match shape:
		"box":
			primitive = BoxMesh.new()
		"sphere":
			primitive = SphereMesh.new()
		"cylinder":
			primitive = CylinderMesh.new()
		_:
			primitive = TorusMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	primitive.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = primitive
	instance.position = at
	instance.scale = size
	parent.add_child(instance)


## Rebuilds the pegboard: painted outlines for every slot, a trap hanging in
## the first filled ones, so one glance shows how many are gone.
static func pegboard(node: Node3D, filled: int, slots: int) -> void:
	_clear(node)
	mesh(node, "box", Vector3.ZERO, Vector3(2.6, 1.3, 0.05), Color(0.55, 0.45, 0.3))
	for i in slots:
		var at := Vector3(-0.96 + i * 0.64, 0.0, 0.035)
		var paint := Color(0.92, 0.92, 0.88)
		for edge: Vector3 in [Vector3(0, 0.28, 0), Vector3(0, -0.28, 0)]:
			mesh(node, "box", at + edge, Vector3(0.5, 0.03, 0.01), paint)
		for edge: Vector3 in [Vector3(-0.25, 0, 0), Vector3(0.25, 0, 0)]:
			mesh(node, "box", at + edge, Vector3(0.03, 0.56, 0.01), paint)
		if i < filled:
			var hanging := MeshInstance3D.new()
			var ring := TorusMesh.new()
			var material := StandardMaterial3D.new()
			material.albedo_color = METAL
			ring.material = material
			hanging.mesh = ring
			hanging.position = at + Vector3(0, 0, 0.06)
			hanging.rotation.x = PI / 2.0
			hanging.scale = Vector3(0.21, 0.3, 0.21)
			node.add_child(hanging)


static func _clear(node: Node3D) -> void:
	for child in node.get_children():
		child.queue_free()


## The sky, a sun and a moon, added under parent. apply() sets them for the time of day.
class Daylight:
	## The sky through a game day, on a timeline s: 0..1 is the day, 1..2 dusk, 2..3
	## the night and 3..4 the last dawn. Each key is [s, zenith, horizon, glow round
	## the sun, the earth's shadow opposite it, sun, lit cloud, shaded cloud, cloud
	## cover, stars], in sRGB. Between keys the colours blend.
	const KEYS := [
		[
			0.0,
			Color(0.32, 0.48, 0.75),
			Color(0.98, 0.78, 0.62),
			Color(1.0, 0.7, 0.4),
			Color(0.55, 0.6, 0.78),
			Color(1.0, 0.75, 0.5),
			Color(1.0, 0.86, 0.72),
			Color(0.55, 0.55, 0.65),
			0.45,
			0.0
		],  # Morning
		[
			0.12,
			Color(0.25, 0.5, 0.85),
			Color(0.78, 0.86, 0.93),
			Color(1.0, 0.9, 0.75),
			Color(0.6, 0.7, 0.85),
			Color(1.0, 0.92, 0.8),
			Color(1.0, 0.98, 0.95),
			Color(0.6, 0.64, 0.72),
			0.4,
			0.0
		],  # Late morning
		[
			0.45,
			Color(0.18, 0.42, 0.82),
			Color(0.72, 0.82, 0.92),
			Color(0.95, 0.95, 0.9),
			Color(0.6, 0.7, 0.88),
			Color(1.0, 0.97, 0.9),
			Color(1.0, 1.0, 1.0),
			Color(0.62, 0.66, 0.74),
			0.35,
			0.0
		],  # Midday
		[
			0.8,
			Color(0.22, 0.42, 0.75),
			Color(0.88, 0.82, 0.7),
			Color(1.0, 0.85, 0.6),
			Color(0.6, 0.65, 0.8),
			Color(1.0, 0.85, 0.65),
			Color(1.0, 0.93, 0.82),
			Color(0.6, 0.6, 0.68),
			0.4,
			0.0
		],  # Afternoon
		[
			1.0,
			Color(0.3, 0.38, 0.62),
			Color(0.98, 0.68, 0.4),
			Color(1.0, 0.6, 0.25),
			Color(0.55, 0.5, 0.65),
			Color(1.0, 0.6, 0.3),
			Color(1.0, 0.75, 0.5),
			Color(0.5, 0.45, 0.55),
			0.45,
			0.0
		],  # Golden hour
		[
			1.45,
			Color(0.2, 0.2, 0.4),
			Color(0.95, 0.42, 0.22),
			Color(1.0, 0.35, 0.12),
			Color(0.55, 0.35, 0.5),
			Color(1.0, 0.4, 0.15),
			Color(1.0, 0.45, 0.3),
			Color(0.35, 0.25, 0.35),
			0.45,
			0.0
		],  # Sunset
		[
			1.75,
			Color(0.07, 0.08, 0.2),
			Color(0.45, 0.18, 0.18),
			Color(0.6, 0.2, 0.12),
			Color(0.2, 0.15, 0.28),
			Color(0.8, 0.25, 0.1),
			Color(0.5, 0.2, 0.2),
			Color(0.12, 0.1, 0.15),
			0.45,
			0.3
		],  # Afterglow
		[
			2.0,
			Color(0.02, 0.025, 0.06),
			Color(0.06, 0.06, 0.1),
			Color(0.08, 0.06, 0.1),
			Color(0.04, 0.04, 0.08),
			Color(0.3, 0.1, 0.05),
			Color(0.12, 0.13, 0.18),
			Color(0.03, 0.03, 0.05),
			0.45,
			0.8
		],  # Nightfall
		[
			2.5,
			Color(0.008, 0.01, 0.025),
			Color(0.035, 0.04, 0.06),
			Color(0.035, 0.04, 0.06),
			Color(0.035, 0.04, 0.06),
			Color(0.2, 0.1, 0.05),
			Color(0.09, 0.1, 0.14),
			Color(0.02, 0.02, 0.035),
			0.5,
			1.0
		],  # Midnight
		[
			2.85,
			Color(0.01, 0.012, 0.03),
			Color(0.05, 0.05, 0.08),
			Color(0.08, 0.06, 0.09),
			Color(0.04, 0.045, 0.07),
			Color(0.3, 0.15, 0.1),
			Color(0.1, 0.1, 0.14),
			Color(0.025, 0.025, 0.04),
			0.65,
			0.9
		],  # Small hours, clouding over
		[
			3.0,
			Color(0.02, 0.03, 0.08),
			Color(0.12, 0.12, 0.2),
			Color(0.3, 0.18, 0.18),
			Color(0.06, 0.07, 0.12),
			Color(0.8, 0.4, 0.3),
			Color(0.2, 0.18, 0.24),
			Color(0.05, 0.05, 0.08),
			0.55,
			0.5
		],  # Before dawn
		[
			3.5,
			Color(0.2, 0.3, 0.55),
			Color(0.95, 0.6, 0.55),
			Color(1.0, 0.55, 0.4),
			Color(0.45, 0.45, 0.65),
			Color(1.0, 0.6, 0.4),
			Color(1.0, 0.7, 0.6),
			Color(0.45, 0.42, 0.55),
			0.45,
			0.05
		],  # Sunrise
		[
			4.0,
			Color(0.32, 0.48, 0.75),
			Color(0.98, 0.78, 0.62),
			Color(1.0, 0.7, 0.4),
			Color(0.55, 0.6, 0.78),
			Color(1.0, 0.75, 0.5),
			Color(1.0, 0.86, 0.72),
			Color(0.55, 0.55, 0.65),
			0.45,
			0.0
		],  # Morning again
	]
	const UNIFORMS := [
		"zenith_color",
		"horizon_color",
		"glow_color",
		"shadow_color",
		"sun_color",
		"cloud_lit",
		"cloud_shade",
		"cloud_cover",
		"stars"
	]
	const DAWN_SECONDS := 8.0  ## How long the last dawn takes to break once the game ends.

	var _sun := DirectionalLight3D.new()
	var _moon := DirectionalLight3D.new()
	var _environment := Environment.new()
	var _sky := ShaderMaterial.new()
	var _dawn := 0.0

	func _init(parent: Node3D) -> void:
		_sky.shader = load("res://assets/shaders/sky.gdshader")
		var sky := Sky.new()
		sky.sky_material = _sky
		# Spread each redraw of the sky's light over a few frames: it changes slowly.
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		_environment.background_mode = Environment.BG_SKY
		_environment.sky = sky
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		_environment.fog_enabled = true
		# The sky fades to the fog colour at its own horizon; fogging it hid the stars.
		_environment.fog_sky_affect = 0.0
		var world := WorldEnvironment.new()
		world.environment = _environment
		parent.add_child(world)
		_sun.shadow_enabled = true
		_sun.directional_shadow_max_distance = 80.0
		parent.add_child(_sun)
		_moon.light_color = Color(0.55, 0.62, 0.85)
		_moon.shadow_enabled = true
		parent.add_child(_moon)

	## How far through the day, dusk and night (each 0..1); ending is the last dawn,
	## which breaks over DAWN_SECONDS. clock (seconds) turns the stars and moves
	## the clouds. Through dusk it gets dark, with a weak moon and fog closing in.
	func apply(
		day: float, dusk: float, night: float, ending: bool, clock: float, delta: float
	) -> void:
		if ending:
			_dawn = minf(_dawn + delta / DAWN_SECONDS, 1.0)
		var s := day
		var sun_up := _path([4.0, 20.0, 58.0, 10.0], [0.0, 0.1, 0.4, 1.0], day)
		var sun_yaw := lerpf(60.0, -35.0, day)
		var moon_up := -10.0
		var moon_yaw := 135.0
		if ending:
			s = 3.0 + _dawn
			sun_up = lerpf(-6.0, 8.0, _dawn)
			sun_yaw = 60.0
			moon_up = lerpf(15.0, 5.0, _dawn)
			moon_yaw = 260.0
		elif night > 0.0:
			s = 2.0 + night
			sun_up = _path([-12.0, -40.0, -6.0], [0.0, 0.5, 1.0], night)
			sun_yaw = lerpf(-45.0, -300.0, night)  # Round under the farm to the east.
			moon_up = _path([8.0, 55.0, 15.0], [0.0, 0.5, 1.0], night)
			moon_yaw = lerpf(135.0, 260.0, night)
		elif dusk > 0.0:
			s = 1.0 + dusk
			sun_up = _path([10.0, 0.0, -12.0], [0.0, 0.55, 1.0], dusk)
			sun_yaw = lerpf(-35.0, -45.0, dusk)
			moon_up = lerpf(-5.0, 8.0, dusk)  # Rising opposite the sunset.
		var dark := clampf(dusk + (1.0 if night > 0.0 else 0.0), 0.0, 1.0) - _dawn

		var palette := _palette(s)
		for i in UNIFORMS.size():
			_sky.set_shader_parameter(UNIFORMS[i], palette[i])
		_sky.set_shader_parameter("sun_dir", _toward(sun_up, sun_yaw))
		_sky.set_shader_parameter("moon_dir", _toward(moon_up, moon_yaw))
		_sky.set_shader_parameter("moon_visible", dark)
		_sky.set_shader_parameter("star_turn", clock * 0.0006)
		_sky.set_shader_parameter("twinkle", clock)
		_sky.set_shader_parameter("cloud_drift", Vector2(clock * 0.004, clock * 0.0015))

		_sun.rotation = Vector3(deg_to_rad(-sun_up), deg_to_rad(sun_yaw), 0)
		_sun.light_color = palette[4]
		var strength := 1.0 if s >= 3.0 else lerpf(1.3, 0.75, clampf(s, 0.0, 1.0))
		_sun.light_energy = strength * smoothstep(-2.0, 8.0, sun_up)
		_sun.visible = _sun.light_energy > 0.01
		# Kept above 10 degrees so a low moon doesn't throw shadows across the whole farm.
		_moon.rotation = Vector3(deg_to_rad(-maxf(moon_up, 10.0)), deg_to_rad(moon_yaw), 0)
		_moon.light_energy = 0.07 * dark
		_moon.visible = dark > 0.0
		_environment.ambient_light_energy = lerpf(1.0, 0.12, dark)
		_environment.fog_light_color = palette[1]
		_environment.fog_density = lerpf(0.004, 0.045, dark)

	## The colours and amounts in KEYS at s, in UNIFORMS order.
	func _palette(s: float) -> Array:
		var after := 1
		while after < KEYS.size() - 1 and KEYS[after][0] < s:
			after += 1
		var a: Array = KEYS[after - 1]
		var b: Array = KEYS[after]
		var t := clampf((s - a[0]) / (b[0] - a[0]), 0.0, 1.0)
		var blended := []
		for i in range(1, a.size()):
			blended.append(lerp(a[i], b[i], t))
		return blended

	## A value along a path through values at the given points (0..1).
	static func _path(values: Array, points: Array, t: float) -> float:
		for i in range(1, points.size()):
			if t <= points[i]:
				return lerpf(values[i - 1], values[i], inverse_lerp(points[i - 1], points[i], t))
		return values[-1]

	## The direction toward a light raised up degrees, turned yaw degrees.
	static func _toward(up: float, yaw: float) -> Vector3:
		return Basis.from_euler(Vector3(deg_to_rad(-up), deg_to_rad(yaw), 0)).z
