extends CharacterBody3D
class_name StackEnemy

signal enemy_killed(enemy: StackEnemy)
signal enemy_alerted(enemy: StackEnemy)

enum EnemyType {
	GROUND_RAMMER = 0,
	SKY_SHOOTER = 1,
}

enum PlaceholderShape {
	PILL = 0,
	CUBE = 1,
}

@export_group("Archetype & Visuals")
## GROUND_RAMMER charges at the player on foot; SKY_SHOOTER hovers and fires explosive projectiles.
@export var enemy_type: EnemyType = EnemyType.GROUND_RAMMER
## Placeholder geometry used when custom_model_scene is empty.
@export var placeholder_shape: PlaceholderShape = PlaceholderShape.PILL
## Optional custom .glb / PackedScene to replace the placeholder shape later.
@export var custom_model_scene: PackedScene
## Uniform scale applied to custom_model_scene.
@export var custom_model_scale: Vector3 = Vector3.ONE
## Body radius (meters) for collision and hit detection.
@export var body_radius: float = 0.72
## Body height (meters) for pill/cube dimensions.
@export var body_height: float = 1.55
## Primary color of the placeholder enemy.
@export var primary_color: Color = Color("ef4444")
## Telegraph flash color when winding up a ram or projectile shot.
@export var telegraph_color: Color = Color("facc15")

@export_group("Detection & Patrol")
## Distance (meters) at which the enemy spots the player stack.
@export var detection_radius: float = 18.0
## Distance (meters) beyond which the enemy gives up chasing and returns home.
@export var leash_radius: float = 28.0
## Require unobstructed line of sight to aggro.
@export var require_line_of_sight: bool = true
## Horizontal patrol radius (meters) around spawn point while idle (0 = stationary guard).
@export var patrol_radius: float = 3.5
## Patrol movement speed (m/s).
@export var patrol_speed: float = 3.2

@export_group("Ground Rammer Tuning")
## Wind-up anticipation duration (seconds) before lunging forward.
@export var ram_windup_time: float = 0.55
## Top charging speed (m/s) during a ram attack.
@export var ram_charge_speed: float = 16.5
## Duration (seconds) of the ram lunge before recovering.
@export var ram_charge_duration: float = 0.85
## Cooldown (seconds) between ram attacks.
@export var ram_cooldown: float = 1.15
## Horizontal knockback impulse applied to the player stack on ram hit.
@export var ram_jostle_horizontal: float = 16.0
## Upward hop impulse applied to the player stack on ram hit.
@export var ram_jostle_upward: float = 8.0

@export_group("Sky Shooter Tuning")
## Hover bobbing amplitude (meters) for sky enemies.
@export var hover_bob_amplitude: float = 0.35
## Hover bobbing frequency (rad/s).
@export var hover_bob_speed: float = 3.2
## Preferred horizontal standoff distance (meters) while aiming at the player.
@export var sky_preferred_range: float = 12.0
## Horizontal repositioning speed (m/s) in midair.
@export var sky_move_speed: float = 5.5
## Telegraph charge-up time (seconds) before firing a projectile.
@export var shoot_windup_time: float = 0.65
## Cooldown (seconds) between shots.
@export var shoot_cooldown: float = 2.1
## Projectile travel speed (m/s).
@export var projectile_speed: float = 21.0
## Optional downward gravity on projectiles (0 = straight laser-like arc).
@export var projectile_gravity: float = 4.5
## Blast radius (meters) of exploding projectiles.
@export var projectile_explosion_radius: float = 3.4
## Horizontal jostle strength of projectile explosions.
@export var projectile_jostle_horizontal: float = 15.0
## Upward jostle strength of projectile explosions.
@export var projectile_jostle_upward: float = 8.5

@export_group("Defeat & Mario Odyssey QoL")
## Minimum ejected ball speed (m/s) required to kill this enemy on impact.
@export var kill_ball_speed_threshold: float = 11.5
## Allow jumping on top of this enemy's head to bounce upward (Mario Odyssey style).
@export var allow_head_stomp_bounce: bool = true
## If true, stomping on the enemy's head also defeats it (otherwise it bounces & briefly stuns it).
@export var head_stomp_kills: bool = false
## Brief freeze-frame (seconds) on impact for crunchy hit feedback.
@export var hitstop_duration: float = 0.045
## Show a dark ground shadow circle directly beneath sky enemies for easy 3D depth reading.
@export var show_aerial_ground_shadow: bool = true

