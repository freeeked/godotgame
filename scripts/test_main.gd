extends Node3D

@onready var player_stack: PlayerStack = get_node_or_null("PlayerStack") as PlayerStack

enum CameraFeelMode {
	SNAPPY = 0,
	CINEMATIC_FLUID = 1,
}

@export_group("Camera Mode & Controls")
## Active camera preset (SNAPPY for tight platforming, CINEMATIC_FLUID for looser drift and heavier momentum feel).
@export var camera_mode: CameraFeelMode = CameraFeelMode.SNAPPY
## Mouse look rotation speed in radians per pixel of cursor movement.
@export var orbit_sensitivity: float = 0.0036
## Keyboard camera rotation speed (I/J/K/L or orbit actions) in radians per second.
@export var key_orbit_speed: float = 2.2
## Closest zoom distance (meters) allowed when scrolling in with the mouse wheel.
@export var min_zoom_distance: float = 4.2
## Farthest zoom distance (meters) allowed when scrolling out with the mouse wheel.
@export var max_zoom_distance: float = 15.0
## Distance change (meters) applied per mouse wheel scroll notch.
@export var zoom_step: float = 0.95
## Sphere-cast padding radius (meters) keeping the camera from clipping into walls and floors.
@export var camera_collision_margin: float = 0.45
## Gentle yaw assist (rad/s) when strafing perpendicular to camera (yields instantly on mouse move).
@export var strafe_orbit_assist_speed: float = 0.42

@export_group("Grounded Vertical Hysteresis")
## Upward jump deadzone (meters) above last grounded height before camera rises to follow climbs.
@export var vertical_deadzone_up: float = 2.35
## Downward drop deadzone (meters) below last grounded height before camera drops to follow falls.
@export var vertical_deadzone_down: float = 0.65

@export_group("Snappy Camera Tuning")
## Default follow distance (meters) behind the stack in Snappy mode.
@export var snappy_follow_distance: float = 7.2
## Horizontal over-the-shoulder offset (meters) to keep the crosshair clear of the stack.
@export var snappy_shoulder_offset_x: float = 1.05
## Vertical height (meters) above the base blob where the camera rig orbits.
@export var snappy_pivot_height: float = 1.45
## Vertical height (meters) above the base blob where the camera aims.
@export var snappy_look_ahead_height: float = 1.85
## Forward distance (meters) along camera facing that the look target projects ahead.
@export var snappy_look_ahead_forward: float = 2.0
## Velocity look-ahead multiplier shifting the frame in your movement direction on bursts/skids.
@export var snappy_velocity_lead: float = 0.09
## Critically damped horizontal spring frequency (higher = tighter lock, lower = more elastic surge).
@export var snappy_spring_freq: float = 15.0
## Vertical tracking smoothing speed toward the grounded floor baseline.
@export var snappy_vert_smooth: float = 9.0
## Rotational smoothing speed for yaw/pitch orbit (higher = closer to raw 1:1 mouse response).
@export var snappy_orbit_smooth: float = 46.0
## Smoothing speed when interpolating zoom distance changes.
@export var snappy_zoom_smooth: float = 18.0
## Maximum camera roll tilt (degrees) when strafing, orbiting, or banking into turns.
@export var snappy_bank_roll_deg: float = 1.4
## Resting field of view (degrees) at normal movement speeds in Snappy mode.
@export var snappy_base_fov: float = 72.0
## Peak field of view (degrees) during sprint-rolls, long jumps, swoops, or cannon boosts.
@export var snappy_boost_fov: float = 80.0

