class_name DustParticles
extends Node3D

@export_group("Puff Geometry & Shading")
@export var puff_radius: float = 0.16
@export var use_clay_style: bool = false ## If true, uses smooth clay-like roughness; false keeps crisp flat-shaded facets
@export var max_active_particles: int = 160

@export_group("Physics & Curve Tuning")
@export var drag_damping: float = 7.0
@export var upward_buoyancy: float = 0.9
@export var pop_in_ratio: float = 0.20 ## First % of lifetime spent popping in from 0.4x to 1.0x scale
@export var shrink_end_ratio: float = 0.15 ## Final scale multiplier right before vanishing
@export var spin_speed_max: float = 6.0

@export_group("Preset Colors")
@export var burst_color: Color = Color("e2e8f0")
@export var skid_color: Color = Color("cbd5e1")
@export var footstep_color: Color = Color("94a3b8")
@export var wall_bump_color: Color = Color("cbd5e1")

@export_group("Auto Stack Tracking")
@export var auto_track_footsteps_and_skids: bool = true
@export var footstep_interval_normal: float = 0.22
@export var footstep_interval_roll: float = 0.11
@export var skid_turn_dot_threshold: float = -0.35

class PuffInstance:
	var mesh_inst: MeshInstance3D
	var material: StandardMaterial3D
	var velocity: Vector3
	var rot_speed: Vector3
	var age: float = 0.0
	var max_age: float = 0.3
	var initial_scale: float = 1.0
	var base_opacity: float = 0.85

var _particles: Array[PuffInstance] = []
var _puff_mesh: SphereMesh
var _player_stack: PlayerStack

var _footstep_timer: float = 0.0
var _prev_move_dir: Vector3 = Vector3.ZERO
var _skid_cooldown: float = 0.0

func _ready() -> void:
	_build_shared_mesh()

func _build_shared_mesh() -> void:
	_puff_mesh = SphereMesh.new()
	_puff_mesh.radius = puff_radius
	_puff_mesh.height = puff_radius * 2.0
	_puff_mesh.radial_segments = 6
	_puff_mesh.rings = 3

## Connects directly to PlayerStack signals so jumps, long jumps, landings, bounces, and ejects emit automatically.
func bind_to_player_stack(stack: PlayerStack) -> void:
	if stack == null:
		return
	_player_stack = stack

	stack.jumped.connect(func(stack_count: int, is_air_combo: bool) -> void:
		var origin: Vector3 = stack.get_leader_position() + Vector3(0.0, -0.45, 0.0)
		var count: int = 10 if is_air_combo else (6 + stack_count)
		var col: Color = Color("bae6fd") if is_air_combo else burst_color
		emit_burst(origin, count, col, 3.6 if is_air_combo else 3.0, 1.05 if is_air_combo else 0.9)
	)


	stack.skid_started.connect(func(origin: Vector3, skid_dir: Vector3) -> void:
		emit_skid_dust(origin, -skid_dir)
		_skid_cooldown = 0.10
	)

	stack.landed.connect(func(impact_speed: float, stack_count: int) -> void:
		var intensity: float = clampf(impact_speed / 20.0, 0.4, 1.35)
		var origin: Vector3 = stack.get_leader_position() + Vector3(0.0, -0.5, 0.0)
		emit_burst(origin, 6 + stack_count * 2, burst_color, 2.8 * intensity, 0.85 * intensity)
	)

	stack.bounced.connect(func(speed: float) -> void:
		var intensity: float = clampf(speed / 16.0, 0.35, 1.1)
		emit_burst(stack.get_stack_center(), 5, skid_color, 2.4 * intensity, 0.7 * intensity)
	)

	stack.blob_ejected.connect(func(_id: int, _name: String, is_roll: bool) -> void:
		var origin: Vector3 = stack.get_leader_position() if is_roll else stack.get_stack_center()
		emit_burst(origin, 7 if is_roll else 6, burst_color, 3.8 if is_roll else 2.9, 0.85)
	)

	stack.blob_reabsorbed.connect(func(_id: int, _name: String, was_recalling: bool) -> void:
		if was_recalling:
			emit_burst(stack.get_stack_center(), 6, Color("fef08a"), 2.6, 0.75)
	)

func _physics_process(delta: float) -> void:
	if auto_track_footsteps_and_skids and _player_stack != null:
		_update_stack_locomotion_dust(delta)
	update_particles(delta)

