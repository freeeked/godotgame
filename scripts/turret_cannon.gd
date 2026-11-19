@tool
class_name TurretCannon
extends Node3D

@export_group("Aim & Power")
@export_range(-180.0, 180.0, 0.5) var yaw_deg: float = 155.0:
	set(value):
		yaw_deg = value
		rotation_degrees.y = yaw_deg
		_rebuild_preview_arc()

@export_range(5.0, 85.0, 0.5) var pitch_deg: float = 38.0:
	set(value):
		pitch_deg = value
		if _barrel_pivot != null:
			_barrel_pivot.rotation.x = -deg_to_rad(pitch_deg)
		_rebuild_preview_arc()

@export_range(5.0, 100.0, 0.5) var launch_speed: float = 32.0:
	set(value):
		launch_speed = value
		_rebuild_preview_arc()

@export var charge_time: float = 0.36
@export var trigger_radius: float = 2.0

@export_group("Trajectory Preview")
@export var show_editor_arc: bool = true:
	set(value):
		show_editor_arc = value
		_rebuild_preview_arc()
@export var show_arc_in_game: bool = false:
	set(value):
		show_arc_in_game = value
		_rebuild_preview_arc()
@export var preview_gravity: float = 28.0:
	set(value):
		preview_gravity = value
		_rebuild_preview_arc()
@export var preview_steps: int = 28:
	set(value):
		preview_steps = maxi(6, value)
		_rebuild_preview_arc()
@export var preview_time_step: float = 0.08:
	set(value):
		preview_time_step = maxf(0.02, value)
		_rebuild_preview_arc()

var _barrel_pivot: Node3D
var _arc_root: Node3D
var _recoil_offset: float = 0.0

var _stack_cooldown: float = 0.0
var _stack_riding: bool = false
var _stack_timer: float = 0.0

var _single_rides: Array[Dictionary] = []
var _single_cooldowns: Dictionary = {}

func _ready() -> void:
	set_notify_transform(true)
	for child: Node in get_children():
		child.queue_free()

	# Keep whatever rotation was set via the 3D gizmo in the scene
	yaw_deg = rotation_degrees.y
	_build_cannon_meshes()
	_rebuild_preview_arc()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if not is_equal_approx(yaw_deg, rotation_degrees.y):
			yaw_deg = rotation_degrees.y

func _build_cannon_meshes() -> void:
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

	var wheel_cyl: CylinderMesh = CylinderMesh.new()
	wheel_cyl.top_radius = 0.62
	wheel_cyl.bottom_radius = 0.62
	wheel_cyl.height = 0.32
	for side: float in [-1.1, 1.1]:
		var wheel: MeshInstance3D = MeshInstance3D.new()
		wheel.mesh = wheel_cyl
		wheel.material_override = iron_mat
		wheel.rotation.z = PI * 0.5
		wheel.position = Vector3(side, 0.62, 0.2)
		add_child(wheel)

	# Barrel points along local +Z, pitched upward by -pitch_deg around X
	_barrel_pivot = Node3D.new()
	_barrel_pivot.position = Vector3(0.0, 1.15, 0.0)
	_barrel_pivot.rotation.x = -deg_to_rad(pitch_deg)
	add_child(_barrel_pivot)

	var breech: MeshInstance3D = MeshInstance3D.new()
	var breech_sphere: SphereMesh = SphereMesh.new()
	breech_sphere.radius = 1.02
	breech_sphere.height = 2.04
	breech.mesh = breech_sphere
	breech.material_override = iron_mat
	breech.position = Vector3(0.0, 0.0, -0.55)
	_barrel_pivot.add_child(breech)

	var barrel_mesh: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.82
	cyl.bottom_radius = 0.96
	cyl.height = 2.3
	barrel_mesh.mesh = cyl
	barrel_mesh.material_override = iron_mat
	barrel_mesh.rotation.x = PI * 0.5
	barrel_mesh.position = Vector3(0.0, 0.0, 0.65)
	_barrel_pivot.add_child(barrel_mesh)

	# Muzzle lip ring so you can clearly see which end fires
	var lip_mesh: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.68
	torus.outer_radius = 0.96
	lip_mesh.mesh = torus
	lip_mesh.material_override = iron_mat
	lip_mesh.rotation.x = PI * 0.5
	lip_mesh.position = Vector3(0.0, 0.0, 1.8)
	_barrel_pivot.add_child(lip_mesh)