@export_group("Cinematic Fluid Camera Tuning")
## Default follow distance (meters) behind the stack in Cinematic Fluid mode.
@export var fluid_follow_distance: float = 8.4
## Horizontal over-the-shoulder offset (meters) in Cinematic Fluid mode.
@export var fluid_shoulder_offset_x: float = 1.25
## Vertical height (meters) above the base blob where the camera rig orbits in Fluid mode.
@export var fluid_pivot_height: float = 1.65
## Vertical height (meters) above the base blob where the camera aims in Fluid mode.
@export var fluid_look_ahead_height: float = 2.05
## Forward distance (meters) along camera facing that the look target projects ahead in Fluid mode.
@export var fluid_look_ahead_forward: float = 3.2
## Velocity look-ahead multiplier shifting the frame ahead of high-speed movement in Fluid mode.
@export var fluid_velocity_lead: float = 0.17
## Critically damped horizontal spring frequency (lower values let the blobs visibly surge ahead on bursts).
@export var fluid_spring_freq: float = 10.5
## Vertical tracking smoothing speed toward the grounded floor baseline in Fluid mode.
@export var fluid_vert_smooth: float = 6.5
## Rotational smoothing speed for yaw/pitch orbit in Fluid mode.
@export var fluid_orbit_smooth: float = 40.0
## Smoothing speed when interpolating zoom distance changes in Fluid mode.
@export var fluid_zoom_smooth: float = 10.0
## Maximum camera roll tilt (degrees) during high-speed sprint-roll curves and skids.
@export var fluid_bank_roll_deg: float = 2.8
## Resting field of view (degrees) at normal movement speeds in Fluid mode.
@export var fluid_base_fov: float = 75.0
## Peak field of view (degrees) during high-speed states in Fluid mode.
@export var fluid_boost_fov: float = 87.0

var _camera_rig: Node3D
var _camera: Camera3D
var _hud: GameHUD
var _sound: SoundEngine
var _dust: DustParticles

var _target_yaw: float = 0.0
var _target_pitch: float = -0.16
var _current_yaw: float = 0.0
var _current_pitch: float = -0.16
var _prev_yaw: float = 0.0
var _manual_orbit_yield_timer: float = 0.0

var _target_zoom_distance: float = 7.2
var _current_zoom_distance: float = 7.2
var _smoothed_boost_ratio: float = 0.0

# Critically damped spring follow & grounded vertical hysteresis state
var _spring_follow_pos: Vector3 = Vector3.ZERO
var _spring_follow_vel: Vector3 = Vector3.ZERO
var _grounded_base_y: float = 0.0
var _smoothed_track_y: float = 0.0
var _prev_anchor: Vector3 = Vector3.ZERO
var _anchor_vel: Vector3 = Vector3.ZERO
var _smoothed_vel_lead: Vector3 = Vector3.ZERO
var _smoothed_bank_roll: float = 0.0
var _has_anchor: bool = false
var _current_level_idx: int = 0
var _roll_tick_accum: float = 0.0

func _ready() -> void:
	var default_dist := _get_mode_follow_distance()
	_target_zoom_distance = clampf(default_dist, min_zoom_distance, max_zoom_distance)
	_current_zoom_distance = _target_zoom_distance

	_setup_lighting_if_needed()
	_setup_camera()
	_setup_hud()
	_setup_sound()
	_setup_dust()

	if player_stack != null:
		player_stack.target_lock_changed.connect(func(_id: int, _blob_name: String, is_locked: bool) -> void:
			if _hud != null:
				_hud.set_reticle_locked(is_locked)
		)
		player_stack.blob_ejected.connect(func(_id: int, _name: String, _is_roll: bool) -> void:
			_refresh_stack_hud()
		)
		player_stack.blob_reabsorbed.connect(func(_id: int, _name: String, _was_recalling: bool) -> void:
			_refresh_stack_hud()
		)
		player_stack.blob_void_died.connect(func(_id: int, _name: String) -> void:
			_refresh_stack_hud()
		)
		player_stack.stack_swap_completed.connect(func(_id: int, _name: String) -> void:
			_refresh_stack_hud()
		)
		player_stack.stack_respawned.connect(func() -> void:
			_has_anchor = false
			_smoothed_boost_ratio = 0.0
			_reset_level_contraptions()
			_refresh_stack_hud()
			_dust.clear_all()
		)
		_refresh_stack_hud()

