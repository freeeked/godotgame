class_name PowerupItem
extends Node3D

enum PowerupType {
	PYRAMID = 0,
	BOMB = 1,
}

signal collected(powerup_type: PowerupType, collector: Node3D)

@export var powerup_type: PowerupType = PowerupType.PYRAMID
@export var tint_color: Color = Color("facc15")
@export var respawn_seconds: float = 4.0

var _visual_pivot: Node3D
var _area: Area3D
var _base_y: float = 1.15
var _collected: bool = false
var _respawn_timer: float = 0.0
var _elapsed: float = 0.0

func _ready() -> void:
	_visual_pivot = Node3D.new()
	_visual_pivot.position.y = _base_y
	add_child(_visual_pivot)

	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()

	if powerup_type == PowerupType.BOMB:
		var sphere := SphereMesh.new()
		sphere.radius = 0.56
		sphere.height = 1.12
		mesh_inst.mesh = sphere
		mat.albedo_color = Color("090d16")
		mat.roughness = 0.18
		mat.metallic = 0.45
		mat.emission_enabled = true
		mat.emission = Color("f97316")
		mat.emission_energy_multiplier = 0.35
	else:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.62
		cone.height = 1.05
		cone.radial_segments = 4
		mesh_inst.mesh = cone
		mat.albedo_color = tint_color
		mat.roughness = 0.25
		mat.metallic = 0.15
		mat.emission_enabled = true
		mat.emission = tint_color
		mat.emission_energy_multiplier = 0.45

	mesh_inst.material_override = mat
	_visual_pivot.add_child(mesh_inst)

	_area = Area3D.new()
	_area.position.y = _base_y
	_area.monitoring = true
	_area.monitorable = false
	_area.collision_mask = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.6, 1.5)
	col.shape = box
	_area.add_child(col)
	add_child(_area)

	_area.body_entered.connect(_on_body_entered)

func reset_powerup() -> void:
	_collected = false
	_respawn_timer = 0.0
	visible = true
	_area.set_deferred("monitoring", true)

func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	_collected = true
	_respawn_timer = respawn_seconds
	visible = false
	_area.set_deferred("monitoring", false)

	var sfx := get_tree().root.find_child("SoundEngine", true, false) as SoundEngine
	if sfx != null:
		sfx.play(&"recall", 1.0)

	collected.emit(powerup_type, body)

func _process(delta: float) -> void:
	_elapsed += delta
	if _collected:
		if respawn_seconds > 0.0:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				reset_powerup()
		return

	_visual_pivot.position.y = _base_y + sin(_elapsed * 3.2) * 0.18
	_visual_pivot.rotation.y = _elapsed * 2.0