func get_local_launch_dir() -> Vector3:
	var pitch_rad: float = deg_to_rad(pitch_deg)
	return Vector3(0.0, sin(pitch_rad), cos(pitch_rad)).normalized()

func get_local_muzzle_pos() -> Vector3:
	return Vector3(0.0, 1.15, 0.0) + get_local_launch_dir() * 2.1

func get_world_launch_velocity() -> Vector3:
	var world_dir: Vector3 = (global_transform.basis * get_local_launch_dir()).normalized()
	return world_dir * launch_speed

func get_world_muzzle_pos() -> Vector3:
	return global_transform * get_local_muzzle_pos()

func _rebuild_preview_arc() -> void:
	if _arc_root != null and is_instance_valid(_arc_root):
		_arc_root.queue_free()
		_arc_root = null

	var should_show: bool = show_editor_arc if Engine.is_editor_hint() else show_arc_in_game
	if not should_show:
		return

	_arc_root = Node3D.new()
	add_child(_arc_root)

	var arc_mat: StandardMaterial3D = StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var start_local: Vector3 = get_local_muzzle_pos()
	var v0_local: Vector3 = get_local_launch_dir() * launch_speed
	var grav: float = preview_gravity
	var landing_local: Vector3 = start_local

	for i: int in range(preview_steps):
		var t0: float = float(i) * preview_time_step
		var t1: float = float(i + 1) * preview_time_step
		var p0: Vector3 = start_local + v0_local * t0 + Vector3(0.0, -0.5 * grav * t0 * t0, 0.0)
		var p1: Vector3 = start_local + v0_local * t1 + Vector3(0.0, -0.5 * grav * t1 * t1, 0.0)

		# Stop arc when it hits the floor plane (local y <= 0) after rising
		if i > 1 and p1.y <= 0.0:
			var denom: float = p0.y - p1.y
			var frac: float = clampf(p0.y / denom, 0.0, 1.0) if denom > 0.0001 else 1.0
			p1 = p0.lerp(p1, frac)
			_add_dash_segment(p0, p1, arc_mat)
			landing_local = p1
			break

		landing_local = p1
		# Draw dashed segments (every segment slightly shortened for clean white dashes)
		var dash_end: Vector3 = p0.lerp(p1, 0.68)
		_add_dash_segment(p0, dash_end, arc_mat)

	# Landing marker ring at the end of the arc
	var target_ring: MeshInstance3D = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.75
	ring_mesh.outer_radius = 1.05
	target_ring.mesh = ring_mesh
	target_ring.material_override = arc_mat
	target_ring.position = landing_local + Vector3(0.0, 0.05, 0.0)
	_arc_root.add_child(target_ring)

