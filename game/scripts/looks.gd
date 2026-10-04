class_name Looks
extends RefCounted
## Placeholder models for the things game.gd keeps track of: tools, crops
## and traps, built from primitive meshes. Also the sky, sun and moon.

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
	"turnip":
	[
		["sphere", Vector3(0, 0.12, 0), Vector3(0.22, 0.2, 0.22), Color(0.88, 0.85, 0.9)],
		["sphere", Vector3(0, 0.12, 0.1), Vector3(0.2, 0.18, 0.2), Color(0.75, 0.45, 0.75)],
		["box", Vector3(0, 0.3, 0), Vector3(0.05, 0.2, 0.05), Color(0.3, 0.55, 0.2)],
	],
}
const METAL := Color(0.32, 0.3, 0.28)


static func item(parent: Node3D, kind: String) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	for part: Array in ITEM_PARTS[kind]:
		mesh(node, part[0], part[1], part[2], part[3])
	return node


## Rebuilds a plot's soil and turnips for its Game.Stage.
static func plot(node: Node3D, stage: int) -> void:
	_clear(node)
	var soil := Color(0.16, 0.1, 0.06) if stage == Game.Stage.GROWING else Color(0.22, 0.15, 0.09)
	mesh(node, "box", Vector3(0, 0.035, 0), Vector3(2.3, 0.02, 2.3), soil)
	if stage == Game.Stage.EMPTY:
		return
	var leaf := 0.35 if stage == Game.Stage.RIPE else 0.18
	for x in 3:
		for z in 3:
			var at := Vector3((x - 1) * 0.65, leaf / 2.0, (z - 1) * 0.65)
			mesh(node, "sphere", at, Vector3(leaf, leaf, leaf), Color(0.25, 0.55, 0.2))
			if stage == Game.Stage.RIPE:
				var top := at + Vector3(0.1, -leaf / 2.0 + 0.05, 0.1)
				mesh(node, "sphere", top, Vector3(0.14, 0.1, 0.14), Color(0.8, 0.5, 0.8))


## Rebuilds a trap for its Game.TrapState. An armed pit is husks over a hole,
## only a little paler than the dirt; an armed bear trap lies open and flat.
static func trap(node: Node3D, kind: String, state: int) -> void:
	_clear(node)
	if state == Game.TrapState.HIDDEN:
		return
	if kind == "pit":
		match state:
			Game.TrapState.ARMED:
				mesh(
					node,
					"box",
					Vector3(0, 0.02, 0),
					Vector3(1.1, 0.03, 1.0),
					Color(0.42, 0.36, 0.22)
				)
			Game.TrapState.SPRUNG:
				mesh(
					node,
					"cylinder",
					Vector3(0, 0.015, 0),
					Vector3(1, 0.01, 1),
					Color(0.02, 0.02, 0.01)
				)
			Game.TrapState.DISARMED:
				mesh(node, "sphere", Vector3.ZERO, Vector3(1.0, 0.18, 1.0), Color(0.3, 0.2, 0.12))
		return
	mesh(node, "torus", Vector3(0, 0.03, 0), Vector3(0.55, 0.3, 0.55), METAL)
	if state == Game.TrapState.ARMED:
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


static func _clear(node: Node3D) -> void:
	for child in node.get_children():
		child.queue_free()


## The sky, a sun and a moon, added under parent. apply() sets them for the time of day.
class Daylight:
	var _sun := DirectionalLight3D.new()
	var _moon := DirectionalLight3D.new()
	var _environment := Environment.new()
	var _sky := ProceduralSkyMaterial.new()

	func _init(parent: Node3D) -> void:
		var sky := Sky.new()
		sky.sky_material = _sky
		_environment.background_mode = Environment.BG_SKY
		_environment.sky = sky
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		_environment.fog_enabled = true
		var world := WorldEnvironment.new()
		world.environment = _environment
		parent.add_child(world)
		_sun.shadow_enabled = true
		_sun.directional_shadow_max_distance = 80.0
		parent.add_child(_sun)
		_moon.light_color = Color(0.55, 0.62, 0.85)
		_moon.rotation = Vector3(deg_to_rad(-50), deg_to_rad(140), 0)
		_moon.shadow_enabled = true
		parent.add_child(_moon)

	## Bright afternoon through the day (0..1), an orange dusk (0..1), then
	## dark with a weak moon and fog that closes in.
	func apply(day: float, dusk: float, night: bool) -> void:
		var dark := clampf(dusk + (1.0 if night else 0.0), 0.0, 1.0)
		_sun.rotation = Vector3(
			deg_to_rad(lerpf(-55.0, -12.0, day) + 10.0 * dusk), deg_to_rad(-35), 0
		)
		var evening := clampf(day * 1.4 - 0.4, 0.0, 1.0)
		_sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.5, 0.25), evening)
		_sun.light_energy = lerpf(lerpf(1.3, 0.7, day), 0.0, dusk)
		_sun.visible = _sun.light_energy > 0.01
		_moon.light_energy = 0.07 * dark
		_moon.visible = dark > 0.0
		var top := Color(0.3, 0.5, 0.8).lerp(Color(0.35, 0.3, 0.45), day)
		var horizon := Color(0.75, 0.8, 0.85).lerp(Color(0.95, 0.55, 0.3), day)
		_sky.sky_top_color = top.lerp(Color(0.01, 0.012, 0.025), dark)
		_sky.sky_horizon_color = horizon.lerp(Color(0.03, 0.035, 0.05), dark)
		_sky.ground_horizon_color = _sky.sky_horizon_color
		_sky.ground_bottom_color = Color(0.1, 0.1, 0.08).lerp(Color.BLACK, dark)
		_environment.ambient_light_energy = lerpf(1.0, 0.12, dark)
		_environment.fog_light_color = _sky.sky_horizon_color
		_environment.fog_density = lerpf(0.004, 0.045, dark)
		_environment.fog_sky_affect = dark  # Day fog greyed out the whole sky.