func _reset_level_contraptions() -> void:
	for node: Node in find_children("*", "", true, false):
		if node.has_method("reset_gate"):
			node.call("reset_gate")
		elif node.has_method("reset_scale"):
			node.call("reset_scale")
		elif node.has_method("reset_cannon"):
			node.call("reset_cannon")
		elif node.has_method("reset_block"):
			node.call("reset_block")
		elif node.has_method("reset_powerup"):
			node.call("reset_powerup")

func get_sound_engine() -> SoundEngine:
	return _sound

func _setup_sound() -> void:
	_sound = get_node_or_null("SoundEngine") as SoundEngine
	if _sound == null:
		_sound = SoundEngine.new()
		_sound.name = "SoundEngine"
		add_child(_sound)

	if player_stack != null:
		player_stack.jumped.connect(func(stack_count: int, is_air_combo: bool) -> void:
			var pitch := (1.16 if is_air_combo else 1.0) + float(3 - stack_count) * 0.06
			_sound.play(&"jump", 0.9, pitch)
		)
		player_stack.long_jumped.connect(func(stack_count: int) -> void:
			var pitch := 1.14 + float(3 - stack_count) * 0.06
			_sound.play(&"jump", 0.98, pitch)
			_sound.play(&"tube_shoot", 0.55, 1.25)
		)
		player_stack.skid_started.connect(func(_origin: Vector3, _skid_dir: Vector3) -> void:
			_sound.play(&"ui_slide", 0.72, 0.78)
		)
		player_stack.landed.connect(func(impact_speed: float, stack_count: int) -> void:
			var vol := clampf(impact_speed / 18.0, 0.25, 1.0)
			var pitch := 0.92 + float(3 - stack_count) * 0.07
			_sound.play(&"land", vol, pitch)
		)
		player_stack.bounced.connect(func(speed: float) -> void:
			_sound.play(&"bounce", clampf(speed / 16.0, 0.2, 0.9))
		)
		player_stack.blob_ejected.connect(func(_id: int, _name: String, is_roll: bool) -> void:
			_sound.play(&"roll_start" if is_roll else &"eject", 0.95)
		)
		player_stack.blob_reabsorbed.connect(func(_id: int, _name: String, was_recalling: bool) -> void:
			_sound.play(&"recall", 0.85 if was_recalling else 0.7, 1.05 if was_recalling else 0.95)
		)
		player_stack.stack_swap_completed.connect(func(_id: int, _name: String) -> void:
			_sound.play(&"tube_shoot", 0.85, 1.12)
		)
		player_stack.blob_void_died.connect(func(_id: int, _name: String) -> void:
			_sound.play(&"explode", 0.75)
		)
		player_stack.stack_respawned.connect(func() -> void:
			_sound.stop_roll_hum(0.05)
			_roll_tick_accum = 0.0
			_sound.play(&"ui_back", 0.75)
		)
		player_stack.target_lock_changed.connect(func(_id: int, _blob_name: String, is_locked: bool) -> void:
			if is_locked:
				_sound.play(&"ui_hover", 0.55, 1.15)
		)

	if _hud != null:
		_hud.mute_toggled.connect(func(muted: bool) -> void:
			_sound.set_muted(muted)
			if not muted:
				_sound.play(&"ui_click", 0.8)
		)
		_hud.level_selected.connect(func(_idx: int) -> void:
			_sound.play(&"ui_click", 0.85)
		)
		_hud.next_level_requested.connect(func() -> void:
			_sound.play(&"win", 0.9)
		)
		_hud.restart_requested.connect(func() -> void:
			_sound.play(&"ui_back", 0.85)
		)

func toggle_camera_mode() -> void:
	camera_mode = CameraFeelMode.CINEMATIC_FLUID if camera_mode == CameraFeelMode.SNAPPY else CameraFeelMode.SNAPPY
	_target_zoom_distance = clampf(_get_mode_follow_distance(), min_zoom_distance, max_zoom_distance)
	if _sound != null:
		_sound.play(&"ui_slide", 0.65)

func _get_mode_follow_distance() -> float:
	return fluid_follow_distance if camera_mode == CameraFeelMode.CINEMATIC_FLUID else snappy_follow_distance

