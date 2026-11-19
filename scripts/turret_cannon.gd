class_name TurretCannon
extends Node3D

@export var yaw_deg: float = 155.0
@export var pitch_deg: float = 38.0
@export var launch_speed: float = 44.0
@export var charge_time: float = 0.36

var _barrel_pivot: Node3D
var _trigger_area: Area3D
var _cooldown: float = 0.0
var _riding_body: Node3D = null
var _ride_timer: float = 0.0

func _ready() -> void:
	rotation.y = deg_to_rad(yaw_deg)

	var iron_mat: StandardMaterial3D = StandardMaterial3D.new()
	iron_mat.albedo_color = Color("0f172a")
	iron_mat.roughness = 0.35
	iron_mat.metallic = 0.55

	var carriage_mat: StandardMaterial3D = StandardMaterial3D.new()
	carriage_mat.albedo_color = Color("78350f")
	carriage_mat.roughness = 0.75

	var base_mesh: MeshInstance3D = MeshInstance3D.new()
	var base_box: BoxMesh = BoxMesh.new()
	base_box.size = Vector3(2.1, 0.7, 2.3)
	base_mesh.mesh = base_box
	base_mesh.material_override = carriage_mat
	base_mesh.position = Vector3(0.0, 0.45, 0.0)
	add_child(base_mesh)

	_barrel_pivot = Node3D.new()
	_barrel_pivot.position = Vector3(0.0, 1.15, 0.0)
	_barrel_pivot.rotation.x = -deg_to_rad(pitch_deg)
	add_child(_barrel_pivot)

	var barrel_mesh: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.82
	cyl.bottom_radius = 0.98
	cyl.height = 2.4
	barrel_mesh.mesh = cyl
	barrel_mesh.material_override = iron_mat
	barrel_mesh.rotation.x = PI * 0.5
	barrel_mesh.position = Vector3(0.0, 0.0, 0.65)
	_barrel_pivot.add_child(barrel_mesh)

	_trigger_area = Area3D.new()
	_trigger_area.position = Vector3(0.0, 0.0, 0.9)
	_trigger_area.monitoring = true
	_trigger_area.monitorable = false
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.5, 2.3, 2.5)
	col.shape = shape
	_trigger_area.add_child(col)
	_barrel_pivot.add_child(_trigger_area)

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var sfx: SoundEngine = get_tree().root.find_child("SoundEngine", true, false) as SoundEngine

	if _riding_body != null:
		_ride_timer += delta
		var chamber_pos: Vector3 = global_position + Vector3(0.0, 1.15, 0.0)
		_riding_body.global_position = chamber_pos

		if _ride_timer >= charge_time:
			var muzzle_pos: Vector3 = _barrel_pivot.global_transform * Vector3(0.0, 0.0, 2.15)
			var launch_dir: Vector3 = (-_barrel_pivot.global_transform.basis.z).normalized()
			_riding_body.global_position = muzzle_pos + launch_dir * 0.75
			if _riding_body is CharacterBody3D:
				(_riding_body as CharacterBody3D).velocity = launch_dir * launch_speed
			_riding_body = null
			_cooldown = 0.75
			if sfx != null:
				sfx.play(&"cannon_fire", 1.0)
		return

	if _cooldown <= 0.0:
		for body: Node3D in _trigger_area.get_overlapping_bodies():
			_riding_body = body
			_ride_timer = 0.0
			if sfx != null:
				sfx.play(&"cannon_load", 0.95)
			return