enum AIState {
	PATROL,
	WINDUP,
	ATTACK,
	RECOVER,
	STUNNED,
	DEAD,
}

var _state: AIState = AIState.PATROL
var _state_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _hit_grace_timer: float = 0.0
var _spawn_transform: Transform3D
var _patrol_angle: float = 0.0
var _charge_dir: Vector3 = Vector3.FORWARD
var _elapsed: float = 0.0

var _visual_pivot: Node3D = null
var _placeholder_mesh: MeshInstance3D = null
var _placeholder_mat: StandardMaterial3D = null
var _alert_pip: MeshInstance3D = null
var _shadow_decal: MeshInstance3D = null
var _player_stack: PlayerStack = null

func _ready() -> void:
	add_to_group("enemies")
	_spawn_transform = global_transform
	_patrol_angle = randf() * TAU

	floor_stop_on_slope = false
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true

	_ensure_collider()
	_build_visuals()
	_find_player_stack()

func _ensure_collider() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			return
	var col := CollisionShape3D.new()
	if placeholder_shape == PlaceholderShape.CUBE:
		var box := BoxShape3D.new()
		box.size = Vector3(body_radius * 1.8, body_height, body_radius * 1.8)
		col.shape = box
	else:
		var cap := CapsuleShape3D.new()
		cap.radius = body_radius
		cap.height = maxf(body_radius * 2.0, body_height)
		col.shape = cap
	add_child(col)

func _build_visuals() -> void:
	_visual_pivot = Node3D.new()
	_visual_pivot.name = "VisualPivot"
	add_child(_visual_pivot)

	if custom_model_scene != null:
		var model := custom_model_scene.instantiate()
		model.name = "CustomEnemyModel"
		if model is Node3D:
			(model as Node3D).scale = custom_model_scale
		_visual_pivot.add_child(model)
	else:
		_placeholder_mesh = MeshInstance3D.new()
		if placeholder_shape == PlaceholderShape.CUBE:
			var box := BoxMesh.new()
			box.size = Vector3(body_radius * 1.8, body_height, body_radius * 1.8)
			_placeholder_mesh.mesh = box
		else:
			var cap := CapsuleMesh.new()
			cap.radius = body_radius
			cap.height = maxf(body_radius * 2.0, body_height)
			_placeholder_mesh.mesh = cap

		_placeholder_mat = StandardMaterial3D.new()
		_placeholder_mat.albedo_color = primary_color
		_placeholder_mat.roughness = 0.55
		_placeholder_mesh.material_override = _placeholder_mat
		_visual_pivot.add_child(_placeholder_mesh)

		# Simple cartoon eyes so facing direction is readable right away
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = body_radius * 0.16
		eye_mesh.height = body_radius * 0.32
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color("111827")

		for side in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = eye_mesh
			eye.material_override = eye_mat
			eye.position = Vector3(side * body_radius * 0.36, body_height * 0.16, body_radius * 0.88)
			_visual_pivot.add_child(eye)

		# Wings/propeller fins on sky enemies for instant visual silhouette
		if enemy_type == EnemyType.SKY_SHOOTER:
			var wing_mesh := BoxMesh.new()
			wing_mesh.size = Vector3(body_radius * 1.25, 0.10, body_radius * 0.55)
			for side in [-1.0, 1.0]:
				var wing := MeshInstance3D.new()
				wing.mesh = wing_mesh
				wing.material_override = _placeholder_mat
				wing.position = Vector3(side * body_radius * 1.25, body_height * 0.12, 0.0)
				wing.rotation.z = side * 0.22
				_visual_pivot.add_child(wing)

	# Alert exclamation pip above head
	_alert_pip = MeshInstance3D.new()
	var pip_mesh := SphereMesh.new()
	pip_mesh.radius = 0.18
	pip_mesh.height = 0.36
	_alert_pip.mesh = pip_mesh
	var pip_mat := StandardMaterial3D.new()
	pip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pip_mat.albedo_color = telegraph_color
	_alert_pip.material_override = pip_mat
	_alert_pip.position = Vector3(0.0, body_height * 0.72 + 0.45, 0.0)
	_alert_pip.visible = false
	_visual_pivot.add_child(_alert_pip)

	# Ground drop shadow for aerial depth clarity
	if enemy_type == EnemyType.SKY_SHOOTER and show_aerial_ground_shadow:
		_shadow_decal = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = body_radius * 0.95
		disc.bottom_radius = body_radius * 0.95
		disc.height = 0.02
		_shadow_decal.mesh = disc
		var sh_mat := StandardMaterial3D.new()
		sh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sh_mat.albedo_color = Color(0.05, 0.08, 0.14, 0.42)
		_shadow_decal.material_override = sh_mat
		_shadow_decal.top_level = true
		add_child(_shadow_decal)

