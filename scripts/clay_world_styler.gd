class_name ClayWorldStyler
extends Node

@export var clay_shader: Shader = preload("res://shaders/clay_surface.gdshader")
@export var enabled: bool = true
@export_range(0.0, 24.0, 1.0) var stop_motion_fps: float = 10.0
@export_range(0.0, 0.04, 0.002) var boil_wobble: float = 0.012

var _converted_ids: Dictionary = {}

func _ready() -> void:
	if not enabled or clay_shader == null:
		return
	# Wait 1 physics/process frame so procedural contraptions & PlayerStack finish spawning
	await get_tree().process_frame
	apply_clay_to_tree(get_tree().current_scene)

func apply_clay_to_tree(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		_convert_mesh_instance(root as MeshInstance3D)
	for child: Node in root.get_children():
		apply_clay_to_tree(child)

func _convert_mesh_instance(mi: MeshInstance3D) -> void:
	var id: int = mi.get_instance_id()
	if _converted_ids.has(id):
		return

	var mat: Material = mi.material_override
	if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		mat = mi.get_active_material(0)

	if mat is StandardMaterial3D:
		var std: StandardMaterial3D = mat as StandardMaterial3D
		# Skip translucent glass tubes, unshaded editor guides, and tiny dark blob eyes
		if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return
		if std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return
		if std.albedo_color.v < 0.14:
			return

		var clay_mat: ShaderMaterial = ShaderMaterial.new()
		clay_mat.shader = clay_shader
		clay_mat.set_shader_parameter("albedo_color", std.albedo_color)
		clay_mat.set_shader_parameter("roughness", clampf(std.roughness + 0.15, 0.45, 0.85))
		clay_mat.set_shader_parameter("stop_motion_fps", stop_motion_fps)
		clay_mat.set_shader_parameter("boil_wobble_amount", boil_wobble)
		mi.material_override = clay_mat
		_converted_ids[id] = true
