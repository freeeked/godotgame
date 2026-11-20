@tool
class_name PneumaticTube
extends Node3D

@export_group("Tube Path")
@export var end_a_local: Vector3 = Vector3(10.5, 1.2, 14.5):
	set(value):
		end_a_local = value
		_rebuild()

@export var elbow_local: Vector3 = Vector3(10.5, 7.5, 14.5):
	set(value):
		elbow_local = value
		_rebuild()

@export var end_b_local: Vector3 = Vector3(4.5, 7.5, 14.5):
	set(value):
		end_b_local = value
		_rebuild()

@export_range(0.4, 4.0, 0.05) var tube_radius: float = 1.2:
	set(value):
		tube_radius = value
		_rebuild()

@export_group("Launch & Travel")
@export var exit_speed_a: float = 12.5:
	set(value):
		exit_speed_a = value
		_rebuild()

@export var exit_speed_b: float = 14.5:
	set(value):
		exit_speed_b = value
		_rebuild()

@export var travel_duration: float = 0.62

@export_group("Editor Trajectory Preview")
@export var show_editor_arcs: bool = true:
	set(value):
		show_editor_arcs = value
		_rebuild()
@export var show_arcs_in_game: bool = false:
	set(value):
		show_arcs_in_game = value
		_rebuild()
@export var preview_gravity: float = 44.0:
	set(value):
		preview_gravity = value
		_rebuild()
@export var preview_steps: int = 22:
	set(value):
		preview_steps = maxi(6, value)
		_rebuild()
@export var preview_time_step: float = 0.07:
	set(value):
		preview_time_step = maxf(0.02, value)
		_rebuild()

var _curve: Curve3D
var _area_a: Area3D
var _area_b: Area3D

var _cooldown_a: float = 0.0
var _cooldown_b: float = 0.0
var _stack_riding: bool = false
var _ride_timer: float = 0.0
var _ride_forward: bool = true

var _single_rides: Array[Dictionary] = []
var _single_cooldowns: Dictionary = {}

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_curve = Curve3D.new()
	var p_a: Vector3 = end_a_local
	var p_el: Vector3 = elbow_local
	var p_b: Vector3 = end_b_local
	var d1: Vector3 = (p_el - p_a).normalized() if p_a.distance_to(p_el) > 0.001 else Vector3.UP
	var d2: Vector3 = (p_b - p_el).normalized() if p_el.distance_to(p_b) > 0.001 else Vector3.FORWARD
	var fillet: float = minf(2.2, minf(p_a.distance_to(p_el) * 0.4, p_el.distance_to(p_b) * 0.4))

	_curve.add_point(p_a)
	_curve.add_point(p_el - d1 * fillet)
	_curve.add_point(p_el + d2 * fillet)
	_curve.add_point(p_b)

	_build_visual_tube()
	_area_a = _make_mouth_area(p_a, "MouthA")
	_area_b = _make_mouth_area(p_b, "MouthB")

	var should_show_arcs: bool = show_editor_arcs if Engine.is_editor_hint() else show_arcs_in_game
	if should_show_arcs:
		_build_exit_arc(p_a, -d1, exit_speed_a, Color(0.4, 0.91, 0.98, 0.9))
		_build_exit_arc(p_b, d2, exit_speed_b, Color(0.98, 0.75, 0.14, 0.9))