func _find_player_stack() -> void:
	if _player_stack != null and is_instance_valid(_player_stack):
		return
	var found := get_tree().root.find_child("PlayerStack", true, false)
	if found is PlayerStack:
		_player_stack = found as PlayerStack

func reset_enemy() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_state = AIState.PATROL
	_state_timer = 0.0
	_cooldown_timer = 0.0
	_hit_grace_timer = 0.0
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	if _visual_pivot != null:
		_visual_pivot.scale = Vector3.ONE
		_visual_pivot.rotation = Vector3.ZERO
		_visual_pivot.position = Vector3.ZERO
	if _placeholder_mat != null:
		_placeholder_mat.albedo_color = primary_color
	if _alert_pip != null:
		_alert_pip.visible = false
	if _shadow_decal != null:
		_shadow_decal.visible = true

func _physics_process(delta: float) -> void:
	if _state == AIState.DEAD:
		return

	_elapsed += delta
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	_hit_grace_timer = maxf(0.0, _hit_grace_timer - delta)
	_find_player_stack()

	# 1. Check incoming ejected balls first (can kill enemy at any moment)
	if _check_ejected_ball_hits():
		return

	# 2. Update AI movement & attacks
	if enemy_type == EnemyType.GROUND_RAMMER:
		_step_ground_rammer(delta)
	else:
		_step_sky_shooter(delta)

	# 3. Check player stack contact (head-stomp bounce vs. ram knockback)
	_check_player_stack_contact()

func _can_see_player(player_pos: Vector3) -> bool:
	var dist := global_position.distance_to(player_pos)
	if dist > detection_radius:
		return false
	if not require_line_of_sight:
		return true

	var exclude: Array[RID] = [get_rid()]
	if _player_stack != null:
		for child in _player_stack.get_children():
			if child is CollisionObject3D:
				exclude.append((child as CollisionObject3D).get_rid())

	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3,
		player_pos + Vector3.UP * 0.4
	)
	query.exclude = exclude
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()

func _step_ground_rammer(delta: float) -> void:
	velocity.y -= 38.0 * delta
	var player_pos := _player_stack.get_stack_center() if _player_stack != null else Vector3.INF
	var dist_from_home := global_position.distance_to(_spawn_transform.origin)

	match _state:
		AIState.PATROL:
			_set_telegraph_visual(0.0)
			if _player_stack != null and dist_from_home < leash_radius and _can_see_player(player_pos):
				_enter_windup(player_pos)
			else:
				_move_patrol_ground(delta)

		AIState.WINDUP:
			_state_timer -= delta
			var wind_ratio := 1.0 - clampf(_state_timer / maxf(0.01, ram_windup_time), 0.0, 1.0)
			_set_telegraph_visual(wind_ratio)

			# Track player aim during first 75% of windup, then lock direction so player can dodge!
			if wind_ratio < 0.75 and _player_stack != null:
				var to_p := Vector3(player_pos.x - global_position.x, 0.0, player_pos.z - global_position.z)
				if to_p.length_squared() > 0.01:
					_charge_dir = to_p.normalized()
					_face_direction(_charge_dir, 14.0 * delta)

			# Pull back slightly in anticipation
			velocity.x = -_charge_dir.x * 2.2
			velocity.z = -_charge_dir.z * 2.2
			if _visual_pivot != null:
				_visual_pivot.scale = Vector3(1.0 + wind_ratio * 0.22, 1.0 - wind_ratio * 0.22, 1.0 + wind_ratio * 0.22)

			if _state_timer <= 0.0:
				_state = AIState.ATTACK
				_state_timer = ram_charge_duration
				if _visual_pivot != null:
					_visual_pivot.scale = Vector3(0.84, 1.18, 1.24)
				_play_sound(&"roll_start", 0.65, 1.25)

		AIState.ATTACK:
			_state_timer -= delta
			_set_telegraph_visual(1.0)
			velocity.x = _charge_dir.x * ram_charge_speed
			velocity.z = _charge_dir.z * ram_charge_speed
			_face_direction(_charge_dir, 18.0 * delta)

			if _state_timer <= 0.0 or is_on_wall() or dist_from_home > leash_radius:
				_state = AIState.RECOVER
				_state_timer = ram_cooldown
				if _visual_pivot != null:
					_visual_pivot.scale = Vector3.ONE

		AIState.RECOVER, AIState.STUNNED:
			_state_timer -= delta
			_set_telegraph_visual(0.0)
			velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-10.0 * delta))
			velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-10.0 * delta))
			if _visual_pivot != null:
				_visual_pivot.scale = _visual_pivot.scale.lerp(Vector3.ONE, 1.0 - exp(-12.0 * delta))
			if _state_timer <= 0.0:
				_state = AIState.PATROL

	move_and_slide()