func _update_stack_locomotion_dust(delta: float) -> void:
	if _player_stack._active_nodes.is_empty() or _player_stack.is_externally_controlled():
		return

	_skid_cooldown = maxf(0.0, _skid_cooldown - delta)
	var leader := _player_stack._active_nodes[0]
	var vel: Vector3 = _player_stack._leader_vel
	var horiz_vel := Vector3(vel.x, 0.0, vel.z)
	var horiz_speed: float = horiz_vel.length()
	var feet_pos: Vector3 = leader.body.global_position - Vector3(0.0, leader.radius * 0.82, 0.0)

	if leader.body.is_on_wall() and vel.length() > 3.5:
		if _skid_cooldown <= 0.0:
			var wall_n: Vector3 = leader.body.get_wall_normal()
			emit_wall_bump_dust(leader.body.global_position - wall_n * (leader.radius * 0.7), wall_n)
			_skid_cooldown = 0.14

	if not _player_stack._is_grounded or horiz_speed < 2.2:
		_footstep_timer = 0.0
		if horiz_speed < 1.0:
			_prev_move_dir = Vector3.ZERO
		return

	var move_dir: Vector3 = horiz_vel / horiz_speed

	if _player_stack._is_skidding and _skid_cooldown <= 0.0:
		emit_skid_dust(feet_pos, -move_dir)
		_skid_cooldown = 0.07

	_prev_move_dir = _prev_move_dir.lerp(move_dir, minf(1.0, 10.0 * delta)).normalized()

	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		emit_footstep_dust(feet_pos, move_dir)
		_footstep_timer = footstep_interval_roll if _player_stack._is_sprint_rolling else footstep_interval_normal

func spawn_particle(
	origin: Vector3,
	velocity: Vector3,
	color: Color,
	initial_scale: float,
	max_age: float,
	opacity: float
) -> PuffInstance:
	if _puff_mesh == null:
		_build_shared_mesh()

	if _particles.size() >= max_active_particles:
		var oldest: PuffInstance = _particles.pop_front()
		if is_instance_valid(oldest.mesh_inst):
			oldest.mesh_inst.queue_free()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, opacity)
	mat.roughness = 0.72 if use_clay_style else 0.92
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not use_clay_style:
		mat.vertex_color_use_as_albedo = false

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _puff_mesh
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.position = origin
	mesh_inst.rotation = Vector3(
		randf() * PI,
		randf() * PI,
		randf() * PI
	)
	mesh_inst.scale = Vector3.ONE * (initial_scale * 0.4)
	add_child(mesh_inst)

	var p := PuffInstance.new()
	p.mesh_inst = mesh_inst
	p.material = mat
	p.velocity = velocity
	p.rot_speed = Vector3(
		randf_range(-0.5, 0.5) * spin_speed_max,
		randf_range(-0.5, 0.5) * spin_speed_max,
		randf_range(-0.5, 0.5) * spin_speed_max
	)
	p.age = 0.0
	p.max_age = maxf(0.05, max_age)
	p.initial_scale = initial_scale
	p.base_opacity = opacity

	_particles.append(p)
	return p

## Radial puff for jump takeoff, landing, or throw pop.
func emit_burst(
	origin: Vector3,
	count: int = 8,
	color: Color = Color("e2e8f0"),
	speed: float = 3.2,
	scale_mult: float = 1.0
) -> void:
	for i: int in range(count):
		var angle: float = (float(i) / float(maxi(1, count))) * TAU + randf_range(-0.25, 0.25)
		var radial_speed: float = speed * randf_range(0.6, 1.2)

		var pos := origin + Vector3(cos(angle) * 0.22, 0.0, sin(angle) * 0.22)
		var vel := Vector3(
			cos(angle) * radial_speed,
			randf_range(1.1, 2.6),
			sin(angle) * radial_speed
		)

		spawn_particle(
			pos,
			vel,
			color,
			scale_mult * randf_range(0.65, 1.15),
			randf_range(0.26, 0.38),
			0.85
		)