func _refresh_stack_hud() -> void:
	if _hud != null and player_stack != null:
		_hud.update_stack_status(player_stack.get_stack_statuses())

func _setup_hud() -> void:
	_hud = GameHUD.new()
	_hud.name = "GameHUD"
	add_child(_hud)

	_hud.level_selected.connect(func(idx: int) -> void:
		_current_level_idx = idx
		if player_stack != null:
			player_stack.respawn(Vector3.ZERO)
	)
	_hud.next_level_requested.connect(func() -> void:
		_current_level_idx = (_current_level_idx + 1) % GameHUD.COURSES.size()
		_hud.set_selected_level(_current_level_idx)
		if player_stack != null:
			player_stack.respawn(Vector3.ZERO)
	)
	_hud.restart_requested.connect(func() -> void:
		if player_stack != null:
			player_stack.respawn(Vector3.ZERO)
	)
	_hud.gameplay_resumed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _sound != null:
			_sound.play(&"ui_click", 0.75)
	)

func _setup_lighting_if_needed() -> void:
	if find_child("WorldEnvironment", true, false) == null:
		var world_env := WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("334155")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("e2e8f0")
		env.ambient_light_energy = 0.65
		world_env.environment = env
		add_child(world_env)

func _setup_dust() -> void:
	_dust = get_node_or_null("DustParticles") as DustParticles
	if _dust == null:
		_dust = DustParticles.new()
		_dust.name = "DustParticles"
		add_child(_dust)
	if player_stack != null:
		_dust.bind_to_player_stack(player_stack)

func _setup_camera() -> void:
	_camera = find_child("Camera3D", true, false) as Camera3D
	_camera_rig = get_node_or_null("CameraRig") as Node3D
	if _camera_rig == null:
		_camera_rig = Node3D.new()
		_camera_rig.name = "CameraRig"
		add_child(_camera_rig)

	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera_rig.add_child(_camera)
	elif _camera.get_parent() != _camera_rig:
		_camera.reparent(_camera_rig)

	_camera.fov = snappy_base_fov if camera_mode == CameraFeelMode.SNAPPY else fluid_base_fov
	_camera.current = true

func _sweep_camera_segment(from_pos: Vector3, to_pos: Vector3, margin: float, exclude_rids: Array[RID]) -> Vector3:
	var segment := to_pos - from_pos
	var dist := segment.length()
	if dist <= 0.001:
		return from_pos

	var dir := segment / dist
	var sphere := SphereShape3D.new()
	sphere.radius = margin

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from_pos)
	query.motion = dir * dist
	query.exclude = exclude_rids
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	if fractions.size() >= 2:
		var safe_t := clampf(fractions[1] - 0.02, 0.0, 1.0)
		return from_pos + dir * (dist * safe_t)

	return to_pos

