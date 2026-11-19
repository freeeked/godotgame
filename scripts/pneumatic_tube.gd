class_name PneumaticTube
extends Node3D

@export var end_a_local: Vector3 = Vector3(10.5, 1.2, 14.5)
@export var elbow_local: Vector3 = Vector3(10.5, 7.5, 14.5)
@export var end_b_local: Vector3 = Vector3(4.5, 7.5, 14.5)
@export var exit_speed_a: float = 11.0
@export var exit_speed_b: float = 12.5
@export var tube_radius: float = 1.2
@export var travel_duration: float = 0.62

var _curve: Curve3D
var _area_a: Area3D
var _area_b: Area3D
var _cooldown_a: float = 0.0
var _cooldown_b: float = 0.0
var _riding_body: Node3D = null
var _ride_timer: float = 0.0
var _ride_forward: bool = true

func _ready() -> void:
	_curve = Curve3D.new()
	var p_a: Vector3 = end_a_local
	var p_el: Vector3 = elbow_local
	var p_b: Vector3 = end_b_local
	var d1: Vector3 = (p_el - p_a).normalized()
	var d2: Vector3 = (p_b - p_el).normalized()
	var fillet: float = minf(2.2, minf(p_a.distance_to(p_el) * 0.4, p_el.distance_to(p_b) * 0.4))

	_curve.add_point(p_a)
	_curve.add_point(p_el - d1 * fillet)
	_curve.add_point(p_el + d2 * fillet)
	_curve.add_point(p_b)

	_build_visual_tube()
	_area_a = _make_mouth_area(p_a, "MouthA")
	_area_b = _make_mouth_area(p_b, "MouthB")

func _build_visual_tube() -> void:
	var baked: PackedVector3Array = _curve.get_baked_points()
	if baked.size() < 2:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color("67e8f9")
	mat.emission_enabled = true
	mat.emission = Color("0891b2")
	mat.emission_energy_multiplier = 0.45
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.45

	for i: int in range(baked.size() - 1):
		var a: Vector3 = baked[i]
		var b: Vector3 = baked[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.01:
			continue
		var seg_mesh: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = tube_radius
		cyl.bottom_radius = tube_radius
		cyl.height = seg_len
		seg_mesh.mesh = cyl
		seg_mesh.material_override = mat
		seg_mesh.position = (a + b) * 0.5
		var dir: Vector3 = (b - a).normalized()
		if absf(dir.dot(Vector3.UP)) < 0.999:
			seg_mesh.quaternion = Quaternion(Vector3.UP, dir)
		add_child(seg_mesh)

func _make_mouth_area(pos: Vector3, label: String) -> Area3D:
	var area: Area3D = Area3D.new()
	area.name = label
	area.position = pos
	area.monitoring = true
	area.monitorable = false
	var col: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = tube_radius * 1.15
	col.shape = sphere
	area.add_child(col)
	add_child(area)
	return area

func _physics_process(delta: float) -> void:
	_cooldown_a = maxf(0.0, _cooldown_a - delta)
	_cooldown_b = maxf(0.0, _cooldown_b - delta)

	var sfx: SoundEngine = get_tree().root.find_child("SoundEngine", true, false) as SoundEngine

	if _riding_body != null:
		_ride_timer += delta
		var raw_t: float = minf(1.0, _ride_timer / travel_duration)
		var eased: float = smoothstep(0.0, 1.0, raw_t)
		var u: float = eased if _ride_forward else (1.0 - eased)
		var local_pt: Vector3 = _curve.sample_baked(u * _curve.get_baked_length(), true)
		_riding_body.global_position = global_transform * local_pt

		if raw_t >= 1.0:
			var exit_local: Vector3 = end_b_local if _ride_forward else end_a_local
			var dir_local: Vector3 = (end_b_local - elbow_local).normalized() if _ride_forward else (end_a_local - elbow_local).normalized()
			var speed: float = exit_speed_b if _ride_forward else exit_speed_a
			var world_dir: Vector3 = (global_transform.basis * dir_local).normalized()
			var launch_vel: Vector3 = world_dir * speed
			if absf(world_dir.y) < 0.35:
				launch_vel.y += 4.5

			_riding_body.global_position = (global_transform * exit_local) + world_dir * 0.65
			if _riding_body is CharacterBody3D:
				(_riding_body as CharacterBody3D).velocity = launch_vel
			_riding_body = null
			_cooldown_a = 0.7
			_cooldown_b = 0.7
			if sfx != null:
				sfx.play(&"tube_shoot", 1.0)
		return

	if _cooldown_a <= 0.0:
		for body: Node3D in _area_a.get_overlapping_bodies():
			_riding_body = body
			_ride_forward = true
			_ride_timer = 0.0
			if sfx != null:
				sfx.play(&"tube_suck", 0.95)
			return

	if _cooldown_b <= 0.0:
		for body: Node3D in _area_b.get_overlapping_bodies():
			_riding_body = body
			_ride_forward = false
			_ride_timer = 0.0
			if sfx != null:
				sfx.play(&"tube_suck", 0.95)
			return