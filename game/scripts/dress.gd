class_name Dress
extends RefCounted
## Loads the models made in Blender (tools/blender/models.py, in assets/models)
## and dresses them in the textures baked there (tools/blender/textures.py, in
## assets/textures; docs/models.md). Each imported material is swapped for one
## using the texture its name picks, the name up to any "+", tinted by its
## colour: "planks_red", "metal_paint+generator" and so on. "plain+..." is a
## flat colour and "glow+..." emits. The textures tile, projected in each
## model's own space (triplanar), or by UV for meshes made with UVs (corn).

const MODELS := "res://assets/models/"
const TEXTURES := "res://assets/textures/"
const TWO_SIDED: Array[String] = ["leaf", "needles"]  ## Thin leaves and boughs.

static var _catalogue := {}  ## textures.json: tile size, roughness, metal, mapping.
static var _materials := {}


## A model from assets/models by name ("barn"), dressed. Its origin and facing
## are as models.py made them: standing on the origin, front toward -Z.
static func model(model_name: String) -> Node3D:
	var root := (load(MODELS + model_name + ".glb") as PackedScene).instantiate() as Node3D
	apply(root)
	return root


## A model's mesh, joined into one, with its surfaces dressed on the mesh
## itself: for a MultiMesh, which draws a mesh's own materials. With
## instance_colours, each instance's colour tints it.
static func mesh(model_name: String, instance_colours := false) -> Mesh:
	var root := (load(MODELS + model_name + ".glb") as PackedScene).instantiate() as Node3D
	var instance := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source_mesh := instance.mesh
	var dressed := ArrayMesh.new()
	for i in source_mesh.get_surface_count():
		var arrays := source_mesh.surface_get_arrays(i)
		if instance_colours:
			# A MultiMesh tints by instance colour only a mesh with vertex
			# colours, and the glTF has none: give it white ones.
			var white := PackedColorArray()
			white.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			white.fill(Color.WHITE)
			arrays[Mesh.ARRAY_COLOR] = white
		dressed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var source := source_mesh.surface_get_material(i) as BaseMaterial3D
		if source:
			dressed.surface_set_material(i, _dressed(source, instance_colours))
	root.free()
	return dressed


## Swaps every imported material under node for its dressed one.
static func apply(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		for i in instance.mesh.get_surface_count():
			var source := instance.mesh.surface_get_material(i) as BaseMaterial3D
			if source:
				instance.set_surface_override_material(i, _dressed(source))


## A texture's material, tinted. world projects it in world space, for ground
## and anything built in code from boxes (a box's own space would stretch it).
## roughness and metal below 0 take the texture's own.
static func material(
	texture: String,
	tint := Color.WHITE,
	world := false,
	roughness := -1.0,
	metal := -1.0,
	instance_colours := false
) -> StandardMaterial3D:
	var key := [texture, tint, world, roughness, metal, instance_colours]
	if _materials.has(key):
		return _materials[key]
	var info := _info(texture)
	var made := StandardMaterial3D.new()
	made.albedo_texture = load(TEXTURES + texture + ".jpg")
	made.albedo_color = tint
	made.normal_enabled = true
	made.normal_texture = load(TEXTURES + texture + "_n.jpg")
	made.roughness = roughness if roughness >= 0.0 else float(info.get("roughness", 0.8))
	made.metallic = metal if metal >= 0.0 else float(info.get("metal", 0.0))
	made.vertex_color_use_as_albedo = instance_colours
	var tile := float(info.get("size", 1.0))
	if info.get("mapping", "triplanar") == "uv":
		made.uv1_scale = Vector3(1.0, 1.0 / tile, 1.0)  # u across a leaf, v metres along it.
	else:
		made.uv1_triplanar = true
		made.uv1_world_triplanar = world
		made.uv1_scale = Vector3.ONE / tile
	if texture in TWO_SIDED:
		made.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = made
	return made


## Whether a texture was baked (its name is in textures.json).
static func has_texture(texture: String) -> bool:
	return not _info(texture).is_empty()


static func _dressed(source: BaseMaterial3D, instance_colours := false) -> Material:
	var texture := source.resource_name.get_slice("+", 0)
	var colour := source.albedo_color
	match texture:
		"plain":
			return _flat(colour, source.roughness, false)
		"glow":
			return _flat(colour, source.roughness, true)
	if not has_texture(texture):
		push_warning("Dress: no texture %s for material %s" % [texture, source.resource_name])
		return source
	return material(texture, colour, false, source.roughness, source.metallic, instance_colours)


static func _flat(colour: Color, roughness: float, glow: bool) -> StandardMaterial3D:
	var key := ["flat", colour, roughness, glow]
	if not _materials.has(key):
		var flat := StandardMaterial3D.new()
		flat.albedo_color = colour
		flat.roughness = roughness
		if glow:
			flat.emission_enabled = true
			flat.emission = colour
			flat.emission_energy_multiplier = 0.6
		_materials[key] = flat
	return _materials[key]


static func _info(texture: String) -> Dictionary:
	if _catalogue.is_empty():
		var text := FileAccess.get_file_as_string(TEXTURES + "textures.json")
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_catalogue = parsed
	return _catalogue.get(texture, {})