func _build_visual_tube() -> void:
	var baked: PackedVector3Array = _curve.get_baked_points()
	if baked.size() < 2:
		return

	# Deduplicate close curve points so normals stay clean
	var pts: Array[Vector3] = []
	for p: Vector3 in baked:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.04:
			pts.append(p)
	if pts.size() < 2:
		return

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.91, 0.98, 0.42)
	mat.emission_enabled = true
	mat.emission = Color("0891b2")
	mat.emission_energy_multiplier = 0.45
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Build a single continuous smooth sleeve mesh (no overlapping cylinder endcap bands)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var radial_segs: int = 24
	var rings: Array[Array] = []
	var prev_normal: Vector3 = Vector3.ZERO

	for i: int in range(pts.size()):
		var tangent: Vector3
		if i == 0:
			tangent = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			tangent = (pts[i] - pts[i - 1]).normalized()
		else:
			tangent = (pts[i + 1] - pts[i - 1]).normalized()

		if prev_normal.length_squared() < 0.001:
			var ref: Vector3 = Vector3.RIGHT if absf(tangent.dot(Vector3.UP)) > 0.9 else Vector3.UP
			prev_normal = tangent.cross(ref).normalized()
		else:
			prev_normal = (prev_normal - tangent * prev_normal.dot(tangent)).normalized()

		var binormal: Vector3 = tangent.cross(prev_normal).normalized()
		var ring_verts: Array[Vector3] = []
		for s: int in range(radial_segs + 1):
			var ang: float = (float(s) / float(radial_segs)) * TAU
			var radial_dir: Vector3 = prev_normal * cos(ang) + binormal * sin(ang)
			ring_verts.append(pts[i] + radial_dir * tube_radius)
		rings.append(ring_verts)

	for i: int in range(rings.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s: int in range(radial_segs):
			var v00: Vector3 = r0[s]
			var v01: Vector3 = r0[s + 1]
			var v10: Vector3 = r1[s]
			var v11: Vector3 = r1[s + 1]

			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v11)

			st.add_vertex(v00)
			st.add_vertex(v11)
			st.add_vertex(v01)

	st.generate_normals()
	var sleeve_mesh: MeshInstance3D = MeshInstance3D.new()
	sleeve_mesh.mesh = st.commit()
	sleeve_mesh.material_override = mat
	add_child(sleeve_mesh)

	# Flared intake rings at both tube ends
	var dir_a: Vector3 = (end_a_local - elbow_local).normalized() if end_a_local.distance_to(elbow_local) > 0.001 else Vector3.DOWN
	var dir_b: Vector3 = (end_b_local - elbow_local).normalized() if end_b_local.distance_to(elbow_local) > 0.001 else Vector3.FORWARD
	_add_mouth_rim(end_a_local, dir_a, Color("22d3ee"))
	_add_mouth_rim(end_b_local, dir_b, Color("f59e0b"))

func _add_mouth_rim(pos: Vector3, outward_dir: Vector3, rim_color: Color) -> void:
	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = rim_color
	rim_mat.emission_enabled = true
	rim_mat.emission = rim_color
	rim_mat.emission_energy_multiplier = 0.55

	var rim: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = tube_radius * 0.92
	torus.outer_radius = tube_radius * 1.18
	rim.mesh = torus
	rim.material_override = rim_mat
	rim.position = pos
	if absf(outward_dir.dot(Vector3.UP)) < 0.999:
		rim.quaternion = Quaternion(Vector3.UP, outward_dir)
	add_child(rim)

func _build_exit_arc(exit_local: Vector3, exit_dir_local: Vector3, speed: float, arc_color: Color) -> void:
	var arc_mat: StandardMaterial3D = StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.albedo_color = arc_color
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var start_local: Vector3 = exit_local + exit_dir_local * 0.65
	var v0_local: Vector3 = exit_dir_local * speed
	if absf(exit_dir_local.y) < 0.35:
		v0_local.y += 4.5

	var landing_local: Vector3 = start_local
	for i: int in range(preview_steps):
		var t0: float = float(i) * preview_time_step
		var t1: float = float(i + 1) * preview_time_step
		var p0: Vector3 = start_local + v0_local * t0 + Vector3(0.0, -0.5 * preview_gravity * t0 * t0, 0.0)
		var p1: Vector3 = start_local + v0_local * t1 + Vector3(0.0, -0.5 * preview_gravity * t1 * t1, 0.0)
		landing_local = p1
		var dash_end: Vector3 = p0.lerp(p1, 0.68)
		_add_dash_segment(p0, dash_end, arc_mat)

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.85
	ring.mesh = torus
	ring.material_override = arc_mat
	ring.position = landing_local
	add_child(ring)

