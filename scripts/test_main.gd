extends Node3D

@onready var player_stack: PlayerStack = get_node_or_null("PlayerStack") as PlayerStack

@export var orbit_sensitivity: float = 0.004
@export var key_orbit_speed: float = 2.2
@export var follow_height: float = 4.5
@export var follow_distance: float = 11.0
@export var camera_smooth_speed: float = 18.0
@export var camera_collision_margin: float = 0.35

var _camera_rig: Node3D
var _camera: Camera3D
var _hud: GameHUD
var _yaw: float = 0.0
var _pitch: float = -0.25
var _smoothed_anchor: Vector3 = Vector3.ZERO
var _has_anchor: bool = false
var _current_level_idx: int = 0

func _ready() -> void:
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
		var safe_t := maxf(0.05, fractions[1] - 0.02)
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
		_pitch = clampf(_pitch - event.relative.y * orbit_sensitivity, -0.95, 0.65)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q or (InputMap.has_action("center_camera") and event.is_action_pressed("center_camera")):
			_yaw = 0.0
			_pitch = -0.25

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
		_pitch = clampf(_pitch + orbit_y * key_orbit_speed * delta, -0.95, 0.65)

		player_stack.step_stack(delta, _yaw, _camera)

	var target_anchor := player_stack.get_leader_position()
	if not _has_anchor:
		_smoothed_anchor = target_anchor
		_has_anchor = true
	else:
		_smoothed_anchor = _smoothed_anchor.lerp(target_anchor, 1.0 - exp(-camera_smooth_speed * delta))

	var shake := player_stack.camera_shake_offset
	var rot := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var desired_offset := rot * Vector3(0.0, 0.0, follow_distance)

	var rig_pos := _smoothed_anchor + Vector3(0.0, follow_height * 0.45, 0.0) + shake
	var desired_cam_pos := rig_pos + desired_offset
	var safe_cam_pos := _resolve_camera_collision(rig_pos, desired_cam_pos)

	_camera_rig.global_position = rig_pos
	_camera.global_position = safe_cam_pos
	_camera.look_at(_smoothed_anchor + Vector3(0.0, 1.0, 0.0) + shake * 0.6, Vector3.UP)