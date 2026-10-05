extends Node3D
## Shows the Blender models side by side in daylight and saves a PNG, to check
## them without playing (docs/models.md). Opens a window briefly:
##   godot --path game res://tools/showcase.tscn -- --set=characters --out=shot.png
## Sets: characters (farmer and creature, front and back), props, plants.
## --close frames the heads.

const SETS := {
	"characters": [["farmer", 0.0], ["farmer", PI], ["creature", 0.0], ["creature", PI]],
	"props": [["generator", 0.4], ["drum", 0.0], ["pump", -0.6], ["crate", 0.3]],
	"plants": [["corn", 0.0], ["corn_far", 0.0], ["pine", 0.0]],
	"monsters": [["creature", PI], ["scarecrow", PI], ["boar", PI], ["husk", PI]],
	"monsters_back": [["creature", 0.0], ["scarecrow", 0.0], ["boar", 0.0], ["husk", 0.0]],
}
const GAP := {"characters": 1.4, "props": 1.8, "plants": 4.0, "monsters": 1.7, "monsters_back": 1.7}


func _ready() -> void:
	var which := "characters"
	var out := "showcase.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			which = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	plane.material = Dress.material("dirt", Color.WHITE, true)
	floor_mesh.mesh = plane
	add_child(floor_mesh)

	var shown: Array = SETS[which]
	var gap: float = GAP[which]
	var tallest := 0.0
	for i in shown.size():
		var model := Dress.model(shown[i][0])
		model.position.x = (i - (shown.size() - 1) / 2.0) * gap
		model.rotation.y = shown[i][1]
		add_child(model)
		for child in model.find_children("*", "MeshInstance3D", true, false):
			tallest = maxf(tallest, (child as MeshInstance3D).get_aabb().end.y)
	var camera := Camera3D.new()
	camera.fov = 35.0
	var width := shown.size() * gap
	var close := "--close" in OS.get_cmdline_user_args()
	var aim := Vector3(0, tallest * (0.88 if close else 0.5), 0)
	var back := 2.2 if close else maxf(width, tallest) * 1.6 + 1.0
	camera.position = aim + Vector3(0, tallest * 0.08, back)
	add_child(camera)
	camera.look_at(aim)
	camera.make_current()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("saved %s" % out)
	get_tree().quit()