## Sharp Turn / Skid Dust: slate-tinted puffs kicked back on direction reversal.
func emit_skid_dust(origin: Vector3, facing_direction: Vector3) -> void:
	var base_angle: float = atan2(facing_direction.x, facing_direction.z) + PI
	for i: int in range(3):
		var angle: float = base_angle + randf_range(-0.3, 0.3)
		var radial_speed: float = randf_range(2.6, 4.0)

		var pos := origin + Vector3(cos(angle) * 0.15, 0.06, sin(angle) * 0.15)
		var vel := Vector3(
			cos(angle) * radial_speed,
			randf_range(0.6, 1.3),
			sin(angle) * radial_speed
		)

		spawn_particle(
			pos,
			vel,
			skid_color,
			randf_range(0.45, 0.65),
			randf_range(0.20, 0.28),
			0.75
		)

## Running Footstep Puffs: small, soft ground-colored puffs that hug the floor.
func emit_footstep_dust(origin: Vector3, facing_direction: Vector3) -> void:
	var base_angle: float = atan2(facing_direction.x, facing_direction.z) + PI
	var angle: float = base_angle + randf_range(-0.25, 0.25)
	var radial_speed: float = randf_range(1.1, 1.8)

	var pos := origin + Vector3(cos(angle) * 0.18, 0.04, sin(angle) * 0.18)
	var vel := Vector3(
		cos(angle) * radial_speed,
		randf_range(0.35, 0.70),
		sin(angle) * radial_speed
	)

	spawn_particle(
		pos,
		vel,
		footstep_color,
		randf_range(0.32, 0.46),
		randf_range(0.18, 0.24),
		0.55
	)

## Wall Slide / Bump Dust: small friction puffs that drift gently off the wall surface.
func emit_wall_bump_dust(origin: Vector3, impact_normal: Vector3) -> void:
	var base_angle: float = atan2(impact_normal.x, impact_normal.z)
	for i: int in range(2):
		var angle: float = base_angle + randf_range(-0.45, 0.45)
		var radial_speed: float = randf_range(1.6, 2.7)

		var pos := origin + Vector3(
			impact_normal.x * 0.08,
			randf_range(-0.125, 0.125),
			impact_normal.z * 0.08
		)
		var vel := Vector3(
			cos(angle) * radial_speed,
			randf_range(0.4, 1.1),
			sin(angle) * radial_speed
		)

		spawn_particle(
			pos,
			vel,
			wall_bump_color,
			randf_range(0.34, 0.50),
			randf_range(0.18, 0.25),
			0.65
		)

## Custom Animation Helper: spawn a single puff and drive custom Tween/AnimationPlayer tracks on its MeshInstance3D.
func play_custom_puff(
	origin: Vector3,
	velocity: Vector3,
	color: Color = Color.WHITE,
	initial_scale: float = 1.0,
	duration: float = 0.4,
	custom_tween_callback: Callable = Callable()
) -> PuffInstance:
	var p: PuffInstance = spawn_particle(origin, velocity, color, initial_scale, duration, 0.9)
	if custom_tween_callback.is_valid():
		custom_tween_callback.call(p.mesh_inst, p.material)
	return p

func clear_all() -> void:
	for p: PuffInstance in _particles:
		if is_instance_valid(p.mesh_inst):
			p.mesh_inst.queue_free()
	_particles.clear()

func update_particles(delta: float) -> void:
	var drag_factor: float = exp(-drag_damping * delta)

	for i: int in range(_particles.size() - 1, -1, -1):
		var p: PuffInstance = _particles[i]
		p.age += delta

		if p.age >= p.max_age or not is_instance_valid(p.mesh_inst):
			if is_instance_valid(p.mesh_inst):
				p.mesh_inst.queue_free()
			_particles.remove_at(i)
			continue

		var t: float = p.age / p.max_age
		p.velocity *= drag_factor
		p.velocity.y += upward_buoyancy * delta
		p.mesh_inst.position += p.velocity * delta
		p.mesh_inst.rotation += p.rot_speed * delta

		var scale_curve: float
		if t < pop_in_ratio:
			scale_curve = 0.4 + (t / maxf(0.001, pop_in_ratio)) * 0.6
		else:
			var shrink_t: float = (t - pop_in_ratio) / maxf(0.001, 1.0 - pop_in_ratio)
			scale_curve = 1.0 - shrink_t * (1.0 - shrink_end_ratio)

		p.mesh_inst.scale = Vector3.ONE * maxf(0.01, p.initial_scale * scale_curve)
		p.material.albedo_color.a = p.base_opacity * (1.0 - t * t)