@tool
class_name ScalePlatform
extends Node3D

@export_group("Platform Dimensions")
@export var deck_size: Vector3 = Vector3(5.2, 0.65, 5.2):
	set(value):
		deck_size = Vector3(maxf(0.5, value.x), maxf(0.1, value.y), maxf(0.5, value.z))
		_rebuild()

@export var stem_height: float = 7.0:
	set(value):
		stem_height = maxf(0.5, value)
		_rebuild()

@export var deck_color: Color = Color("2dd4bf"):
	set(value):
		deck_color = value
		_rebuild()

@export_group("Weight & Sink")
@export var sink_per_blob: float = 0.85
@export var max_sink: float = 2.55:
	set(value):
		max_sink = maxf(0.0, value)
		_rebuild()

@export_group("Editor Guides")
@export var show_editor_guides: bool = true:
	set(value):
		show_editor_guides = value
		_rebuild()

var _deck_body: AnimatableBody3D
var _top_sensor: Area3D
var _rest_y: float = 0.0
var _current_y: float = 0.0
var _creak_timer: float = 0.0
var _last_count: int = 0

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_rest_y = -deck_size.y * 0.5
	_current_y = _rest_y

	_deck_body = AnimatableBody3D.new()
	_deck_body.sync_to_physics = true
	_deck_body.position = Vector3(0.0, _rest_y, 0.0)
	add_child(_deck_body)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = deck_size
	mesh_inst.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = deck_color
	mat.roughness = 0.45
	mat.metallic = 0.15
	mesh_inst.material_override = mat
	_deck_body.add_child(mesh_inst)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = deck_size
	col.shape = shape
	_deck_body.add_child(col)

	var stem_mesh: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.52
	cyl.height = stem_height
	stem_mesh.mesh = cyl
	var stem_mat: StandardMaterial3D = StandardMaterial3D.new()
	stem_mat.albedo_color = Color("334155")
	stem_mat.metallic = 0.5
	stem_mesh.material_override = stem_mat
	stem_mesh.position = Vector3(0.0, -deck_size.y * 0.5 - stem_height * 0.5, 0.0)
	_deck_body.add_child(stem_mesh)

	_top_sensor = Area3D.new()
	_top_sensor.position = Vector3(0.0, deck_size.y * 0.5 + 0.35, 0.0)
	_top_sensor.monitoring = true
	_top_sensor.monitorable = false
	var s_col: CollisionShape3D = CollisionShape3D.new()
	var s_shape: BoxShape3D = BoxShape3D.new()
	s_shape.size = Vector3(deck_size.x * 0.92, 0.7, deck_size.z * 0.92)
	s_col.shape = s_shape
	_top_sensor.add_child(s_col)
	_deck_body.add_child(_top_sensor)

	if Engine.is_editor_hint() and show_editor_guides and max_sink > 0.01:
		var guide_mat: StandardMaterial3D = StandardMaterial3D.new()
		guide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		guide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		guide_mat.albedo_color = Color(deck_color.r, deck_color.g, deck_color.b, 0.28)

		var ghost_deck: MeshInstance3D = MeshInstance3D.new()
		var ghost_box: BoxMesh = BoxMesh.new()
		ghost_box.size = deck_size
		ghost_deck.mesh = ghost_box
		ghost_deck.material_override = guide_mat
		ghost_deck.position = Vector3(0.0, _rest_y - max_sink, 0.0)
		add_child(ghost_deck)

		# Vertical corner drop guides
		var corner_offsets: Array[Vector2] = [
			Vector2(-deck_size.x * 0.48, -deck_size.z * 0.48),
			Vector2(deck_size.x * 0.48, -deck_size.z * 0.48),
			Vector2(-deck_size.x * 0.48, deck_size.z * 0.48),
			Vector2(deck_size.x * 0.48, deck_size.z * 0.48),
		]
		var line_cyl: CylinderMesh = CylinderMesh.new()
		line_cyl.top_radius = 0.035
		line_cyl.bottom_radius = 0.035
		line_cyl.height = max_sink
		for c: Vector2 in corner_offsets:
			var bar: MeshInstance3D = MeshInstance3D.new()
			bar.mesh = line_cyl
			bar.material_override = guide_mat
			bar.position = Vector3(c.x, -max_sink * 0.5, c.y)
			add_child(bar)

func reset_scale() -> void:
	_current_y = _rest_y
	_last_count = 0
	_creak_timer = 0.0
	if _deck_body != null:
		_deck_body.position.y = _rest_y

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _top_sensor == null or _deck_body == null:
		return

	var count: int = _top_sensor.get_overlapping_bodies().size() + _top_sensor.get_overlapping_areas().size()
	var sfx: SoundEngine = get_tree().root.find_child("SoundEngine", true, false) as SoundEngine

	if count != _last_count:
		if sfx != null:
			sfx.play(&"scale_settle", 0.72, 1.0 - float(count) * 0.08 if count > _last_count else 1.1)
		_last_count = count

	var sink: float = minf(max_sink, float(count) * sink_per_blob)
	var target_y: float = _rest_y - sink
	var disp: float = target_y - _current_y
	var max_speed: float = 2.15 if disp < 0.0 else 1.75
	var step: float = clampf(disp * 3.0, -max_speed * delta, max_speed * delta)

	if absf(step) > 0.0001:
		_current_y += step
		_deck_body.position.y = _current_y
		_creak_timer -= delta
		if _creak_timer <= 0.0 and sfx != null:
			sfx.play(&"scale_creak", 0.42, 0.95)
			_creak_timer = 0.22