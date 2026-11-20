class_name ClayWorldStyler
extends Node

@export var clay_shader: Shader = preload("res://shaders/clay_surface.gdshader")
@export var enabled: bool = true
@export_range(0.0, 24.0, 1.0) var stop_motion_fps: float = 10.0
@export_range(0.0, 0.04, 0.002) var boil_wobble: float = 0.006

var _converted_ids: Dictionary = {}

func _ready() -> void:
	if not enabled or clay_shader == null:
		return

	get_tree().node_added.connect(_on_node_added)
	await get_tree().process_frame
	apply_clay_to_tree(get_tree().current_scene)

func _on_node_added(node: Node) -> void:
	if not enabled or clay_shader == null:
		return
	if node is GeometryInstance3D:
		# Defer 1 frame so procedural builders finish setting material_override / CSG material
		_convert_deferred.call_deferred(node)

func _convert_deferred(node: Node) -> void:
	if is_instance_valid(node):
		apply_clay_to_tree(node)

func apply_clay_to_tree(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D or root is CSGShape3D:
		_convert_geometry(root as GeometryInstance3D)
	for child: Node in root.get_children():
		apply_clay_to_tree(child)

func _convert_geometry(geom: GeometryInstance3D) -> void:
	var id: int = geom.get_instance_id()
	if _converted_ids.has(id) or geom.material_override is ShaderMaterial:
		return

	var mat: Material = geom.material_override
	if mat == null:
		if geom is MeshInstance3D:
			var mi: MeshInstance3D = geom as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				mat = mi.get_active_material(0)
		elif geom is CSGShape3D:
			mat = geom.get("material") as Material

	var base_color: Color = Color("94a3b8") # Default floor/stone clay tone if no material was assigned
	var base_roughness: float = 0.65

	if mat is StandardMaterial3D:
		var std: StandardMaterial3D = mat as StandardMaterial3D
		# Skip translucent pneumatic tubes, unshaded editor guides, and tiny dark blob eyes
		if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return
		if std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return
		if std.albedo_color.v < 0.14:
			return

		base_color = std.albedo_color
		base_roughness = clampf(std.roughness + 0.15, 0.45, 0.85)
	elif mat != null:
		# Skip custom ShaderMaterials (such as reticle outlines or screen quads)
		return

	# Note: CSGCombiner3D is a container parent; only style leaf CSG primitives or standalone CSG shapes
	if geom is CSGCombiner3D:
		return

	var clay_mat: ShaderMaterial = ShaderMaterial.new()
	clay_mat.shader = clay_shader
	clay_mat.set_shader_parameter("albedo_color", base_color)
	clay_mat.set_shader_parameter("roughness", base_roughness)
	clay_mat.set_shader_parameter("stop_motion_fps", stop_motion_fps)
	# Keep vertex boil gentler on large architectural blocks so box corners don't separate
	var is_map_geo: bool = geom is CSGShape3D or geom.get_parent() is StaticBody3D
	clay_mat.set_shader_parameter("boil_wobble_amount", boil_wobble * (0.35 if is_map_geo else 1.5))

	geom.material_override = clay_mat
	_converted_ids[id] = true