func _resolve_wall_safe_camera(center_pivot: Vector3, desired_shoulder_pivot: Vector3, desired_cam_pos: Vector3) -> Vector3:
	var exclude_rids: Array[RID] = []
	if player_stack != null:
		for child in player_stack.get_children():
			if child is CollisionObject3D:
				exclude_rids.append((child as CollisionObject3D).get_rid())

	var safe_shoulder := _sweep_camera_segment(center_pivot, desired_shoulder_pivot, camera_collision_margin, exclude_rids)
	return _sweep_camera_segment(safe_shoulder, desired_cam_pos, camera_collision_margin, exclude_rids)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if _hud != null:
				_hud.toggle_pause()
			if _sound != null:
				_sound.play(&"ui_back", 0.75)
			return

	if _hud != null and _hud.is_gameplay_blocked():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_target_yaw -= event.relative.x * orbit_sensitivity
		_target_pitch = clampf(_target_pitch - event.relative.y * orbit_sensitivity, -0.75, 0.85)
		_manual_orbit_yield_timer = 0.50
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom_distance = clampf(_target_zoom_distance - zoom_step, min_zoom_distance, max_zoom_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom_distance = clampf(_target_zoom_distance + zoom_step, min_zoom_distance, max_zoom_distance)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_V or event.physical_keycode == KEY_TAB:
			toggle_camera_mode()
		elif event.physical_keycode == KEY_Q or (InputMap.has_action("center_camera") and event.is_action_pressed("center_camera")):
			_target_yaw = 0.0
			_target_pitch = -0.16
			_target_zoom_distance = clampf(_get_mode_follow_distance(), min_zoom_distance, max_zoom_distance)
			_manual_orbit_yield_timer = 0.50
			if _sound != null:
				_sound.play(&"ui_slide", 0.55, 1.1)

func _step_critically_damped_spring_xz(current: Vector3, vel: Vector3, target: Vector3, freq: float, delta: float) -> Array[Vector3]:
	var omega := freq
	var x := omega * delta
	var exp_term := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change_x := current.x - target.x
	var change_z := current.z - target.z
	var temp_x := (vel.x + omega * change_x) * delta
	var temp_z := (vel.z + omega * change_z) * delta
	var next_vx := (vel.x - omega * temp_x) * exp_term
	var next_vz := (vel.z - omega * temp_z) * exp_term
	var next_x := target.x + (change_x + temp_x) * exp_term
	var next_z := target.z + (change_z + temp_z) * exp_term
	return [
		Vector3(next_x, target.y, next_z),
		Vector3(next_vx, 0.0, next_vz)
	]

func _physics_process(delta: float) -> void:
	if player_stack == null:
		return

	_manual_orbit_yield_timer = maxf(0.0, _manual_orbit_yield_timer - delta)

	var blocked := _hud != null and _hud.is_gameplay_blocked()
	if not blocked:
		var orbit_x := 0.0
		var orbit_y := 0.0
		if InputMap.has_action("orbit_left") and InputMap.has_action("orbit_right"):
			orbit_x = Input.get_axis("orbit_right", "orbit_left")
		if InputMap.has_action("orbit_up") and InputMap.has_action("orbit_down"):
			orbit_y = Input.get_axis("orbit_up", "orbit_down")

		if is_zero_approx(orbit_x):
			if Input.is_physical_key_pressed(KEY_J):
				orbit_x += 1.0
			if Input.is_physical_key_pressed(KEY_L):
				orbit_x -= 1.0
		if is_zero_approx(orbit_y):
			if Input.is_physical_key_pressed(KEY_I):
				orbit_y -= 1.0
			if Input.is_physical_key_pressed(KEY_K):
				orbit_y += 1.0

		if not is_zero_approx(orbit_x) or not is_zero_approx(orbit_y):
			_manual_orbit_yield_timer = 0.50

		_target_yaw += orbit_x * key_orbit_speed * delta
		_target_pitch = clampf(_target_pitch + orbit_y * key_orbit_speed * delta, -0.75, 0.85)

		player_stack.step_stack(delta, _target_yaw, _camera)

	# Continuous sprint-roll hum & rhythmic roll ticks
	if _sound != null:
		var horiz_speed := Vector2(player_stack._leader_vel.x, player_stack._leader_vel.z).length()
		var rolling_on_ground := player_stack._is_sprint_rolling and player_stack._is_grounded and horiz_speed > 2.0 and not blocked
		if rolling_on_ground:
			_sound.start_roll_hum(0.14)
			var speed_ratio := clampf(horiz_speed / player_stack.sprint_roll_speed, 0.2, 1.2)
			_sound.set_roll_hum_volume(0.08 + 0.14 * speed_ratio, 0.85 + 0.35 * speed_ratio)
			_roll_tick_accum += horiz_speed * delta
			if _roll_tick_accum >= 2.6:
				_roll_tick_accum = 0.0
				_sound.play(&"roll_tick", 0.35 * speed_ratio, 0.92 + 0.18 * speed_ratio)
		else:
			_sound.stop_roll_hum(0.14)
			_roll_tick_accum = 0.0

	var is_fluid := camera_mode == CameraFeelMode.CINEMATIC_FLUID
	var mode_dist := fluid_follow_distance if is_fluid else snappy_follow_distance
	var mode_shoulder := fluid_shoulder_offset_x if is_fluid else snappy_shoulder_offset_x
	var mode_pivot_h := fluid_pivot_height if is_fluid else snappy_pivot_height
	var mode_look_h := fluid_look_ahead_height if is_fluid else snappy_look_ahead_height
	var mode_look_fwd := fluid_look_ahead_forward if is_fluid else snappy_look_ahead_forward
	var vel_lead_scale := fluid_velocity_lead if is_fluid else snappy_velocity_lead
	var spring_freq := fluid_spring_freq if is_fluid else snappy_spring_freq
	var v_smooth := fluid_vert_smooth if is_fluid else snappy_vert_smooth
	var orbit_smooth := fluid_orbit_smooth if is_fluid else snappy_orbit_smooth
	var zoom_smooth := fluid_zoom_smooth if is_fluid else snappy_zoom_smooth
	var max_bank_deg := fluid_bank_roll_deg if is_fluid else snappy_bank_roll_deg
	var base_fov := fluid_base_fov if is_fluid else snappy_base_fov
	var boost_fov := fluid_boost_fov if is_fluid else snappy_boost_fov

	var raw_anchor := player_stack.get_leader_position()
	if not _has_anchor:
		_spring_follow_pos = raw_anchor
		_spring_follow_vel = Vector3.ZERO
		_grounded_base_y = raw_anchor.y
		_smoothed_track_y = raw_anchor.y
		_prev_anchor = raw_anchor
		_anchor_vel = Vector3.ZERO
		_has_anchor = true
	else:
		var inst_vel := (raw_anchor - _prev_anchor) / maxf(0.0001, delta)
		_prev_anchor = raw_anchor
		_anchor_vel = _anchor_vel.lerp(inst_vel, 1.0 - exp(-12.0 * delta))

		# Critically damped spring lag on XZ so blobs surge forward when accelerating/boosting
		var spring_res := _step_critically_damped_spring_xz(_spring_follow_pos, _spring_follow_vel, raw_anchor, spring_freq, delta)
		_spring_follow_pos = spring_res[0]
		_spring_follow_vel = spring_res[1]

		# Grounded Vertical Hysteresis: anchor Y baseline to last grounded floor within deadzone
		if player_stack._is_grounded:
			_grounded_base_y = lerpf(_grounded_base_y, raw_anchor.y, 1.0 - exp(-11.0 * delta))
		else:
			if raw_anchor.y > _grounded_base_y + vertical_deadzone_up:
				_grounded_base_y = lerpf(_grounded_base_y, raw_anchor.y - vertical_deadzone_up, 1.0 - exp(-7.5 * delta))
			elif raw_anchor.y < _grounded_base_y - vertical_deadzone_down:
				_grounded_base_y = lerpf(_grounded_base_y, raw_anchor.y + vertical_deadzone_down, 1.0 - exp(-9.5 * delta))

		_smoothed_track_y = lerpf(_smoothed_track_y, _grounded_base_y, 1.0 - exp(-v_smooth * delta))

	# Subtle movement-assisted yaw when strafing perpendicular to camera (yields instantly on mouse move)
	var pre_yaw_basis := Basis(Vector3.UP, _current_yaw)
	var pre_right := pre_yaw_basis.x
	var horiz_vel := Vector3(player_stack._leader_vel.x, 0.0, player_stack._leader_vel.z)
	var horiz_spd := horiz_vel.length()
	if _manual_orbit_yield_timer <= 0.0 and not blocked and horiz_spd > 2.5 and not player_stack._is_skidding:
		var strafe_ratio := clampf(horiz_vel.dot(pre_right) / player_stack.sprint_roll_speed, -1.0, 1.0)
		_target_yaw -= strafe_ratio * strafe_orbit_assist_speed * delta

	# Keep mouse/key orbit nearly 1:1 responsive in both Snappy and Fluid modes
	_current_yaw = lerp_angle(_current_yaw, _target_yaw, 1.0 - exp(-orbit_smooth * delta))
	_current_pitch = lerpf(_current_pitch, _target_pitch, 1.0 - exp(-orbit_smooth * delta))
	_current_zoom_distance = lerpf(_current_zoom_distance, _target_zoom_distance, 1.0 - exp(-zoom_smooth * delta))
	var zoom_ratio := clampf(_current_zoom_distance / maxf(0.1, mode_dist), 0.65, 1.85)

	var shake := player_stack.camera_shake_offset
	var yaw_basis := Basis(Vector3.UP, _current_yaw)
	var right_vec := yaw_basis.x
	var forward_vec := -yaw_basis.z

	var target_vel_lead := horiz_vel * vel_lead_scale
	var strafe_speed := horiz_vel.dot(right_vec)
	var yaw_rate := clampf(wrapf(_current_yaw - _prev_yaw, -PI, PI) / maxf(0.0001, delta), -4.0, 4.0)
	var curve_bank := player_stack._turn_bank_angle * (14.0 if is_fluid else 7.5)
	var target_bank := deg_to_rad(clampf(-strafe_speed * 0.14 - yaw_rate * 0.35 - curve_bank, -max_bank_deg, max_bank_deg))
	_prev_yaw = _current_yaw

	_smoothed_vel_lead = _smoothed_vel_lead.lerp(target_vel_lead, 1.0 - exp(-8.0 * delta))
	_smoothed_bank_roll = lerpf(_smoothed_bank_roll, target_bank, 1.0 - exp(-9.5 * delta))

	var target_boost_ratio: float = player_stack.get_speed_fov_ratio() if player_stack.has_method("get_speed_fov_ratio") else (1.0 if player_stack.is_high_speed_state() else 0.0)
	var boost_rate: float = (6.5 if is_fluid else 9.0) if target_boost_ratio > _smoothed_boost_ratio else (2.8 if is_fluid else 3.8)
	_smoothed_boost_ratio = lerpf(_smoothed_boost_ratio, target_boost_ratio, 1.0 - exp(-boost_rate * delta))

	var tracked_anchor := Vector3(_spring_follow_pos.x, _smoothed_track_y, _spring_follow_pos.z)
	var active_shoulder := mode_shoulder * lerpf(0.82, 1.25, clampf((zoom_ratio - 0.65) / 1.2, 0.0, 1.0))
	var up_aim_lift := maxf(0.0, _current_pitch) * 0.95

	var center_pivot := Vector3(raw_anchor.x, _smoothed_track_y, raw_anchor.z) + Vector3.UP * (mode_pivot_h + up_aim_lift)
	var desired_shoulder_pivot := (
		tracked_anchor
		+ _smoothed_vel_lead * 0.45
		+ Vector3.UP * (mode_pivot_h + up_aim_lift)
		+ right_vec * active_shoulder
		+ shake
	)

	var rot := Basis.from_euler(Vector3(_current_pitch, _current_yaw, 0.0))
	var dyn_dist := _current_zoom_distance + (1.45 if is_fluid else 0.95) * _smoothed_boost_ratio
	var desired_cam_pos := desired_shoulder_pivot + rot * Vector3(0.0, 0.0, dyn_dist)
	var safe_cam_pos := _resolve_wall_safe_camera(center_pivot, desired_shoulder_pivot, desired_cam_pos)

	var pitch_aim_y := tan(_current_pitch) * 7.2
	var look_target := (
		tracked_anchor
		+ _smoothed_vel_lead
		+ Vector3.UP * (mode_look_h + pitch_aim_y)
		+ right_vec * (active_shoulder * 0.9)
		+ forward_vec * mode_look_fwd
		+ shake * 0.6
	)

	_camera_rig.global_position = desired_shoulder_pivot
	_camera.global_position = safe_cam_pos
	_camera.look_at(look_target, Vector3.UP)
	if absf(_smoothed_bank_roll) > 0.0001:
		_camera.rotate_object_local(Vector3.FORWARD, _smoothed_bank_roll)

	_camera.fov = lerpf(base_fov, boost_fov, _smoothed_boost_ratio)