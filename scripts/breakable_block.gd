@tool
class_name BreakableBlock
extends Node3D

@export_group("Block Settings")
@export var block_size: Vector3 = Vector3(2.8, 2.8, 2.8):
	set(value):
		block_size = Vector3(maxf(0.4, value.x), maxf(0.4, value.y), maxf(0.4, value.z))
		_rebuild()

@export var block_color: Color = Color("f97316"):
	set(value):
		block_color = value
		_rebuild()

@export var respawn_seconds: float = 4.5

@export_group("Editor Guides")
@export var show_editor_guides: bool = true:
	set(value):
		show_editor_guides = value
		_rebuild()

var _body: StaticBody3D
var _top_smash_area: Area3D
var _broken: bool = false
var _respawn_timer: float = 0.0

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_body = StaticBody3D.new()
	add_child(_body)

	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = block_size
	mesh.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = block_color
	mat.roughness = 0.6
	mesh.material_override = mat
	_body.add_child(mesh)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = block_size
	col.shape = shape
	_body.add_child(col)

	_top_smash_area = Area3D.new()
	_top_smash_area.position = Vector3(0.0, block_size.y * 0.5 + 0.22, 0.0)
	_top_smash_area.monitoring = true
	_top_smash_area.monitorable = false
	var s_col: CollisionShape3D = CollisionShape3D.new()
	var s_shape: BoxShape3D = BoxShape3D.new()
	s_shape.size = Vector3(block_size.x * 1.05, 0.44, block_size.z * 1.05)
	s_col.shape = s_shape
	_top_smash_area.add_child(s_col)
	add_child(_top_smash_area)

	if Engine.is_editor_hint() and show_editor_guides:
		var top_cap: MeshInstance3D = MeshInstance3D.new()
		var cap_box: BoxMesh = BoxMesh.new()
		cap_box.size = Vector3(block_size.x * 1.02, 0.06, block_size.z * 1.02)
		top_cap.mesh = cap_box
		var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
		cap_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cap_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cap_mat.albedo_color = Color(1.0, 0.95, 0.75, 0.45)
		top_cap.material_override = cap_mat
		top_cap.position = Vector3(0.0, block_size.y * 0.5 + 0.04, 0.0)
		add_child(top_cap)

func reset_block() -> void:
	_broken = false
	_respawn_timer = 0.0
	if _body != null:
		_body.visible = true
		_body.collision_layer = 1
		_body.collision_mask = 1

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _top_smash_area == null or _body == null:
		return

	if _broken:
		if respawn_seconds > 0.0:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				reset_block()
		return

	for body: Node3D in _top_smash_area.get_overlapping_bodies():
		if body is CharacterBody3D:
			var cb: CharacterBody3D = body as CharacterBody3D
			if cb.velocity.y <= 0.5:
				_broken = true
				_respawn_timer = respawn_seconds
				_body.visible = false
				_body.collision_layer = 0
				_body.collision_mask = 0
				cb.velocity.y = maxf(cb.velocity.y, 9.5)
				var sfx: SoundEngine = get_tree().root.find_child("SoundEngine", true, false) as SoundEngine
				if sfx != null:
					sfx.play(&"block_crack", 0.9)
					sfx.play(&"block_break", 1.0)
				break