func _move_patrol_ground(delta: float) -> void:
	if patrol_radius <= 0.05:
		var home_disp := Vector3(_spawn_transform.origin.x - global_position.x, 0.0, _spawn_transform.origin.z - global_position.z)
		if home_disp.length() > 0.35:
			var dir := home_disp.normalized()
			velocity.x = dir.x * patrol_speed
			velocity.z = dir.z * patrol_speed
			_face_direction(dir, 8.0 * delta)
		else:
			velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-10.0 * delta))
			velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-10.0 * delta))
		return

	_patrol_angle += (patrol_speed / maxf(0.5, patrol_radius)) * delta
	var target := _spawn_transform.origin + Vector3(cos(_patrol_angle) * patrol_radius, 0.0, sin(_patrol_angle) * patrol_radius)
	var to_t := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to_t.length_squared() > 0.01:
		var dir := to_t.normalized()
		velocity.x = dir.x * patrol_speed
		velocity.z = dir.z * patrol_speed
		_face_direction(dir, 8.0 * delta)

func _step_sky_shooter(delta: float) -> void:
	var player_pos := _player_stack.get_stack_center() if _player_stack != null else Vector3.INF
	var bob_y := _spawn_transform.origin.y + sin(_elapsed * hover_bob_speed) * hover_bob_amplitude
	var dist_from_home := global_position.distance_to(_spawn_transform.origin)

	match _state:
		AIState.PATROL:
			_set_telegraph_visual(0.0)
			if _player_stack != null and dist_from_home < leash_radius and _can_see_player(player_pos):
				_hover_toward_player(player_pos, bob_y, delta)
				if _cooldown_timer <= 0.0:
					_enter_windup(player_pos)
			else:
				_move_patrol_sky(bob_y, delta)

		AIState.WINDUP:
			_state_timer -= delta
			var wind_ratio := 1.0 - clampf(_state_timer / maxf(0.01, shoot_windup_time), 0.0, 1.0)
			_set_telegraph_visual(wind_ratio)
			velocity = velocity.lerp(Vector3(0.0, (bob_y - global_position.y) * 5.0, 0.0), 1.0 - exp(-8.0 * delta))

			if _player_stack != null:
				var aim := (player_pos - global_position).normalized()
				_face_direction(Vector3(aim.x, 0.0, aim.z), 14.0 * delta)

			if _visual_pivot != null:
				var swell := 1.0 + sin(wind_ratio * PI) * 0.24
				_visual_pivot.scale = Vector3(swell, 1.0 - sin(wind_ratio * PI) * 0.14, swell)

			if _state_timer <= 0.0:
				_fire_projectile(player_pos)
				_state = AIState.RECOVER
				_state_timer = 0.35
				_cooldown_timer = shoot_cooldown

		AIState.RECOVER, AIState.STUNNED:
			_state_timer -= delta
			_set_telegraph_visual(0.0)
			velocity = velocity.lerp(Vector3(0.0, (bob_y - global_position.y) * 5.0, 0.0), 1.0 - exp(-8.0 * delta))
			if _visual_pivot != null:
				_visual_pivot.scale = _visual_pivot.scale.lerp(Vector3.ONE, 1.0 - exp(-12.0 * delta))
			if _state_timer <= 0.0:
				_state = AIState.PATROL

	move_and_slide()
	_update_ground_shadow()

func _move_patrol_sky(bob_y: float, delta: float) -> void:
	_patrol_angle += (patrol_speed / maxf(0.5, maxf(1.0, patrol_radius))) * delta
	var offset := Vector3(cos(_patrol_angle) * patrol_radius, 0.0, sin(_patrol_angle) * patrol_radius) if patrol_radius > 0.05 else Vector3.ZERO
	var target := Vector3(_spawn_transform.origin.x + offset.x, bob_y, _spawn_transform.origin.z + offset.z)
	var disp := target - global_position
	velocity = velocity.lerp(disp * 3.0, 1.0 - exp(-6.0 * delta))
	if Vector2(velocity.x, velocity.z).length() > 0.25:
		_face_direction(Vector3(velocity.x, 0.0, velocity.z).normalized(), 6.0 * delta)

