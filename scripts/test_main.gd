extends Node3D

@onready var player_stack: PlayerStack = get_node_or_null("PlayerStack") as PlayerStack

@export var orbit_sensitivity: float = 0.004
@export var key_orbit_speed: float = 2.2
@export var follow_height: float = 4.5
@export var follow_distance: float = 11.0
@export var camera_smooth_speed: float = 18.0

var _camera_rig: Node3D
var _camera: Camera3D
var _reticle: ColorRect
var _yaw: float = 0.0
var _pitch: float = -0.25
var _smoothed_anchor: Vector3 = Vector3.ZERO
var _has_anchor: bool = false

func _ready() -> void:
	_setup_lighting_if_needed()
	_setup_camera()
	_setup_reticle()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if player_stack != null:
		player_stack.target_lock_changed.connect(func(_id: int, _blob_name: String, is_locked: bool) -> void:
			if _reticle != null:
				_reticle.color = Color("38bdf8") if is_locked else Color(1.0, 1.0, 1.0, 0.75)
				_reticle.scale = Vector2(1.4, 1.4) if is_locked else Vector2.ONE
		)
		player_stack.stack_swap_completed.connect(func(_id: int, blob_name: String) -> void:
			print("[StackSwap] Swooped onto ", blob_name, " as new base driver!")
		)
		player_stack.blob_void_died.connect(func(_id: int, blob_name: String) -> void:
			print("[VoidDeath] ", blob_name, " fell into the void.")
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

func _setup_reticle() -> void:
	_reticle = find_child("Reticle", true, false) as ColorRect
	if _reticle == null:
		var hud := CanvasLayer.new()
		hud.name = "HUD"
		add_child(hud)

		_reticle = ColorRect.new()
		_reticle.name = "Reticle"
		_reticle.size = Vector2(8, 8)
		_reticle.pivot_offset = Vector2(4, 4)
		_reticle.set_anchors_preset(Control.PRESET_CENTER)
		_reticle.offset_left = -4
		_reticle.offset_top = -4
		_reticle.offset_right = 4
		_reticle.offset_bottom = 4
		_reticle.color = Color(1.0, 1.0, 1.0, 0.75)
		_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_reticle)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch - event.relative.y * orbit_sensitivity, -1.1, 0.65)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q or (InputMap.has_action("center_camera") and event.is_action_pressed("center_camera")):
			_yaw = 0.0
			_pitch = -0.25
		elif event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	if player_stack == null:
		return

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
	_pitch = clampf(_pitch + orbit_y * key_orbit_speed * delta, -1.1, 0.65)

	player_stack.step_stack(delta, _yaw, _camera)

	var target_anchor := player_stack.get_leader_position()
	if not _has_anchor:
		_smoothed_anchor = target_anchor
		_has_anchor = true
	else:
		_smoothed_anchor = _smoothed_anchor.lerp(target_anchor, 1.0 - exp(-camera_smooth_speed * delta))

	var shake := player_stack.camera_shake_offset
	var rot := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var offset := rot * Vector3(0.0, 0.0, follow_distance)

	_camera_rig.global_position = _smoothed_anchor + Vector3(0.0, follow_height * 0.45, 0.0) + shake
	_camera.global_position = _camera_rig.global_position + offset
	_camera.look_at(_smoothed_anchor + Vector3(0.0, 1.0, 0.0) + shake * 0.6, Vector3.UP)
