extends Node3D

@onready var player_stack: PlayerStack = get_node_or_null("PlayerStack") as PlayerStack

@export_group("Camera Framing & Zoom")
@export var orbit_sensitivity: float = 0.0036
@export var key_orbit_speed: float = 2.2
@export var follow_distance: float = 7.2
@export var min_zoom_distance: float = 4.2
@export var max_zoom_distance: float = 15.0
@export var zoom_step: float = 0.95
@export var zoom_smooth_speed: float = 14.0
@export var shoulder_offset_x: float = 1.05
@export var pivot_height: float = 1.45
@export var look_ahead_height: float = 1.85
@export var look_ahead_forward: float = 2.0
@export var base_fov: float = 72.0
@export var boost_fov: float = 80.0
@export var camera_smooth_speed: float = 18.0
@export var camera_collision_margin: float = 0.35

var _camera_rig: Node3D
var _camera: Camera3D
var _hud: GameHUD
var _yaw: float = 0.0
var _pitch: float = -0.16
var _target_zoom_distance: float = 7.2
var _current_zoom_distance: float = 7.2
var _smoothed_anchor: Vector3 = Vector3.ZERO
var _has_anchor: bool = false
var _current_level_idx: int = 0

func _ready() -> void:
	_target_zoom_distance = clampf(follow_distance, min_zoom_distance, max_zoom_distance)
	_current_zoom_distance = _target_zoom_distance

	_setup_lighting_if_needed()
	_setup_camera()
	_setup_hud()

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
			_refresh_stack_hud()
		)
		_refresh_stack_hud()

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

	_camera.fov = base_fov
	_camera.current = true

func _resolve_camera_collision(pivot_pos: Vector3, desired_cam_pos: Vector3) -> Vector3:
	var to_cam := desired_cam_pos - pivot_pos
	var dist := to_cam.length()
	if dist <= 0.001:
		return desired_cam_pos

	var dir := to_cam / dist
	var exclude_rids: Array[RID] = []
	if player_stack != null:
		for child in player_stack.get_children():
			if child is CollisionObject3D:
				exclude_rids.append((child as CollisionObject3D).get_rid())

	var sphere := SphereShape3D.new()
	sphere.radius = camera_collision_margin

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, pivot_pos)
	query.motion = dir * dist
	query.exclude = exclude_rids
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	if fractions.size() >= 2:
		var safe_t := maxf(0.22, fractions[1] - 0.03)
		return pivot_pos + dir * (dist * safe_t)

	return desired_cam_pos

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if _hud != null:
				_hud.toggle_pause()
			return

	if _hud != null and _hud.is_gameplay_blocked():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch - event.relative.y * orbit_sensitivity, -0.75, 0.85)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom_distance = clampf(_target_zoom_distance - zoom_step, min_zoom_distance, max_zoom_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom_distance = clampf(_target_zoom_distance + zoom_step, min_zoom_distance, max_zoom_distance)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q or (InputMap.has_action("center_camera") and event.is_action_pressed("center_camera")):
			_yaw = 0.0
			_pitch = -0.16
			_target_zoom_distance = clampf(follow_distance, min_zoom_distance, max_zoom_distance)

func _physics_process(delta: float) -> void:
	if player_stack == null:
		return

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

		_yaw += orbit_x * key_orbit_speed * delta
		_pitch = clampf(_pitch + orbit_y * key_orbit_speed * delta, -0.75, 0.85)

		player_stack.step_stack(delta, _yaw, _camera)

	_current_zoom_distance = lerpf(_current_zoom_distance, _target_zoom_distance, 1.0 - exp(-zoom_smooth_speed * delta))
	var zoom_ratio := clampf(_current_zoom_distance / maxf(0.1, follow_distance), 0.65, 1.85)

	var target_anchor := player_stack.get_leader_position()
	if not _has_anchor:
		_smoothed_anchor = target_anchor
		_has_anchor = true
	else:
		var h_t := 1.0 - exp(-camera_smooth_speed * delta)
		var v_t := 1.0 - exp(-(camera_smooth_speed * 0.72) * delta)
		_smoothed_anchor.x = lerpf(_smoothed_anchor.x, target_anchor.x, h_t)
		_smoothed_anchor.z = lerpf(_smoothed_anchor.z, target_anchor.z, h_t)
		_smoothed_anchor.y = lerpf(_smoothed_anchor.y, target_anchor.y, v_t)

	var shake := player_stack.camera_shake_offset
	var yaw_basis := Basis(Vector3.UP, _yaw)
	var right_vec := yaw_basis.x
	var forward_vec := -yaw_basis.z

	var active_shoulder := shoulder_offset_x * lerpf(0.82, 1.25, clampf((zoom_ratio - 0.65) / 1.2, 0.0, 1.0))
	var up_aim_lift := maxf(0.0, _pitch) * 0.95
	var rig_pos := (
		_smoothed_anchor
		+ Vector3.UP * (pivot_height + up_aim_lift)
		+ right_vec * active_shoulder
		+ shake
	)

	var rot := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var dyn_dist := _current_zoom_distance + (0.95 if player_stack.is_high_speed_state() else 0.0)
	var desired_offset := rot * Vector3(0.0, 0.0, dyn_dist)
	var desired_cam_pos := rig_pos + desired_offset
	var safe_cam_pos := _resolve_camera_collision(rig_pos, desired_cam_pos)

	var pitch_aim_y := tan(_pitch) * 7.2
	var look_target := (
		_smoothed_anchor
		+ Vector3.UP * (look_ahead_height + pitch_aim_y)
		+ right_vec * (active_shoulder * 0.9)
		+ forward_vec * look_ahead_forward
		+ shake * 0.6
	)

	_camera_rig.global_position = rig_pos
	_camera.global_position = safe_cam_pos
	_camera.look_at(look_target, Vector3.UP)

	var target_fov := boost_fov if player_stack.is_high_speed_state() else base_fov
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-10.0 * delta))