func _add_dash_segment(a: Vector3, b: Vector3, mat: StandardMaterial3D) -> void:
	var seg_len: float = a.distance_to(b)
	if seg_len < 0.02:
		return
	var dash: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = seg_len
	dash.mesh = cyl
	dash.material_override = mat
	dash.position = (a + b) * 0.5
	var dir: Vector3 = (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		dash.quaternion = Quaternion(Vector3.UP, dir)
	add_child(dash)

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

func _sample_curve_pos_and_tangent(dist_along: float, forward: bool) -> Dictionary:
	var total_len: float = maxf(0.01, _curve.get_baked_length())
	var clamped_d: float = clampf(dist_along, 0.0, total_len)
	var eps: float = minf(0.18, total_len * 0.05)

	var p_curr: Vector3 = _curve.sample_baked(clamped_d, true)
	var p_prev: Vector3 = _curve.sample_baked(maxf(0.0, clamped_d - eps), true)
	var p_next: Vector3 = _curve.sample_baked(minf(total_len, clamped_d + eps), true)

	var tangent_local: Vector3 = (p_next - p_prev) if forward else (p_prev - p_next)
	if tangent_local.length_squared() < 0.0001:
		tangent_local = (end_b_local - elbow_local) if forward else (end_a_local - elbow_local)

	return {
		"pos": global_transform * p_curr,
		"tangent": (global_transform.basis * tangent_local).normalized(),
	}

func reset_tube() -> void:
	_stack_riding = false
	_ride_timer = 0.0
	_cooldown_a = 0.0
	_cooldown_b = 0.0
	_single_rides.clear()
	_single_cooldowns.clear()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _area_a == null or _area_b == null:
		return

	_cooldown_a = maxf(0.0, _cooldown_a - delta)
	_cooldown_b = maxf(0.0, _cooldown_b - delta)

	var expired_keys: Array = []
	for key: Variant in _single_cooldowns.keys():
		var rem: float = float(_single_cooldowns[key]) - delta
		if rem <= 0.0:
			expired_keys.append(key)
		else:
			_single_cooldowns[key] = rem
	for key: Variant in expired_keys:
		_single_cooldowns.erase(key)

	var player: Node = get_tree().root.find_child("PlayerStack", true, false)
	if player == null:
		return

	var sfx: SoundEngine = get_tree().root.find_child("SoundEngine", true, false) as SoundEngine
	var total_len: float = maxf(0.01, _curve.get_baked_length())

	# 1. Active stack single-file caterpillar ride along the tube curve
	if _stack_riding:
		var is_ext: bool = bool(player.call("is_externally_controlled")) if player.has_method("is_externally_controlled") else true
		if not is_ext:
			_stack_riding = false
			return

		_ride_timer += delta
		var raw_t: float = minf(1.0, _ride_timer / maxf(0.08, travel_duration))
		var eased: float = smoothstep(0.0, 1.0, raw_t)

		var radii: Array = player.call("get_active_blob_radii") if player.has_method("get_active_blob_radii") else [0.65, 0.72, 0.62]
		var blob_count: int = maxi(1, radii.size())
		var train_trail: float = 0.0
		for i: int in range(1, blob_count):
			train_trail += (float(radii[i - 1]) + float(radii[i])) * 0.92

		# Travel extra distance equal to train_trail so the last blob clears the exit cleanly
		var head_travel: float = eased * (total_len + train_trail * 0.75)

		var world_positions: Array[Vector3] = []
		var world_tangents: Array[Vector3] = []
		var accum_offset: float = 0.0

		for i: int in range(blob_count):
			if i > 0:
				accum_offset += (float(radii[i - 1]) + float(radii[i])) * 0.92
			var d_from_entry: float = head_travel - accum_offset
			var curve_dist: float = d_from_entry if _ride_forward else (total_len - d_from_entry)
			var sample: Dictionary = _sample_curve_pos_and_tangent(curve_dist, _ride_forward)
			world_positions.append(sample["pos"] as Vector3)
			world_tangents.append(sample["tangent"] as Vector3)

		var stretch: float = sin(raw_t * PI) * 0.22
		if player.has_method("pose_stack_along_tube"):
			player.call("pose_stack_along_tube", world_positions, world_tangents, stretch)

		if raw_t >= 1.0:
			var exit_local: Vector3 = end_b_local if _ride_forward else end_a_local
			var dir_local: Vector3 = (end_b_local - elbow_local).normalized() if _ride_forward else (end_a_local - elbow_local).normalized()
			var speed: float = exit_speed_b if _ride_forward else exit_speed_a
			var world_dir: Vector3 = (global_transform.basis * dir_local).normalized()
			var launch_vel: Vector3 = world_dir * speed
			if absf(world_dir.y) < 0.35:
				launch_vel.y += 4.5

			var exit_world: Vector3 = (global_transform * exit_local) + world_dir * 0.75
			if player.has_method("launch_stack_from_tube"):
				player.call("launch_stack_from_tube", exit_world, launch_vel.normalized(), launch_vel)

			_stack_riding = false
			_cooldown_a = 0.75
			_cooldown_b = 0.75
			if sfx != null:
				sfx.play(&"tube_shoot", 1.0)
	else:
		# Check if active stack enters Mouth A or Mouth B
		var is_ext: bool = bool(player.call("is_externally_controlled")) if player.has_method("is_externally_controlled") else false
		if not is_ext and player.has_method("get_active_blob_positions"):
			var positions: Array = player.call("get_active_blob_positions")
			var mouth_a_world: Vector3 = global_transform * end_a_local
			var mouth_b_world: Vector3 = global_transform * end_b_local
			var trigger_r: float = tube_radius * 1.25

			if _cooldown_a <= 0.0:
				for pos_v: Variant in positions:
					if (pos_v as Vector3).distance_to(mouth_a_world) <= trigger_r:
						_stack_riding = true
						_ride_forward = true
						_ride_timer = 0.0
						if player.has_method("set_external_control"):
							player.call("set_external_control", true)
						if sfx != null:
							sfx.play(&"tube_suck", 0.95)
						break

			if not _stack_riding and _cooldown_b <= 0.0:
				for pos_v: Variant in positions:
					if (pos_v as Vector3).distance_to(mouth_b_world) <= trigger_r:
						_stack_riding = true
						_ride_forward = false
						_ride_timer = 0.0
						if player.has_method("set_external_control"):
							player.call("set_external_control", true)
						if sfx != null:
							sfx.play(&"tube_suck", 0.95)
						break

	# 2. Advance individual ejected blobs riding the tube
	for i: int in range(_single_rides.size() - 1, -1, -1):
		var ride: Dictionary = _single_rides[i]
		ride["timer"] = float(ride["timer"]) + delta
		var raw_t: float = minf(1.0, float(ride["timer"]) / maxf(0.08, travel_duration * 0.85))
		var eased: float = smoothstep(0.0, 1.0, raw_t)
		var fwd: bool = bool(ride["forward"])
		var d_from_entry: float = eased * total_len
		var curve_dist: float = d_from_entry if fwd else (total_len - d_from_entry)
		var sample: Dictionary = _sample_curve_pos_and_tangent(curve_dist, fwd)

		var blob: Node3D = ride["blob"] as Node3D
		if is_instance_valid(blob):
			blob.global_position = sample["pos"] as Vector3

		if raw_t >= 1.0:
			_single_cooldowns[ride["id"]] = 0.75
			_single_rides.remove_at(i)
			if is_instance_valid(blob) and player.has_method("launch_ejected_blob"):
				var exit_local: Vector3 = end_b_local if fwd else end_a_local
				var dir_local: Vector3 = (end_b_local - elbow_local).normalized() if fwd else (end_a_local - elbow_local).normalized()
				var speed: float = exit_speed_b if fwd else exit_speed_a
				var world_dir: Vector3 = (global_transform.basis * dir_local).normalized()
				var launch_vel: Vector3 = world_dir * speed
				if absf(world_dir.y) < 0.35:
					launch_vel.y += 4.5
				var exit_world: Vector3 = (global_transform * exit_local) + world_dir * 0.75
				player.call("launch_ejected_blob", blob, exit_world, launch_vel)
			if sfx != null:
				sfx.play(&"tube_shoot", 0.9, 1.12)

	# 3. Check ejected blobs entering Mouth A or Mouth B
	if player.has_method("get_ejected_blob_nodes"):
		var ejected: Array = player.call("get_ejected_blob_nodes")
		var mouth_a_world: Vector3 = global_transform * end_a_local
		var mouth_b_world: Vector3 = global_transform * end_b_local
		var trigger_r: float = tube_radius * 1.25

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

			if _cooldown_a <= 0.0 and ej.global_position.distance_to(mouth_a_world) <= trigger_r:
				if player.has_method("lock_ejected_blob"):
					player.call("lock_ejected_blob", ej, true)
				_single_rides.append({"id": id, "blob": ej, "timer": 0.0, "forward": true})
				if sfx != null:
					sfx.play(&"tube_suck", 0.85, 1.12)
			elif _cooldown_b <= 0.0 and ej.global_position.distance_to(mouth_b_world) <= trigger_r:
				if player.has_method("lock_ejected_blob"):
					player.call("lock_ejected_blob", ej, true)
				_single_rides.append({"id": id, "blob": ej, "timer": 0.0, "forward": false})
				if sfx != null:
					sfx.play(&"tube_suck", 0.85, 1.12)