func _hover_toward_player(player_pos: Vector3, bob_y: float, delta: float) -> void:
	var to_p := Vector3(player_pos.x - global_position.x, 0.0, player_pos.z - global_position.z)
	var flat_dist := to_p.length()
	var dir := to_p / maxf(0.001, flat_dist)
	_face_direction(dir, 10.0 * delta)

	var desired_vel := Vector3.ZERO
	if flat_dist > sky_preferred_range + 2.0:
		desired_vel = dir * sky_move_speed
	elif flat_dist < sky_preferred_range - 2.5:
		desired_vel = -dir * (sky_move_speed * 0.75)

	desired_vel.y = (bob_y - global_position.y) * 5.0
	velocity = velocity.lerp(desired_vel, 1.0 - exp(-6.0 * delta))

func _enter_windup(player_pos: Vector3) -> void:
	_state = AIState.WINDUP
	_state_timer = ram_windup_time if enemy_type == EnemyType.GROUND_RAMMER else shoot_windup_time
	var to_p := Vector3(player_pos.x - global_position.x, 0.0, player_pos.z - global_position.z)
	if to_p.length_squared() > 0.01:
		_charge_dir = to_p.normalized()
	enemy_alerted.emit(self)
	_play_sound(&"ui_hover", 0.65, 1.35)

func _fire_projectile(player_pos: Vector3) -> void:
	if get_parent() == null:
		return

	var muzzle := global_position + (_visual_pivot.global_transform.basis.z * (body_radius + 0.35))
	var to_target := player_pos - muzzle
	var dist := to_target.length()
	var flight_t := dist / maxf(1.0, projectile_speed)

	# Compensate slightly for gravity arc so shots land near the player
	var aim_point := player_pos + Vector3(0.0, 0.5 * projectile_gravity * flight_t * flight_t, 0.0)
	var shoot_dir := (aim_point - muzzle).normalized()

	var proj := EnemyProjectile.new()
	proj.velocity = shoot_dir * projectile_speed
	proj.gravity_accel = projectile_gravity
	proj.explosion_radius = projectile_explosion_radius
	proj.jostle_horizontal = projectile_jostle_horizontal
	proj.jostle_upward = projectile_jostle_upward
	proj.proj_color = telegraph_color
	proj.owner_enemy = self
	get_parent().add_child(proj)
	proj.global_position = muzzle

	if _visual_pivot != null:
		_visual_pivot.scale = Vector3(1.25, 0.78, 0.75)
	_play_sound(&"eject", 0.7, 1.3)

func _check_ejected_ball_hits() -> bool:
	if _player_stack == null:
		return false

	var balls := _player_stack.get_ejected_blob_infos()
	for info in balls:
		var ball_pos: Vector3 = info["position"]
		var ball_r: float = info["radius"]
		var ball_speed: float = info["speed"]
		var horiz_dist := Vector2(ball_pos.x - global_position.x, ball_pos.z - global_position.z).length()
		var vert_dist := absf(ball_pos.y - global_position.y)

		if horiz_dist <= (body_radius + ball_r + 0.15) and vert_dist <= (body_height * 0.6 + ball_r):
			if ball_speed >= kill_ball_speed_threshold:
				var hit_dir := (global_position - ball_pos).normalized()
				_player_stack.deflect_ejected_blob_on_hit(info["blob"], -hit_dir)
				_kill_enemy(hit_dir * ball_speed)
				return true
			else:
				# Slow ball bounces harmlessly off armor with a clink
				var bounce_n := (ball_pos - global_position).normalized()
				_player_stack.deflect_ejected_blob_on_hit(info["blob"], bounce_n)
				_play_sound(&"bounce", 0.45, 1.4)
	return false