func _add_dash_segment(a: Vector3, b: Vector3, mat: StandardMaterial3D) -> void:
	var seg_len: float = a.distance_to(b)
	if seg_len < 0.02:
		return
	var dash: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = seg_len
	dash.mesh = cyl
	dash.material_override = mat
	dash.position = (a + b) * 0.5
	var dir: Vector3 = (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		dash.quaternion = Quaternion(Vector3.UP, dir)
	_arc_root.add_child(dash)

func reset_cannon() -> void:
	_stack_cooldown = 0.0
	_stack_riding = false
	_stack_timer = 0.0
	_single_rides.clear()
	_single_cooldowns.clear()
	_recoil_offset = 0.0
	if _barrel_pivot != null:
		_barrel_pivot.position.z = 0.0
		_barrel_pivot.scale = Vector3.ONE

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_stack_cooldown = maxf(0.0, _stack_cooldown - delta)
	var expired_keys: Array = []
	for key: Variant in _single_cooldowns.keys():
		var rem: float = float(_single_cooldowns[key]) - delta
		if rem <= 0.0:
			expired_keys.append(key)
		else:
			_single_cooldowns[key] = rem
	for key: Variant in expired_keys:
		_single_cooldowns.erase(key)

	if _barrel_pivot != null:
		_recoil_offset = lerpf(_recoil_offset, 0.0, 1.0 - exp(-14.0 * delta))
		_barrel_pivot.position.z = -_recoil_offset

	var player: Node = get_tree().root.find_child("PlayerStack", true, false)
	if player == null:
		return

	var sfx: SoundEngine = get_tree().root.find_child("SoundEngine", true, false) as SoundEngine
	var chamber_world: Vector3 = global_position + Vector3(0.0, 1.15, 0.0)
	var trigger_center: Vector3 = global_transform * (Vector3(0.0, 1.15, 0.0) + get_local_launch_dir() * 0.85)

	# 1. Advance active stack charge/fire
	if _stack_riding:
		_stack_timer += delta
		var raw_t: float = minf(1.0, _stack_timer / charge_time)
		var swell: float = 1.0 + sin(raw_t * PI) * 0.18
		_barrel_pivot.scale = Vector3(swell, swell, 1.0 - sin(raw_t * PI) * 0.12)

		if player.has_method("hold_stack_at"):
			player.call("hold_stack_at", chamber_world, 0.55)

		if raw_t >= 1.0:
			_barrel_pivot.scale = Vector3.ONE
			_recoil_offset = 0.75
			_stack_riding = false
			_stack_cooldown = 0.75

			var muzzle_world: Vector3 = get_world_muzzle_pos()
			var launch_vel: Vector3 = get_world_launch_velocity()
			var launch_dir: Vector3 = launch_vel.normalized()

			if player.has_method("launch_stack_from_cannon"):
				player.call("launch_stack_from_cannon", muzzle_world, launch_dir, launch_vel)
			if sfx != null:
				sfx.play(&"cannon_fire", 1.0)
	elif _stack_cooldown <= 0.0 and player.has_method("get_active_blob_positions"):
		var is_ext: bool = bool(player.call("is_externally_controlled")) if player.has_method("is_externally_controlled") else false
		if not is_ext:
			var positions: Array = player.call("get_active_blob_positions")
			for pos_v: Variant in positions:
				var pos: Vector3 = pos_v as Vector3
				if pos.distance_to(trigger_center) <= trigger_radius:
					_stack_riding = true
					_stack_timer = 0.0
					if player.has_method("set_external_control"):
						player.call("set_external_control", true)
					if sfx != null:
						sfx.play(&"cannon_load", 0.95)
					break

	# 2. Advance individual ejected blob rides
	for i: int in range(_single_rides.size() - 1, -1, -1):
		var ride: Dictionary = _single_rides[i]
		ride["timer"] = float(ride["timer"]) + delta
		var raw_t: float = minf(1.0, float(ride["timer"]) / (charge_time * 0.85))
		var blob: Node3D = ride["blob"] as Node3D
		if is_instance_valid(blob):
			blob.global_position = chamber_world
			blob.scale = Vector3.ONE * 0.55

		if raw_t >= 1.0:
			_recoil_offset = 0.65
			_single_cooldowns[ride["id"]] = 0.75
			_single_rides.remove_at(i)
			if is_instance_valid(blob) and player.has_method("launch_ejected_blob"):
				var muzzle_world: Vector3 = get_world_muzzle_pos()
				var launch_vel: Vector3 = get_world_launch_velocity() * 1.08
				blob.scale = Vector3.ONE
				player.call("launch_ejected_blob", blob, muzzle_world, launch_vel)
			if sfx != null:
				sfx.play(&"cannon_fire", 0.9, 1.15)

	# 3. Check ejected blobs entering the trigger
	if player.has_method("get_ejected_blob_nodes"):
		var ejected: Array = player.call("get_ejected_blob_nodes")
		for ej_v: Variant in ejected:
			var ej: Node3D = ej_v as Node3D
			if not is_instance_valid(ej):
				continue
			var id: int = ej.get_instance_id()
			if _single_cooldowns.has(id):
				continue
			var already_riding: bool = false
			for r: Dictionary in _single_rides:
				if int(r["id"]) == id:
					already_riding = true
					break
			if already_riding:
				continue
			if ej.global_position.distance_to(trigger_center) <= trigger_radius:
				if player.has_method("lock_ejected_blob"):
					player.call("lock_ejected_blob", ej, true)
				_single_rides.append({
					"id": id,
					"blob": ej,
					"timer": 0.0,
				})
				if sfx != null:
					sfx.play(&"cannon_load", 0.85, 1.15)
