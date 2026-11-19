class_name BreakableBlock
extends Node3D

@export var block_size: Vector3 = Vector3(2.8, 2.8, 2.8)
@export var block_color: Color = Color("f97316")
@export var respawn_seconds: float = 4.5

var _body: StaticBody3D
var _top_smash_area: Area3D
var _broken: bool = false
var _respawn_timer: float = 0.0

func _ready() -> void:
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

func reset_block() -> void:
	_broken = false
	_respawn_timer = 0.0
	_body.visible = true
	_body.collision_layer = 1
	_body.collision_mask = 1

func _physics_process(delta: float) -> void:
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