func _check_player_stack_contact() -> void:
	if _player_stack == null or _hit_grace_timer > 0.0:
		return

	var driver := _player_stack.get_active_driver_body()
	if driver == null:
		return

	var stack_pos := driver.global_position
	var horiz_dist := Vector2(stack_pos.x - global_position.x, stack_pos.z - global_position.z).length()
	var vert_diff := stack_pos.y - global_position.y

	if horiz_dist > body_radius + 0.75 or absf(vert_diff) > body_height * 0.75 + 0.75:
		return

	# Mario Odyssey Head-Stomp Check: player is above enemy head and falling downward
	if allow_head_stomp_bounce and vert_diff > body_height * 0.25 and _player_stack._leader_vel.y <= 1.0:
		_hit_grace_timer = 0.35
		_player_stack.bounce_off_enemy_head(17.5)
		_play_sound(&"bounce", 0.85, 1.2)
		if head_stomp_kills:
			_kill_enemy(Vector3(0.0, 4.0, 0.0))
		else:
			_state = AIState.STUNNED
			_state_timer = 0.85
			if _visual_pivot != null:
				_visual_pivot.scale = Vector3(1.38, 0.55, 1.38)
		return

	# Ground Rammer body bump jostles the player stack
	if enemy_type == EnemyType.GROUND_RAMMER and (_state == AIState.ATTACK or _state == AIState.PATROL):
		_hit_grace_timer = 0.65
		var push := Vector3(stack_pos.x - global_position.x, 0.0, stack_pos.z - global_position.z)
		if push.length_squared() < 0.001:
			push = _charge_dir
		push = push.normalized()

		var mult := 1.0 if _state == AIState.ATTACK else 0.55
		_player_stack.apply_external_jostle(
			Vector3(push.x * ram_jostle_horizontal * mult, ram_jostle_upward * mult, push.z * ram_jostle_horizontal * mult),
			0.6 * mult
		)
		_play_sound(&"land", 0.8, 0.85)
		if _state == AIState.ATTACK:
			_state = AIState.RECOVER
			_state_timer = ram_cooldown

func _kill_enemy(impact_vel: Vector3) -> void:
	if _state == AIState.DEAD:
		return
	_state = AIState.DEAD
	enemy_killed.emit(self)
	_play_sound(&"explode", 0.85, 1.15)

	if _player_stack != null:
		_player_stack.trigger_camera_shake(Vector3(randf_range(-0.35, 0.35), 0.25, randf_range(-0.35, 0.35)))

	# Brief hitstop freeze for crunchy impact
	if hitstop_duration > 0.001:
		get_tree().paused = true
		await get_tree().create_timer(hitstop_duration, true).timeout
		if is_inside_tree():
			get_tree().paused = false

	# Spawn a lightweight visual spin-out corpse so collisions disable immediately
	if _visual_pivot != null and get_parent() != null:
		var corpse := _visual_pivot.duplicate() as Node3D
		get_parent().add_child(corpse)
		corpse.global_transform = _visual_pivot.global_transform
		var fling := Vector3(impact_vel.x * 0.45, 10.5, impact_vel.z * 0.45)
		var tw := corpse.create_tween()
		tw.set_parallel(true)
		tw.tween_property(corpse, "global_position", corpse.global_position + fling * 0.32, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(corpse, "rotation", corpse.rotation + Vector3(6.5, 8.0, 5.0), 0.32)
		tw.tween_property(corpse, "scale", Vector3.ONE * 0.05, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(corpse.queue_free)

	if _shadow_decal != null:
		_shadow_decal.visible = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func _set_telegraph_visual(intensity: float) -> void:
	if _alert_pip != null:
		_alert_pip.visible = intensity > 0.05
		_alert_pip.scale = Vector3.ONE * (0.85 + intensity * 0.45)
	if _placeholder_mat != null:
		_placeholder_mat.albedo_color = primary_color.lerp(telegraph_color, clampf(intensity, 0.0, 1.0))

func _face_direction(flat_dir: Vector3, weight: float) -> void:
	if _visual_pivot == null or flat_dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(flat_dir.x, flat_dir.z)
	var diff := fposmod(target_yaw - _visual_pivot.rotation.y + PI, TAU) - PI
	_visual_pivot.rotation.y += diff * minf(1.0, weight)

func _update_ground_shadow() -> void:
	if _shadow_decal == null:
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 30.0)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_shadow_decal.visible = false
	else:
		_shadow_decal.visible = true
		var hit_pos := hit["position"] as Vector3
		_shadow_decal.global_position = hit_pos + Vector3(0.0, 0.03, 0.0)
		var height := maxf(0.0, global_position.y - hit_pos.y)
		var scale_f := clampf(1.0 - (height / 24.0) * 0.55, 0.35, 1.0)
		_shadow_decal.scale = Vector3(scale_f, 1.0, scale_f)

func _play_sound(sound_name: StringName, volume: float, pitch: float) -> void:
	var snd := get_tree().root.find_child("SoundEngine", true, false)
	if snd != null and snd.has_method("play"):
		snd.call("play", sound_name, volume, pitch)
