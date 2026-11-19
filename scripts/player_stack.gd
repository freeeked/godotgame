extends Node3D
class_name PlayerStack

signal void_fell()
signal blob_ejected(blob_id: int, blob_name: String, is_roll: bool)
signal blob_reabsorbed(blob_id: int, blob_name: String, was_recalling: bool)
signal blob_void_died(blob_id: int, blob_name: String)
signal stack_respawned()
signal target_lock_changed(blob_id: int, blob_name: String, is_locked: bool)
signal stack_swap_completed(new_leader_id: int, new_leader_name: String)
signal jumped(stack_count: int, is_air_combo: bool)
signal landed(impact_speed: float, stack_count: int)
signal bounced(speed: float)

@export_group("Movement & Jump")
@export var move_speed: float = 12.5
@export var ground_accel: float = 180.0
@export var air_accel: float = 85.0
@export var ground_friction: float = 28.0
@export var air_friction: float = 2.5
@export var jump_force: float = 17.5
@export var gravity: float = 44.0
@export var terminal_velocity: float = 32.0
@export var coyote_time_max: float = 0.14
@export var jump_buffer_time_max: float = 0.10

@export_group("Sprint Roll")
@export var sprint_roll_speed: float = 19.5
@export var roll_spacing_factor: float = 0.72
@export var roll_spring_stiffness: float = 340.0
@export var roll_spring_damping: float = 23.0

@export_group("Eject & Roll Bottom")
@export var throw_forward_speed: float = 16.0
@export var throw_upward_speed: float = 14.0
@export var sprint_throw_forward_speed: float = 31.0
@export var sprint_throw_upward_speed: float = 16.5
@export var roll_forward_speed: float = 30.0
@export var sprint_roll_forward_speed: float = 48.0
@export var roll_upward_hop: float = 0.0
@export var bounce_restitution: float = 0.45

@export_group("Homing Recall (R)")
@export var recall_base_speed: float = 28.0
@export var recall_closing_margin: float = 24.0
@export var recall_max_speed: float = 58.0
@export var recall_spring_stiffness: float = 165.0
@export var recall_spring_damping: float = 17.0
@export var recall_initial_pop: float = 12.5

@export_group("Stack Swap Swoop (F)")
@export var max_target_distance: float = 48.0
@export var max_reticle_radius: float = 0.48
@export var stack_swap_cooldown_duration: float = 0.25
@export var swoop_target_glide_cap: float = 8.5
@export var post_swoop_air_pop: float = 11.5

@export_group("Stack & Springs")
@export var follower_spring_stiffness: float = 260.0
@export var follower_spring_damping: float = 17.0
@export var squash_spring_stiffness: float = 165.0
@export var squash_spring_damping: float = 12.5
@export var void_death_y: float = -12.0

class StackBlob:
	var id: int
	var blob_name: String
	var color: Color
	var radius: float
	var body: CharacterBody3D
	var col_shape: CollisionShape3D
	var pivot: Node3D
	var visual_root: Node3D
	var mesh_inst: MeshInstance3D
	var material: StandardMaterial3D
	var outline_mesh: MeshInstance3D
	var outline_mat: StandardMaterial3D
	var velocity: Vector3 = Vector3.ZERO
	var squash: Vector3 = Vector3.ZERO
	var spring_pos: Vector3 = Vector3.ZERO
	var spring_vel: Vector3 = Vector3.ZERO
	var is_grounded: bool = false
	var eject_cooldown: float = 0.0
	var is_rolling: bool = false
	var is_recalling: bool = false
	var recall_time: float = 0.0
	var recall_swoop_dir: Vector3 = Vector3.ZERO

var _all_nodes: Array[StackBlob] = []
var _active_nodes: Array[StackBlob] = []
var _ejected_nodes: Array[StackBlob] = []
var _dead_nodes: Dictionary = {}
var _locked_ejected_nodes: Dictionary = {}

var _highlighted_ejected_node: StackBlob = null
var _stack_swoop_target: StackBlob = null
var _stack_swoop_time: float = 0.0
var _stack_swoop_blocked_time: float = 0.0
var _stack_swoop_dir: Vector3 = Vector3.ZERO
var _stack_swap_cooldown: float = 0.0

var _leader_vel: Vector3 = Vector3.ZERO
var _facing_angle: float = PI
var _is_grounded: bool = false
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_held: bool = false
var _has_air_combo_jump: bool = false
var _last_camera: Camera3D = null

var _was_jump_down: bool = false
var _was_eject_down: bool = false
var _was_roll_down: bool = false
var _was_recall_down: bool = false
var _was_swap_down: bool = false

var _is_sprint_rolling: bool = false
var _roll_blend: float = 0.0
var _roll_spin_angle: float = 0.0
var _roll_entry_timer: float = 0.0
var _roll_exit_timer: float = 0.0
var _launch_momentum_timer: float = 0.0
var _elapsed: float = 0.0

var camera_shake_offset: Vector3 = Vector3.ZERO
var _camera_shake_vel: Vector3 = Vector3.ZERO

var _stack_hull_shape: CapsuleShape3D = null
var _stack_hull_node: CollisionShape3D = null

func _ready() -> void:
	_build_blobs()
	respawn(Vector3.ZERO)

func _build_blobs() -> void:
	var configs := [
		{"id": 0, "name": "Blue", "color": Color("2563eb"), "radius": 0.65},
		{"id": 1, "name": "Green", "color": Color("22c55e"), "radius": 0.72},
		{"id": 2, "name": "Pink", "color": Color("d946ef"), "radius": 0.62},
	]

	for cfg in configs:
		var blob := StackBlob.new()
		blob.id = cfg["id"]
		blob.blob_name = cfg["name"]
		blob.color = cfg["color"]
		blob.radius = cfg["radius"]

		var char_body := CharacterBody3D.new()
		char_body.name = "%sBlobBody" % blob.blob_name
		char_body.axis_lock_angular_x = true
		char_body.axis_lock_angular_y = true
		char_body.axis_lock_angular_z = true
		char_body.floor_stop_on_slope = false

		var col_shape := CollisionShape3D.new()
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = blob.radius * 0.85
		col_shape.shape = sphere_shape
		char_body.add_child(col_shape)

		var pivot := Node3D.new()
		pivot.name = "FacingPivot"
		char_body.add_child(pivot)

		var visual_root := Node3D.new()
		visual_root.name = "VisualRoot"
		pivot.add_child(visual_root)

		var mesh_inst := MeshInstance3D.new()
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = blob.radius
		sphere_mesh.height = blob.radius * 2.0
		sphere_mesh.radial_segments = 24
		sphere_mesh.rings = 16
		mesh_inst.mesh = sphere_mesh
		mesh_inst.scale = Vector3(1.08, 0.92, 1.08)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = blob.color
		mat.roughness = 0.4
		mat.metallic = 0.1
		mesh_inst.material_override = mat
		visual_root.add_child(mesh_inst)

		# Inverted-hull white reticle lock-on outline
		var outline_mesh := MeshInstance3D.new()
		var outline_sphere := SphereMesh.new()
		outline_sphere.radius = blob.radius * 1.15
		outline_sphere.height = blob.radius * 2.30
		outline_sphere.radial_segments = 24
		outline_sphere.rings = 16
		outline_mesh.mesh = outline_sphere
		outline_mesh.scale = Vector3(1.08, 0.92, 1.08)

		var outline_mat := StandardMaterial3D.new()
		outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		outline_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		outline_mesh.material_override = outline_mat
		outline_mesh.visible = false
		visual_root.add_child(outline_mesh)

		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = blob.radius * 0.12
		eye_mesh.height = blob.radius * 0.24
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color("111827")

		for side in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = eye_mesh
			eye.material_override = eye_mat
			eye.position = Vector3(side * blob.radius * 0.3, blob.radius * 0.15, blob.radius * 0.95)
			visual_root.add_child(eye)

		add_child(char_body)

		blob.body = char_body
		blob.col_shape = col_shape
		blob.pivot = pivot
		blob.visual_root = visual_root
		blob.mesh_inst = mesh_inst
		blob.material = mat
		blob.outline_mesh = outline_mesh
		blob.outline_mat = outline_mat

		_all_nodes.append(blob)

	for i in range(_all_nodes.size()):
		for j in range(i + 1, _all_nodes.size()):
			_all_nodes[i].body.add_collision_exception_with(_all_nodes[j].body)

	_active_nodes = _all_nodes.duplicate()
	_sync_collider_states()

func _get_standing_stack_height() -> float:
	if _active_nodes.is_empty():
		return 1.0
	var bottom := _active_nodes[0]
	var total_h := bottom.radius * 2.0
	for i in range(1, _active_nodes.size()):
		total_h += (_active_nodes[i - 1].radius + _active_nodes[i].radius) * 0.90
	return total_h

func _can_stand_up() -> bool:
	if _active_nodes.size() <= 1:
		return true
	var bottom := _active_nodes[0]
	var standing_h := _get_standing_stack_height()
	var col_r := bottom.radius * 0.82
	if standing_h <= col_r * 2.05:
		return true

	var feet_y := bottom.body.global_position.y - bottom.radius * 0.85
	var check_top_y := feet_y + standing_h - col_r
	var start_pos := Vector3(bottom.body.global_position.x, feet_y + col_r + 0.05, bottom.body.global_position.z)
	var motion_y := maxf(0.0, check_top_y - start_pos.y)
	if motion_y <= 0.01:
		return true

	var sphere := SphereShape3D.new()
	sphere.radius = col_r * 0.92
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, start_pos)
	query.motion = Vector3(0.0, motion_y, 0.0)
	query.exclude = _get_all_blob_rids()
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	return fractions.size() < 2 or fractions[1] >= 0.98

func _update_stack_hull_collider() -> void:
	if _active_nodes.is_empty():
		return
	var bottom := _active_nodes[0]
	if _stack_hull_node == null:
		_stack_hull_shape = CapsuleShape3D.new()
		_stack_hull_node = CollisionShape3D.new()
		_stack_hull_node.name = "StackHeightHull"
		_stack_hull_node.shape = _stack_hull_shape

	if _stack_hull_node.get_parent() != bottom.body:
		if _stack_hull_node.get_parent() != null:
			_stack_hull_node.get_parent().remove_child(_stack_hull_node)
		bottom.body.add_child(_stack_hull_node)

	var base_r := bottom.radius * 0.85
	var standing_h := _get_standing_stack_height()
	var current_h := lerpf(standing_h, base_r * 2.0, _roll_blend)

	_stack_hull_shape.radius = base_r
	_stack_hull_shape.height = maxf(base_r * 2.0, current_h)
	# Keep the bottom of the capsule aligned with the driver's feet so ramps/stairs feel identical
	_stack_hull_node.position = Vector3(0.0, (_stack_hull_shape.height * 0.5) - base_r, 0.0)
	_stack_hull_node.disabled = (_stack_swoop_target != null)

func _sync_collider_states() -> void:
	for idx in range(_active_nodes.size()):
		var b := _active_nodes[idx]
		b.body.visible = true
		b.col_shape.disabled = (idx != 0)

	for b in _ejected_nodes:
		var dead := _dead_nodes.has(b)
		b.body.visible = not dead
		b.col_shape.disabled = dead or b.is_recalling
	_update_stack_hull_collider()

func is_blob_dead(blob: StackBlob) -> bool:
	return _dead_nodes.has(blob)

func get_highlighted_ejected_blob() -> StackBlob:
	return _highlighted_ejected_node

func get_leader_position() -> Vector3:
	if _active_nodes.is_empty():
		return global_position
	return _active_nodes[0].body.global_position

func get_stack_center() -> Vector3:
	if _active_nodes.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for b in _active_nodes:
		sum += b.body.global_position
	return sum / float(_active_nodes.size())

func trigger_camera_shake(impulse: Vector3) -> void:
	_camera_shake_vel += impulse
	if _camera_shake_vel.length() > 1.2:
		_camera_shake_vel = _camera_shake_vel.normalized() * 1.2

func _update_camera_shake(delta: float) -> void:
	var stiffness := 110.0
	var damping := 22.0
	var force := -stiffness * camera_shake_offset - damping * _camera_shake_vel
	_camera_shake_vel += force * delta
	camera_shake_offset += _camera_shake_vel * delta
	if camera_shake_offset.length() > 0.14:
		camera_shake_offset = camera_shake_offset.normalized() * 0.14
	if camera_shake_offset.length_squared() < 0.000001 and _camera_shake_vel.length_squared() < 0.000001:
		camera_shake_offset = Vector3.ZERO
		_camera_shake_vel = Vector3.ZERO

func respawn(spawn_point: Vector3) -> void:
	_cancel_stack_swoop()
	_stack_swap_cooldown = 0.0
	_set_highlighted_target(null)
	_dead_nodes.clear()
	_locked_ejected_nodes.clear()
	_ejected_nodes.clear()

	_active_nodes = _all_nodes.duplicate()
	_active_nodes.sort_custom(func(a: StackBlob, b: StackBlob) -> bool: return a.id < b.id)

	_leader_vel = Vector3.ZERO
	_is_grounded = false
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_facing_angle = PI
	_is_sprint_rolling = false
	_roll_blend = 0.0
	_roll_spin_angle = 0.0
	_roll_entry_timer = 0.0
	_roll_exit_timer = 0.0
	_launch_momentum_timer = 0.0
	camera_shake_offset = Vector3.ZERO
	_camera_shake_vel = Vector3.ZERO

	var current_y := spawn_point.y
	for blob in _active_nodes:
		blob.body.visible = true
		blob.outline_mesh.visible = false
		blob.is_rolling = false
		blob.is_recalling = false
		blob.recall_time = 0.0
		blob.eject_cooldown = 0.0
		blob.velocity = Vector3.ZERO
		blob.squash = Vector3.ZERO
		blob.spring_pos = Vector3.ZERO
		blob.spring_vel = Vector3.ZERO
		blob.is_grounded = false
		blob.visual_root.scale = Vector3.ONE
		blob.pivot.rotation = Vector3(0.0, _facing_angle, 0.0)
		blob.visual_root.rotation = Vector3.ZERO
		blob.body.global_position = Vector3(
			spawn_point.x,
			current_y + blob.radius * 0.92,
			spawn_point.z
		)
		blob.body.velocity = Vector3.ZERO
		current_y += blob.radius * 1.85

	_sync_collider_states()
	stack_respawned.emit()

# --- Input Helpers ---

func _read_move_axes() -> Vector2:
	var x := 0.0
	var z := 0.0
	if InputMap.has_action("move_left") and Input.is_action_pressed("move_left"):
		x -= 1.0
	if InputMap.has_action("move_right") and Input.is_action_pressed("move_right"):
		x += 1.0
	if InputMap.has_action("move_forward") and Input.is_action_pressed("move_forward"):
		z -= 1.0
	if InputMap.has_action("move_back") and Input.is_action_pressed("move_back"):
		z += 1.0

	if is_zero_approx(x):
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			x += 1.0
	if is_zero_approx(z):
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			z -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			z += 1.0

	return Vector2(x, z)

func _read_jump_held() -> bool:
	return (InputMap.has_action("jump") and Input.is_action_pressed("jump")) or Input.is_physical_key_pressed(KEY_SPACE)

func _read_sprint_held() -> bool:
	return (InputMap.has_action("sprint_roll") and Input.is_action_pressed("sprint_roll")) or Input.is_physical_key_pressed(KEY_SHIFT)

func _read_eject_held() -> bool:
	return (InputMap.has_action("eject") and Input.is_action_pressed("eject")) or Input.is_physical_key_pressed(KEY_E)

func _read_roll_held() -> bool:
	var action_down := InputMap.has_action("roll_bottom") and Input.is_action_pressed("roll_bottom")
	return action_down or Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_CTRL)

func _read_recall_held() -> bool:
	return (InputMap.has_action("recall") and Input.is_action_pressed("recall")) or Input.is_physical_key_pressed(KEY_R)

func _read_swap_held() -> bool:
	return (InputMap.has_action("swap_swoop") and Input.is_action_pressed("swap_swoop")) or Input.is_physical_key_pressed(KEY_F)

# --- Main Fixed-Timestep Update ---

func step_stack(delta: float, camera_yaw: float, camera: Camera3D = null) -> void:
	_elapsed += delta
	if _active_nodes.is_empty():
		return

	_stack_swap_cooldown = maxf(0.0, _stack_swap_cooldown - delta)

	if camera != null:
		_last_camera = camera
		update_target_highlight(camera)

	var jump_down := _read_jump_held()
	var jump_just_pressed := jump_down and not _was_jump_down
	_was_jump_down = jump_down
	_jump_held = jump_down

	var eject_down := _read_eject_held()
	var eject_just_pressed := eject_down and not _was_eject_down
	_was_eject_down = eject_down

	var roll_down := _read_roll_held()
	var roll_just_pressed := roll_down and not _was_roll_down
	_was_roll_down = roll_down

	var recall_down := _read_recall_held()
	var recall_just_pressed := recall_down and not _was_recall_down
	_was_recall_down = recall_down

	var swap_down := _read_swap_held()
	var swap_just_pressed := swap_down and not _was_swap_down
	_was_swap_down = swap_down

	if jump_just_pressed:
		_jump_buffer_timer = jump_buffer_time_max
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	# Void check for base driver
	if _active_nodes[0].body.global_position.y < void_death_y:
		void_fell.emit()
		respawn(Vector3.ZERO)
		return

	# Update facing_angle from current frame input BEFORE eject/roll actions
	var axes := _read_move_axes()
	if _stack_swoop_target == null and (not is_zero_approx(axes.x) or not is_zero_approx(axes.y)):
		var sin_y := sin(camera_yaw)
		var cos_y := cos(camera_yaw)
		var world_x := cos_y * axes.x + (-sin_y) * (-axes.y)
		var world_z := (-sin_y) * axes.x + (-cos_y) * (-axes.y)
		if Vector2(world_x, world_z).length() > 0.0001:
			_facing_angle = atan2(world_x, world_z)

	if swap_just_pressed and _highlighted_ejected_node != null and _highlighted_ejected_node != _stack_swoop_target:
		initiate_stack_swap_swoop()

	if _stack_swoop_target == null:
		if eject_just_pressed:
			eject_top_character()
		if roll_just_pressed:
			roll_bottom_character()

	if recall_just_pressed:
		recall_all()

	if _stack_swoop_target != null:
		_update_stack_swoop(delta)
	else:
		_update_active_stack(delta, axes, camera_yaw)

	_update_ejected_characters(delta)
	_update_highlight_visuals()
	_update_camera_shake(delta)

# --- Reticle Target Lock & Stack-Swap Swoop (F) ---

func _set_highlighted_target(target: StackBlob) -> void:
	if _highlighted_ejected_node == target:
		return
	if _highlighted_ejected_node != null:
		_highlighted_ejected_node.outline_mesh.visible = false
	_highlighted_ejected_node = target
	if target != null:
		target.outline_mesh.visible = true
		target_lock_changed.emit(target.id, target.blob_name, true)
	else:
		target_lock_changed.emit(-1, "", false)

func update_target_highlight(camera: Camera3D) -> void:
	if (
		_stack_swoop_target != null
		and _ejected_nodes.has(_stack_swoop_target)
		and not _locked_ejected_nodes.has(_stack_swoop_target)
		and not _dead_nodes.has(_stack_swoop_target)
	):
		_set_highlighted_target(_stack_swoop_target)
		return

	if _active_nodes.is_empty() or _ejected_nodes.is_empty() or _stack_swap_cooldown > 0.0:
		_set_highlighted_target(null)
		return

	var driver := _active_nodes[0]
	var cam_pos := camera.global_position
	var cam_forward := -camera.global_transform.basis.z
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		_set_highlighted_target(null)
		return

	var best_blob: StackBlob = null
	var best_reticle_dist := max_reticle_radius
	var exclude_rids := _get_all_blob_rids()
	var space_state := get_world_3d().direct_space_state

	for b in _ejected_nodes:
		if _locked_ejected_nodes.has(b) or _dead_nodes.has(b) or b.is_recalling:
			continue

		var blob_pos := b.body.global_position
		if driver.body.global_position.distance_to(blob_pos) > max_target_distance:
			continue

		# Must be in front of camera
		var to_blob := blob_pos - cam_pos
		if to_blob.dot(cam_forward) <= 0.0:
			continue

		# Project to normalized NDC (-1..1) around screen center
		var screen_pos := camera.unproject_position(blob_pos)
		var ndc_x := (screen_pos.x / viewport_size.x) * 2.0 - 1.0
		var ndc_y := (screen_pos.y / viewport_size.y) * 2.0 - 1.0
		var reticle_dist := Vector2(ndc_x, ndc_y).length()
		if reticle_dist > best_reticle_dist:
			continue

		# Line-of-sight occlusion raycast from camera to blob
		var cam_to_blob_dist := to_blob.length()
		if cam_to_blob_dist > b.radius * 1.1:
			var ray_end := cam_pos + to_blob.normalized() * (cam_to_blob_dist - b.radius * 1.1)
			var ray_query := PhysicsRayQueryParameters3D.create(cam_pos, ray_end)
			ray_query.exclude = exclude_rids
			ray_query.collide_with_areas = false
			var hit := space_state.intersect_ray(ray_query)
			if not hit.is_empty():
				continue

		best_reticle_dist = reticle_dist
		best_blob = b

	_set_highlighted_target(best_blob)

func _update_highlight_visuals() -> void:
	var pulse := 0.5 + 0.5 * sin(_elapsed * 9.0)
	for b in _all_nodes:
		var is_target := (
			_highlighted_ejected_node == b
			and _ejected_nodes.has(b)
			and not _dead_nodes.has(b)
		)
		b.outline_mesh.visible = is_target
		if is_target:
			var outline_scale := 1.0 + pulse * 0.05
			b.outline_mesh.scale = Vector3(1.08, 0.92, 1.08) * outline_scale
			b.outline_mat.albedo_color.a = 0.78 + pulse * 0.17

func _is_swoop_path_occluded(from_pos: Vector3, to_pos: Vector3, target_radius: float) -> bool:
	var diff := to_pos - from_pos
	var dist := diff.length()
	if dist <= target_radius * 1.2:
		return false

	var ray_end := from_pos + diff.normalized() * (dist - target_radius * 0.9)
	var ray_query := PhysicsRayQueryParameters3D.create(from_pos, ray_end)
	ray_query.exclude = _get_all_blob_rids()
	ray_query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(ray_query)
	return not hit.is_empty()

func initiate_stack_swap_swoop() -> bool:
	if _stack_swap_cooldown > 0.0 or _active_nodes.is_empty():
		return false

	var target := _highlighted_ejected_node
	var bottom := _active_nodes[0]
	if (
		target == null
		or not _ejected_nodes.has(target)
		or _locked_ejected_nodes.has(target)
		or _dead_nodes.has(target)
		or target.is_recalling
	):
		return false

	# Clamp runaway sprint-roll glide speed on lock-on
	var target_horiz_spd := Vector2(target.velocity.x, target.velocity.z).length()
	if target_horiz_spd > swoop_target_glide_cap:
		var ratio := swoop_target_glide_cap / target_horiz_spd
		target.velocity.x *= ratio
		target.velocity.z *= ratio

	var landing_pos := Vector3(
		target.body.global_position.x,
		target.body.global_position.y + target.radius + bottom.radius * 0.92,
		target.body.global_position.z
	)
	var to_target := landing_pos - bottom.body.global_position
	var dist := to_target.length()
	if dist > 0.001:
		to_target /= dist
	else:
		to_target = Vector3(sin(_facing_angle), 0.5, cos(_facing_angle)).normalized()

	if dist <= target.radius + bottom.radius + 0.95:
		_complete_stack_swap_docking(target)
		return true

	_stack_swoop_target = target
	_stack_swap_cooldown = stack_swap_cooldown_duration
	_stack_swoop_time = 0.0
	_stack_swoop_blocked_time = 0.0

	var side_sign := 1.0 if randf() < 0.5 else -1.0
	var perp_x := -to_target.z * side_sign
	var perp_z := to_target.x * side_sign
	_stack_swoop_dir = Vector3(perp_x * 0.65, 0.75, perp_z * 0.65).normalized()

	var clamped_spd := Vector2(target.velocity.x, target.velocity.z).length()
	var launch_spd := clampf(dist * 1.35 + clamped_spd * 0.6, 20.0, 30.0)
	var upward_boost := (recall_initial_pop + to_target.y * 12.0) if to_target.y > 0.1 else (recall_initial_pop + 2.5)

	_leader_vel = Vector3(
		to_target.x * launch_spd + perp_x * 5.5,
		maxf(_leader_vel.y * 0.35, upward_boost),
		to_target.z * launch_spd + perp_z * 5.5
	)
	_is_grounded = false
	_coyote_timer = 0.0

	if Vector2(to_target.x, to_target.z).length() > 0.05:
		_facing_angle = atan2(to_target.x, to_target.z)

	for idx in range(_active_nodes.size()):
		var b := _active_nodes[idx]
		b.is_grounded = false
		b.pivot.rotation.y = _facing_angle
		_apply_squash(b, -0.24 + idx * 0.02, 0.28 - idx * 0.02)
		b.spring_vel.y = 18.0 + float(idx) * 2.5

	trigger_camera_shake(Vector3(-to_target.x * 0.45, 0.2, -to_target.z * 0.45))
	return true

func _cancel_stack_swoop() -> void:
	_stack_swoop_target = null
	_stack_swoop_time = 0.0
	_stack_swoop_blocked_time = 0.0
	_set_highlighted_target(null)
	for b in _active_nodes:
		b.visual_root.rotation.z = 0.0
		b.visual_root.rotation.x = 0.0

func _update_stack_swoop(delta: float) -> void:
	var bottom := _active_nodes[0]
	var target := _stack_swoop_target
	if (
		target == null
		or not _ejected_nodes.has(target)
		or _locked_ejected_nodes.has(target)
		or _dead_nodes.has(target)
		or target.is_recalling
	):
		_cancel_stack_swoop()
		return

	_is_sprint_rolling = _read_sprint_held()
	_roll_blend = lerpf(_roll_blend, 1.0 if _is_sprint_rolling else 0.0, 1.0 - exp(-26.0 * delta))

	_stack_swoop_time += delta

	var landing_pos := Vector3(
		target.body.global_position.x,
		target.body.global_position.y + target.radius + bottom.radius * 0.92,
		target.body.global_position.z
	)
	var raw_disp := landing_pos - bottom.body.global_position
	var dist := raw_disp.length()

	if dist <= target.radius + bottom.radius + 0.95:
		_complete_stack_swap_docking(target)
		return

	if _stack_swoop_time > 0.12 and _is_swoop_path_occluded(bottom.body.global_position, target.body.global_position, target.radius):
		_leader_vel.x *= 0.25
		_leader_vel.z *= 0.25
		_cancel_stack_swoop()
		return

	var lead_seconds := clampf(dist / 90.0, 0.01, 0.06)
	var predicted_target := landing_pos + target.velocity * lead_seconds

	var swoop_fade := exp(-_stack_swoop_time * 5.0) * clampf(dist / 5.0, 0.0, 1.0)
	var curved_target := predicted_target + _stack_swoop_dir * (swoop_fade * minf(4.0, dist * 0.36))
	var disp := curved_target - bottom.body.global_position

	var urgency := 1.0 + minf(2.4, _stack_swoop_time * 2.5)
	var stiffness := recall_spring_stiffness * urgency
	var damping := recall_spring_damping * (1.0 + minf(0.6, _stack_swoop_time * 0.7))

	var accel_vec := disp * stiffness - _leader_vel * damping
	_leader_vel += accel_vec * delta

	var target_spd := target.velocity.length()
	var min_closing := minf(
		recall_max_speed,
		maxf(recall_base_speed, target_spd + recall_closing_margin) + _stack_swoop_time * 18.0
	)

	var to_real_target := raw_disp.normalized()
	var closing_vel := _leader_vel.dot(to_real_target)
	if closing_vel < min_closing:
		var boost := minf(min_closing - closing_vel, 95.0 * delta)
		_leader_vel += to_real_target * boost

	var spd := _leader_vel.length()
	if spd > recall_max_speed:
		_leader_vel = _leader_vel.normalized() * recall_max_speed

	var pre_pos := bottom.body.global_position
	bottom.body.velocity = _leader_vel
	bottom.body.move_and_slide()
	_is_grounded = bottom.body.is_on_floor()
	_leader_vel = bottom.body.velocity

	var moved_dist := bottom.body.global_position.distance_to(pre_pos)
	var expected_dist := spd * delta
	if expected_dist > 0.001 and moved_dist < expected_dist * 0.25:
		_stack_swoop_blocked_time += delta
		if _stack_swoop_blocked_time >= 0.14:
			_leader_vel.x = 0.0
			_leader_vel.z = 0.0
			_cancel_stack_swoop()
			return
	else:
		_stack_swoop_blocked_time = 0.0

	var post_dist := bottom.body.global_position.distance_to(landing_pos)
	if post_dist <= target.radius + bottom.radius + 0.95:
		_complete_stack_swap_docking(target)
		return

	# Banking, pitch & aerodynamic stretch
	var horiz_spd := Vector2(_leader_vel.x, _leader_vel.z).length()
	if horiz_spd > 0.3:
		var target_yaw := atan2(_leader_vel.x, _leader_vel.z)
		_facing_angle = target_yaw
		var yaw_diff := fposmod(target_yaw - bottom.pivot.rotation.y + PI, TAU) - PI
		var bank_angle := clampf(-yaw_diff * 0.85, -0.55, 0.55)
		bottom.pivot.rotation.y = _lerp_angle(bottom.pivot.rotation.y, target_yaw, 18.0 * delta)
		bottom.visual_root.rotation.z = _lerp_angle(bottom.visual_root.rotation.z, bank_angle, 14.0 * delta)
	else:
		bottom.visual_root.rotation.z = _lerp_angle(bottom.visual_root.rotation.z, 0.0, 14.0 * delta)

	var target_pitch := clampf(-_leader_vel.y * 0.032, -0.65, 0.65)
	bottom.visual_root.rotation.x = _lerp_angle(bottom.visual_root.rotation.x, target_pitch, 18.0 * delta)

	var speed_ratio := clampf(spd / 36.0, 0.0, 1.0)
	var prox_squash := ((1.0 - post_dist / 2.2) * 0.12) if post_dist < 2.2 else 0.0
	var stretch := speed_ratio * 0.24 - prox_squash
	bottom.squash = bottom.squash.lerp(Vector3.ZERO, minf(1.0, 16.0 * delta))
	bottom.visual_root.scale = Vector3(
		1.0 - stretch * 0.45 + bottom.squash.x,
		1.0 - stretch * 0.45 + bottom.squash.y,
		1.0 + stretch + bottom.squash.z
	)

	_update_squash_springs(delta)

	var back_x := -sin(_facing_angle)
	var back_z := -cos(_facing_angle)
	for i in range(1, _active_nodes.size()):
		var ahead := _active_nodes[i - 1]
		var curr := _active_nodes[i]

		var spacing := (ahead.radius + curr.radius) * 0.68
		var target_x := ahead.body.global_position.x + back_x * spacing
		var target_y := ahead.body.global_position.y + (0.15 if _is_sprint_rolling else ahead.radius * 0.85 + curr.radius * 0.55)
		var target_z := ahead.body.global_position.z + back_z * spacing

		var follow_t := 1.0 - exp(-26.0 * delta)
		curr.body.global_position = curr.body.global_position.lerp(Vector3(target_x, target_y, target_z), follow_t)

		curr.pivot.rotation.y = _lerp_angle(curr.pivot.rotation.y, bottom.pivot.rotation.y, 18.0 * delta)
		curr.visual_root.rotation.x = _lerp_angle(curr.visual_root.rotation.x, target_pitch, 18.0 * delta)
		curr.visual_root.rotation.z = _lerp_angle(curr.visual_root.rotation.z, bottom.visual_root.rotation.z, 14.0 * delta)

		curr.squash = curr.squash.lerp(Vector3.ZERO, minf(1.0, 16.0 * delta))
		curr.visual_root.scale = Vector3(
			1.0 - stretch * 0.4 + curr.squash.x,
			1.0 - stretch * 0.4 + curr.squash.y,
			1.0 + stretch * 0.9 + curr.squash.z
		)

	if _stack_swoop_time > 2.6:
		_cancel_stack_swoop()

func _complete_stack_swap_docking(target_node: StackBlob) -> void:
	_stack_swoop_target = null
	_stack_swoop_time = 0.0
	_stack_swoop_blocked_time = 0.0
	_stack_swap_cooldown = stack_swap_cooldown_duration
	_set_highlighted_target(null)

	var ejected_idx := _ejected_nodes.find(target_node)
	if ejected_idx != -1:
		_ejected_nodes.remove_at(ejected_idx)

	var incoming_vel := _leader_vel
	var target_feet_y := target_node.body.global_position.y - target_node.radius * 0.92
	var anchor_x := target_node.body.global_position.x
	var anchor_z := target_node.body.global_position.z

	var carry_factor := 0.55 if _is_sprint_rolling else 0.42
	var carry_vx := target_node.velocity.x * 0.75 + incoming_vel.x * carry_factor
	var carry_vz := target_node.velocity.z * 0.75 + incoming_vel.z * carry_factor

	var max_carry := sprint_roll_speed if _is_sprint_rolling else move_speed * 1.15
	var carry_spd := Vector2(carry_vx, carry_vz).length()
	if carry_spd > max_carry:
		var ratio := max_carry / carry_spd
		carry_vx *= ratio
		carry_vz *= ratio

	if carry_spd > 2.0:
		_launch_momentum_timer = 0.22

	var docked_in_air := not target_node.is_grounded
	var air_pop_y := post_swoop_air_pop if docked_in_air else 0.0
	_leader_vel = Vector3(carry_vx, air_pop_y, carry_vz)
	_is_grounded = target_node.is_grounded
	_coyote_timer = coyote_time_max
	_has_air_combo_jump = docked_in_air
	if docked_in_air:
		_launch_momentum_timer = 0.28

	if Vector2(carry_vx, carry_vz).length() > 0.5:
		_facing_angle = atan2(carry_vx, carry_vz)

	_active_nodes.push_front(target_node)

	var impact_horiz := Vector2(incoming_vel.x, incoming_vel.z)
	if impact_horiz.length_squared() < 0.25:
		impact_horiz = Vector2(sin(_facing_angle), cos(_facing_angle))
	else:
		impact_horiz = impact_horiz.normalized()

	var jiggle_mag := 14.0
	var current_feet_y := target_feet_y
	var back_x := -sin(_facing_angle)
	var back_z := -cos(_facing_angle)
	var trail_dist := 0.0
	var total_count := float(_active_nodes.size())

	for idx in range(_active_nodes.size()):
		var b := _active_nodes[idx]
		var tier_ratio := float(idx + 1) / total_count
		var alt_sign := 1.0 if (idx % 2 == 0) else -1.0

		b.is_rolling = false
		b.is_recalling = false
		b.recall_time = 0.0
		b.eject_cooldown = 0.0
		b.visual_root.scale = Vector3.ONE
		b.pivot.rotation = Vector3(0.0, _facing_angle, 0.0)
		b.visual_root.rotation = Vector3.ZERO

		if _is_sprint_rolling and idx > 0:
			var prev := _active_nodes[idx - 1]
			trail_dist += (prev.radius + b.radius) * roll_spacing_factor
			b.body.global_position = Vector3(
				anchor_x + back_x * trail_dist,
				target_feet_y + b.radius * 0.92,
				anchor_z + back_z * trail_dist
			)
			b.velocity = Vector3(impact_horiz.x * jiggle_mag * 0.55, 0.0, impact_horiz.y * jiggle_mag * 0.55)
		else:
			b.body.global_position = Vector3(anchor_x, current_feet_y + b.radius * 0.92, anchor_z)
			b.velocity = Vector3(
				0.0 if idx == 0 else impact_horiz.x * jiggle_mag * 0.65 * tier_ratio,
				0.0,
				0.0 if idx == 0 else impact_horiz.y * jiggle_mag * 0.65 * tier_ratio
			)

		var squash_amt := 0.34 * (1.0 - float(idx) * 0.14)
		_apply_squash(b, squash_amt, -squash_amt * 0.92)
		b.spring_vel.y = 22.0 * (1.0 - float(idx) * 0.12)
		b.spring_vel.x = impact_horiz.x * jiggle_mag * 0.85 * alt_sign
		b.spring_vel.z = impact_horiz.y * jiggle_mag * 0.85 * alt_sign

		current_feet_y += b.radius * 1.85

	_sync_collider_states()
	trigger_camera_shake(Vector3(impact_horiz.x * 0.42, -0.28, impact_horiz.y * 0.42))
	stack_swap_completed.emit(target_node.id, target_node.blob_name)

func promote_to_base(target_node: StackBlob) -> void:
	if _dead_nodes.has(target_node):
		return
	if not _active_nodes.has(target_node) and not _ejected_nodes.has(target_node):
		return

	_set_highlighted_target(null)
	if _stack_swoop_target == target_node:
		_stack_swoop_target = null

	var ejected_idx := _ejected_nodes.find(target_node)
	var was_ejected := ejected_idx != -1

	var old_bottom := _active_nodes[0]
	var old_feet_y := old_bottom.body.global_position.y - old_bottom.radius * 0.92
	var target_feet_y := (target_node.body.global_position.y - target_node.radius * 0.92) if was_ejected else old_feet_y
	var anchor_x := target_node.body.global_position.x if was_ejected else old_bottom.body.global_position.x
	var anchor_z := target_node.body.global_position.z if was_ejected else old_bottom.body.global_position.z

	if was_ejected:
		_ejected_nodes.remove_at(ejected_idx)
		_leader_vel = Vector3(
			target_node.velocity.x * 0.65,
			maxf(target_node.velocity.y * 0.5, 4.0),
			target_node.velocity.z * 0.65
		)
		_is_grounded = false
	else:
		var active_idx := _active_nodes.find(target_node)
		if active_idx != -1:
			_active_nodes.remove_at(active_idx)

	_active_nodes.push_front(target_node)

	var current_feet_y := target_feet_y
	var back_x := -sin(_facing_angle)
	var back_z := -cos(_facing_angle)
	var trail_dist := 0.0

	for idx in range(_active_nodes.size()):
		var b := _active_nodes[idx]
		b.is_rolling = false
		b.is_recalling = false
		b.recall_time = 0.0
		b.velocity = Vector3.ZERO
		b.eject_cooldown = 0.0
		b.visual_root.scale = Vector3.ONE
		b.pivot.rotation = Vector3(0.0, _facing_angle, 0.0)
		b.visual_root.rotation = Vector3.ZERO
		if _is_sprint_rolling and idx > 0:
			var prev := _active_nodes[idx - 1]
			trail_dist += (prev.radius + b.radius) * roll_spacing_factor
			b.body.global_position = Vector3(
				anchor_x + back_x * trail_dist,
				target_feet_y + b.radius * 0.92,
				anchor_z + back_z * trail_dist
			)
		else:
			b.body.global_position = Vector3(anchor_x, current_feet_y + b.radius * 0.92, anchor_z)
		_apply_squash(b, 0.32 - float(idx) * 0.05, -0.28 + float(idx) * 0.04)
		current_feet_y += b.radius * 1.85

	_sync_collider_states()

# --- Eject Top (E) & Roll Bottom (C / Ctrl) ---

func _is_sphere_clearance_blocked(test_center: Vector3, check_radius: float, exclude_rids: Array[RID]) -> bool:
	var space_state := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = check_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, test_center)
	query.exclude = exclude_rids
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hits := space_state.intersect_shape(query, 1)
	return not hits.is_empty()

func _get_all_blob_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for b in _all_nodes:
		rids.append(b.body.get_rid())
	return rids

func _get_camera_aim_direction() -> Vector3:
	if _last_camera == null:
		return Vector3(sin(_facing_angle), 0.38, cos(_facing_angle)).normalized()

	var viewport_size := _last_camera.get_viewport().get_visible_rect().size
	var screen_center := viewport_size * 0.5
	var ray_origin := _last_camera.project_ray_origin(screen_center)
	var ray_dir := _last_camera.project_ray_normal(screen_center)

	# Raycast out to 45m to find what the crosshair is pointing at
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 45.0)
	query.exclude = _get_all_blob_rids()
	query.collide_with_areas = false
	var hit := space_state.intersect_ray(query)

	var aim_point: Vector3 = hit["position"] if not hit.is_empty() else (ray_origin + ray_dir * 28.0)
	var from_pos := _active_nodes[_active_nodes.size() - 1].body.global_position
	var to_aim := (aim_point - from_pos)
	if to_aim.length_squared() < 0.01:
		return ray_dir
	return to_aim.normalized()

func eject_top_character() -> StackBlob:
	if _active_nodes.size() <= 1:
		return null

	var top_node: StackBlob = _active_nodes.pop_back()
	var front_driver := _active_nodes[0]
	var stack_anchor: StackBlob = _active_nodes[_active_nodes.size() - 1]
	var is_sprint_launch := _is_sprint_rolling

	var aim_dir := _get_camera_aim_direction()
	var horiz_aim := Vector2(aim_dir.x, aim_dir.z)
	if horiz_aim.length() > 0.05:
		_facing_angle = atan2(aim_dir.x, aim_dir.z)

	var forward_x := sin(_facing_angle)
	var forward_z := cos(_facing_angle)

	var origin_node := front_driver if is_sprint_launch else stack_anchor
	var spawn_y := (front_driver.body.global_position.y + front_driver.radius * 0.45) if is_sprint_launch else (top_node.body.global_position.y + 0.15)
	var desired_offset := (front_driver.radius + top_node.radius * 0.55) if is_sprint_launch else 0.65

	var exclude_rids := _get_all_blob_rids()
	var safe_offset := 0.0
	var step_size := 0.08
	var d := step_size
	while d <= desired_offset + 0.001:
		var test_pos := Vector3(
			origin_node.body.global_position.x + forward_x * d,
			spawn_y,
			origin_node.body.global_position.z + forward_z * d
		)
		if _is_sphere_clearance_blocked(test_pos, top_node.radius * 0.85, exclude_rids):
			break
		safe_offset = d
		d += step_size

	top_node.body.global_position = Vector3(
		origin_node.body.global_position.x + forward_x * safe_offset,
		spawn_y,
		origin_node.body.global_position.z + forward_z * safe_offset
	)

	# Blend camera pitch into throw speed & upward arc so aiming up launches high and clean
	var pitch_up := clampf(aim_dir.y, -0.35, 0.92)
	var throw_speed := (32.0 if is_sprint_launch else 24.5) + maxf(0.0, pitch_up) * 8.0
	var arc_bonus := lerpf(5.5, 9.5, clampf((pitch_up + 0.2) / 1.1, 0.0, 1.0))
	var vel_carry := 0.55 if is_sprint_launch else 0.35

	top_node.velocity = Vector3(
		aim_dir.x * throw_speed + _leader_vel.x * vel_carry,
		maxf(6.5, aim_dir.y * throw_speed + arc_bonus) + maxf(0.0, _leader_vel.y * 0.3),
		aim_dir.z * throw_speed + _leader_vel.z * vel_carry
	)

	top_node.is_grounded = false
	top_node.is_rolling = false
	top_node.is_recalling = false
	top_node.recall_time = 0.0
	top_node.eject_cooldown = 0.35
	top_node.pivot.rotation = Vector3(0.0, _facing_angle, 0.0)
	top_node.visual_root.rotation = Vector3.ZERO

	_apply_squash(
		top_node,
		-0.32 if is_sprint_launch else -0.22,
		0.38 if is_sprint_launch else 0.28
	)

	var shake_power := 0.65 if is_sprint_launch else 0.40
	trigger_camera_shake(Vector3(-forward_x * shake_power, 0.22 if is_sprint_launch else 0.14, -forward_z * shake_power))

	for b in _active_nodes:
		_apply_squash(b, 0.32 if is_sprint_launch else 0.26, -0.28 if is_sprint_launch else -0.24)

	_ejected_nodes.append(top_node)
	_sync_collider_states()
	blob_ejected.emit(top_node.id, top_node.blob_name, false)
	return top_node

func _find_floor_y(at_pos: Vector3, fallback_feet_y: float, exclude_rids: Array[RID]) -> float:
	var space_state := get_world_3d().direct_space_state
	var ray_from := Vector3(at_pos.x, at_pos.y + 1.2, at_pos.z)
	var ray_to := Vector3(at_pos.x, fallback_feet_y - 0.6, at_pos.z)
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.exclude = exclude_rids
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		return (hit["position"] as Vector3).y
	return fallback_feet_y

func _get_camera_horizontal_forward() -> Vector3:
	if _last_camera != null:
		var cam_fwd := -_last_camera.global_transform.basis.z
		var flat_cam := Vector3(cam_fwd.x, 0.0, cam_fwd.z)
		if flat_cam.length_squared() > 0.0001:
			return flat_cam.normalized()

	return Vector3(sin(_facing_angle), 0.0, cos(_facing_angle)).normalized()

func roll_bottom_character() -> StackBlob:
	if _active_nodes.size() <= 1:
		return null

	var is_sprint_launch := _is_sprint_rolling
	var cam_fwd := _get_camera_horizontal_forward()
	var forward_x := cam_fwd.x
	var forward_z := cam_fwd.z
	_facing_angle = atan2(forward_x, forward_z)

	var exclude_rids := _get_all_blob_rids()

	var prev_driver := _active_nodes[0]
	var prev_col_r := prev_driver.radius * 0.85
	var anchor_x := prev_driver.body.global_position.x
	var anchor_z := prev_driver.body.global_position.z
	var raw_feet_y := prev_driver.body.global_position.y - prev_col_r
	var floor_y := _find_floor_y(prev_driver.body.global_position, raw_feet_y, exclude_rids) if _is_grounded else raw_feet_y

	var bottom_node: StackBlob = _active_nodes.pop_front()
	var new_driver := _active_nodes[0]
	var cur_horiz_speed := Vector2(_leader_vel.x, _leader_vel.z).length()

	var new_col_r := new_driver.radius * 0.85
	var ball_col_r := bottom_node.radius * 0.85

	# Keep new_driver at its exact current XZ (no horizontal teleporting when sprinting or turning)
	var driver_x := new_driver.body.global_position.x if is_sprint_launch else anchor_x
	var driver_z := new_driver.body.global_position.z if is_sprint_launch else anchor_z
	if _is_grounded:
		var driver_raw_feet := new_driver.body.global_position.y - new_col_r
		var driver_floor := _find_floor_y(Vector3(driver_x, new_driver.body.global_position.y, driver_z), driver_raw_feet, exclude_rids)
		new_driver.body.global_position = Vector3(driver_x, driver_floor + new_col_r + 0.02, driver_z)
	else:
		new_driver.body.global_position = Vector3(driver_x, new_driver.body.global_position.y if is_sprint_launch else (floor_y + new_col_r + 0.02), driver_z)

	# Sweep forward in the camera's horizontal direction up to desired_lead without clipping into walls
	var ball_center_y := floor_y + ball_col_r + 0.03
	var desired_lead := 0.55 if is_sprint_launch else (new_driver.radius + bottom_node.radius + 0.18)
	var safe_lead := 0.0
	var step_size := 0.06
	var d := step_size
	while d <= desired_lead + 0.001:
		var test_pos := Vector3(
			anchor_x + forward_x * d,
			ball_center_y,
			anchor_z + forward_z * d
		)
		if _is_sphere_clearance_blocked(test_pos, ball_col_r * 0.96, exclude_rids):
			break
		safe_lead = d
		d += step_size

	var spawn_x := anchor_x + forward_x * safe_lead
	var spawn_z := anchor_z + forward_z * safe_lead
	bottom_node.body.global_position = Vector3(spawn_x, ball_center_y, spawn_z)

	# Carry momentum only along the camera's bowl direction so side/back camera bowls stay crisp
	var forward_carry := maxf(0.0, _leader_vel.x * forward_x + _leader_vel.z * forward_z)
	var base_launch := sprint_roll_forward_speed if is_sprint_launch else roll_forward_speed
	var carry_factor := 0.75 if is_sprint_launch else 0.35
	var launch_speed := base_launch + forward_carry * carry_factor

	bottom_node.velocity = Vector3(
		forward_x * launch_speed,
		0.0 if _is_grounded else roll_upward_hop,
		forward_z * launch_speed
	)
	bottom_node.is_grounded = _is_grounded
	bottom_node.is_rolling = true
	bottom_node.is_recalling = false
	bottom_node.recall_time = 0.0
	bottom_node.eject_cooldown = 0.95 if is_sprint_launch else 0.65
	bottom_node.pivot.rotation = Vector3(0.0, _facing_angle, 0.0)
	bottom_node.visual_root.rotation = Vector3.ZERO

	var shake_power := 0.85 if is_sprint_launch else 0.55
	trigger_camera_shake(Vector3(-forward_x * shake_power, 0.24 if is_sprint_launch else 0.15, -forward_z * shake_power))

	_apply_squash(
		bottom_node,
		-0.36 if is_sprint_launch else -0.26,
		0.38 if is_sprint_launch else 0.28
	)

	if is_sprint_launch:
		var clamped := minf(cur_horiz_speed * 0.72, sprint_roll_speed)
		if cur_horiz_speed > 0.001:
			var ratio := clamped / cur_horiz_speed
			_leader_vel.x *= ratio
			_leader_vel.z *= ratio
	else:
		_is_grounded = false
		_coyote_timer = coyote_time_max
		_leader_vel = Vector3(
			-forward_x * 2.0,
			maxf(_leader_vel.y, 3.2),
			-forward_z * 2.0
		)

	for idx in range(_active_nodes.size()):
		var b := _active_nodes[idx]
		if not is_sprint_launch:
			b.velocity = Vector3.ZERO
		_apply_squash(
			b,
			(0.30 if is_sprint_launch else 0.22) - idx * 0.04,
			(-0.26 if is_sprint_launch else -0.20) + idx * 0.03
		)

	new_driver.pivot.rotation = Vector3(0.0, _facing_angle, 0.0)

	_ejected_nodes.append(bottom_node)
	_sync_collider_states()
	blob_ejected.emit(bottom_node.id, bottom_node.blob_name, true)
	return bottom_node

func _get_recall_target_position() -> Vector3:
	if _active_nodes.is_empty():
		return global_position

	var bottom := _active_nodes[0]
	if _is_sprint_rolling:
		var back_x := -sin(_facing_angle)
		var back_z := -cos(_facing_angle)
		var spacing := bottom.radius * 1.35 * float(_active_nodes.size())
		return Vector3(
			bottom.body.global_position.x + back_x * spacing,
			bottom.body.global_position.y + bottom.radius * 0.35,
			bottom.body.global_position.z + back_z * spacing
		)

	var stack_height := 0.0
	for i in range(1, _active_nodes.size()):
		stack_height += _active_nodes[i].radius * 1.85

	return Vector3(
		bottom.body.global_position.x,
		bottom.body.global_position.y + stack_height + bottom.radius * 1.25,
		bottom.body.global_position.z
	)

func recall_all() -> void:
	if _stack_swoop_target != null:
		_cancel_stack_swoop()

	var recallable: Array[StackBlob] = []
	for b in _ejected_nodes:
		if not _locked_ejected_nodes.has(b) and not _dead_nodes.has(b):
			recallable.append(b)

	if recallable.is_empty():
		return

	var target_center := _get_recall_target_position()

	for idx in range(recallable.size()):
		var b := recallable[idx]
		if _highlighted_ejected_node == b:
			_set_highlighted_target(null)

		var to_target := target_center - b.body.global_position
		var dist := to_target.length()
		if dist > 0.001:
			to_target /= dist

		if not b.is_recalling:
			b.recall_time = 0.0
			var side_sign := 1.0 if (idx % 2 == 0) else -1.0
			var perp_x := -to_target.z * side_sign
			var perp_z := to_target.x * side_sign
			b.recall_swoop_dir = Vector3(perp_x * 0.75, 0.65, perp_z * 0.75).normalized()

			var stack_speed := _leader_vel.length()
			var launch_speed := clampf(dist * 1.2 + stack_speed * 0.6, 16.0, 26.0)
			var upward_boost := (recall_initial_pop + to_target.y * 10.0) if to_target.y > 0.15 else (recall_initial_pop + float(idx) * 1.8)

			b.velocity = Vector3(
				to_target.x * launch_speed + perp_x * 6.5,
				maxf(b.velocity.y * 0.35, upward_boost),
				to_target.z * launch_speed + perp_z * 6.5
			)
			_apply_squash(b, -0.22, 0.26)

		b.is_recalling = true
		b.is_rolling = false
		b.is_grounded = false
		b.eject_cooldown = 0.0

	_sync_collider_states()

func _reabsorb_blob(ejected_index: int) -> void:
	var blob: StackBlob = _ejected_nodes[ejected_index]
	_ejected_nodes.remove_at(ejected_index)

	if _highlighted_ejected_node == blob:
		_set_highlighted_target(null)
	if _stack_swoop_target == blob:
		_stack_swoop_target = null

	var current_top: StackBlob = _active_nodes[_active_nodes.size() - 1]
	var incoming_vel := blob.velocity
	var was_recalling := blob.is_recalling

	blob.is_rolling = false
	blob.is_recalling = false
	blob.recall_time = 0.0
	blob.visual_root.scale = Vector3.ONE
	blob.pivot.rotation = Vector3(0.0, _facing_angle, 0.0)
	blob.visual_root.rotation = Vector3.ZERO

	var impact_horiz := Vector2(incoming_vel.x, incoming_vel.z)
	if impact_horiz.length_squared() < 0.25:
		impact_horiz = Vector2(-sin(_facing_angle), -cos(_facing_angle))
	else:
		impact_horiz = impact_horiz.normalized()

	var jiggle_mag := 14.5 if was_recalling else 8.5

	# Check if the stack will be too tall for the current ceiling once this blob rejoins
	_active_nodes.append(blob)
	var must_crouch := not _can_stand_up()
	if must_crouch and not _is_sprint_rolling:
		_is_sprint_rolling = true
		_roll_blend = 1.0
		_roll_entry_timer = 0.0
		_roll_exit_timer = 0.0

	if _is_sprint_rolling:
		var back_x := -sin(_facing_angle)
		var back_z := -cos(_facing_angle)
		var spacing := (current_top.radius + blob.radius) * roll_spacing_factor
		var target_x := current_top.body.global_position.x + back_x * spacing
		var target_z := current_top.body.global_position.z + back_z * spacing
		var top_feet_y := current_top.body.global_position.y - current_top.radius * 0.92
		var target_feet_y := _sample_follower_feet_y(
			target_x,
			target_z,
			top_feet_y,
			top_feet_y,
			_active_nodes.size() - 1,
			_get_all_blob_rids()
		)
		blob.body.global_position = Vector3(
			target_x,
			target_feet_y + blob.radius * 0.92,
			target_z
		)
		blob.velocity = Vector3(
			impact_horiz.x * jiggle_mag * 0.65,
			0.0,
			impact_horiz.y * jiggle_mag * 0.65
		)
	else:
		blob.body.global_position = Vector3(
			current_top.body.global_position.x,
			current_top.body.global_position.y + current_top.radius + blob.radius * 0.92,
			current_top.body.global_position.z
		)
		blob.velocity = Vector3(
			impact_horiz.x * jiggle_mag,
			0.0,
			impact_horiz.y * jiggle_mag
		)

	var total_count := float(_active_nodes.size() + 1)
	for idx in range(_active_nodes.size()):
		var existing := _active_nodes[idx]
		var tier_ratio := float(idx + 1) / total_count
		var alt_sign := 1.0 if (idx % 2 == 0) else -1.0
		var squash_amt := (0.32 if was_recalling else 0.20) * (0.65 + 0.35 * tier_ratio)

		_apply_squash(existing, squash_amt, -squash_amt * 0.9)
		existing.spring_vel.y = (20.0 if was_recalling else 12.0) * (0.6 + 0.4 * tier_ratio)
		existing.spring_vel.x += impact_horiz.x * jiggle_mag * 0.9 * alt_sign
		existing.spring_vel.z += impact_horiz.y * jiggle_mag * 0.9 * alt_sign

		if idx > 0:
			existing.velocity.x += impact_horiz.x * jiggle_mag * 0.65 * tier_ratio
			existing.velocity.z += impact_horiz.y * jiggle_mag * 0.65 * tier_ratio

	_apply_squash(blob, 0.38 if was_recalling else 0.24, -0.34 if was_recalling else -0.22)
	blob.spring_vel.y = 24.0 if was_recalling else 14.0
	blob.spring_vel.x = -impact_horiz.x * jiggle_mag * 0.8
	blob.spring_vel.z = -impact_horiz.y * jiggle_mag * 0.8

	if was_recalling:
		_leader_vel.x += impact_horiz.x * 1.4
		_leader_vel.z += impact_horiz.y * 1.4

	_sync_collider_states()
	blob_reabsorbed.emit(blob.id, blob.blob_name, was_recalling)

# --- Ejected Blob Physics, Homing Recall & Void Death ---

func _update_ejected_characters(delta: float) -> void:
	for i in range(_ejected_nodes.size() - 1, -1, -1):
		var b := _ejected_nodes[i]
		if _dead_nodes.has(b) or _locked_ejected_nodes.has(b):
			continue

		if b.body.global_position.y < void_death_y:
			_dead_nodes[b] = true
			b.body.visible = false
			b.outline_mesh.visible = false
			b.col_shape.disabled = true
			b.is_recalling = false
			b.recall_time = 0.0
			b.is_rolling = false
			b.velocity = Vector3.ZERO
			if _highlighted_ejected_node == b:
				_set_highlighted_target(null)
			if _stack_swoop_target == b:
				_cancel_stack_swoop()
			blob_void_died.emit(b.id, b.blob_name)
			continue

		if b.is_recalling:
			b.recall_time += delta
			var base_target := _get_recall_target_position()
			var raw_disp := base_target - b.body.global_position
			var dist := raw_disp.length()

			if dist <= b.radius + 1.15:
				_reabsorb_blob(i)
				continue

			var lead_seconds := clampf(dist / 38.0, 0.04, 0.22)
			var predicted_target := base_target + _leader_vel * lead_seconds

			var swoop_fade := exp(-b.recall_time * 5.2) * clampf(dist / 5.0, 0.0, 1.0)
			var curved_target := predicted_target + b.recall_swoop_dir * (swoop_fade * minf(4.2, dist * 0.38))
			var disp := curved_target - b.body.global_position

			var urgency := 1.0 + minf(2.2, b.recall_time * 2.4)
			var stiffness := recall_spring_stiffness * urgency
			var damping := recall_spring_damping * (1.0 + minf(0.6, b.recall_time * 0.7))

			var accel_vec := disp * stiffness - b.velocity * damping
			b.velocity += accel_vec * delta

			var stack_speed := _leader_vel.length()
			var min_closing := minf(
				recall_max_speed,
				maxf(recall_base_speed, stack_speed + recall_closing_margin) + b.recall_time * 18.0
			)

			var to_real_target := raw_disp.normalized()
			var closing_vel := b.velocity.dot(to_real_target)
			if closing_vel < min_closing:
				var boost := minf(min_closing - closing_vel, 95.0 * delta)
				b.velocity += to_real_target * boost

			var spd := b.velocity.length()
			if spd > recall_max_speed:
				b.velocity = b.velocity.normalized() * recall_max_speed

			b.body.global_position += b.velocity * delta

			var horiz_spd := Vector2(b.velocity.x, b.velocity.z).length()
			if horiz_spd > 0.3:
				var target_yaw := atan2(b.velocity.x, b.velocity.z)
				var yaw_diff := fposmod(target_yaw - b.pivot.rotation.y + PI, TAU) - PI
				var bank_angle := clampf(-yaw_diff * 0.85, -0.55, 0.55)
				b.pivot.rotation.y = _lerp_angle(b.pivot.rotation.y, target_yaw, 18.0 * delta)
				b.visual_root.rotation.z = _lerp_angle(b.visual_root.rotation.z, bank_angle, 14.0 * delta)
			else:
				b.visual_root.rotation.z = _lerp_angle(b.visual_root.rotation.z, 0.0, 14.0 * delta)

			var target_pitch := clampf(-b.velocity.y * 0.032, -0.65, 0.65)
			b.visual_root.rotation.x = _lerp_angle(b.visual_root.rotation.x, target_pitch, 18.0 * delta)

			var speed_ratio := clampf(spd / 36.0, 0.0, 1.0)
			var prox_squash := ((1.0 - dist / 2.2) * 0.12) if dist < 2.2 else 0.0
			var stretch := speed_ratio * 0.24 - prox_squash
			b.squash = b.squash.lerp(Vector3.ZERO, minf(1.0, 16.0 * delta))
			b.visual_root.scale = Vector3(
				1.0 - stretch * 0.45 + b.squash.x,
				1.0 - stretch * 0.45 + b.squash.y,
				1.0 + stretch + b.squash.z
			)
			continue

		b.eject_cooldown = maxf(0.0, b.eject_cooldown - delta)

		var eff_grav := (gravity * 1.5) if b.velocity.y < 0.0 else gravity
		b.velocity.y = maxf(b.velocity.y - eff_grav * delta, -terminal_velocity)

		b.is_grounded = false
		var total_move := b.velocity * delta
		var max_step := maxf(0.15, b.radius * 0.45)
		var substeps := clampi(int(ceilf(total_move.length() / max_step)), 1, 6)
		var sub_dt := delta / float(substeps)
		var did_bounce := false
		var peak_bounce_speed := 0.0

		for _sub in range(substeps):
			var remaining := b.velocity * sub_dt
			for _slide in range(3):
				var collision := b.body.move_and_collide(remaining, false, 0.004)
				if collision == null:
					break

				var normal := collision.get_normal()
				var remainder := collision.get_remainder()

				if normal.y > 0.65:
					if b.velocity.y < -2.5:
						var fall_spd := absf(b.velocity.y)
						b.velocity.y = -b.velocity.y * bounce_restitution
						_apply_squash(b, 0.28, -0.26)
						did_bounce = true
						peak_bounce_speed = maxf(peak_bounce_speed, fall_spd)
					else:
						b.velocity.y = 0.0
						b.is_grounded = true
				elif normal.y < -0.65:
					if b.velocity.y > 2.5:
						_apply_squash(b, 0.24, -0.22)
						did_bounce = true
						peak_bounce_speed = maxf(peak_bounce_speed, b.velocity.y)
					b.velocity.y = 0.0
				else:
					var wall_n := Vector3(normal.x, 0.0, normal.z).normalized()
					var into_speed := -b.velocity.dot(wall_n)
					if into_speed > 0.0:
						b.velocity += wall_n * into_speed * 1.5
						if into_speed > 2.2:
							_apply_squash(b, -0.24, 0.22)
							did_bounce = true
							peak_bounce_speed = maxf(peak_bounce_speed, into_speed)

				remaining = remainder.slide(normal)

		if did_bounce:
			bounced.emit(peak_bounce_speed)

		b.squash = b.squash.lerp(Vector3.ZERO, minf(1.0, 14.0 * delta))
		var horiz_speed := Vector2(b.velocity.x, b.velocity.z).length()

		if b.is_rolling and horiz_speed > 1.8:
			var roll_heading := atan2(b.velocity.x, b.velocity.z)
			b.pivot.rotation.y = roll_heading
			b.visual_root.rotation.z = 0.0
			b.visual_root.rotation.x += (horiz_speed / maxf(0.35, b.radius)) * delta

			if b.is_grounded or _stack_swoop_target == b:
				var damp_rate := 14.0 if _stack_swoop_target == b else 2.2
				var roll_damp := exp(-damp_rate * delta)
				b.velocity.x *= roll_damp
				b.velocity.z *= roll_damp

			b.visual_root.scale = Vector3(1.0 + b.squash.x, 1.0 + b.squash.y, 1.0 + b.squash.z)
		else:
			b.is_rolling = false
			if not b.is_grounded:
				b.visual_root.rotation.x += 10.0 * delta
				b.visual_root.scale = Vector3(1.0 + b.squash.x, 1.0 + b.squash.y, 1.0 + b.squash.z)
			else:
				b.visual_root.rotation.x = _lerp_angle(b.visual_root.rotation.x, 0.0, 12.0 * delta)
				b.visual_root.rotation.z = _lerp_angle(b.visual_root.rotation.z, 0.0, 12.0 * delta)

				var ground_damp := exp(-8.0 * delta)
				b.velocity.x *= ground_damp
				b.velocity.z *= ground_damp

				var breath := sin(_elapsed * 6.0 + float(b.id)) * 0.03
				b.visual_root.scale = Vector3(
					1.0 + breath + b.squash.x,
					1.0 - breath + b.squash.y,
					1.0 + breath + b.squash.z
				)

		# Don't accidentally reabsorb a ball that is still actively rolling fast away/ahead
		var still_fast_rolling := b.is_rolling and horiz_speed > 8.0
		var held_in_air_lock := (_highlighted_ejected_node == b) and not b.is_grounded and b.velocity.y > -6.0
		if b.eject_cooldown <= 0.0 and not still_fast_rolling and not held_in_air_lock and _stack_swoop_target == null:
			var stack_center := get_stack_center()
			if stack_center.distance_to(b.body.global_position) <= b.radius + 1.05:
				_reabsorb_blob(i)

	for i in range(_ejected_nodes.size()):
		for j in range(i + 1, _ejected_nodes.size()):
			var a := _ejected_nodes[i]
			var b := _ejected_nodes[j]
			if _dead_nodes.has(a) or _dead_nodes.has(b) or a.is_recalling or b.is_recalling:
				continue

			var min_dist := a.radius + b.radius
			var delta_vec := b.body.global_position - a.body.global_position
			var dist := delta_vec.length()

			if dist > 0.001 and dist < min_dist:
				var normal := delta_vec / dist
				var overlap := (min_dist - dist) * 0.5
				a.body.global_position -= normal * overlap
				b.body.global_position += normal * overlap

				var rel_vel := (b.velocity - a.velocity).dot(normal)
				if rel_vel < 0.0:
					var impulse := -(1.0 + bounce_restitution) * rel_vel * 0.5
					a.velocity -= normal * impulse
					b.velocity += normal * impulse
					_apply_squash(a, -0.2, 0.2)
					_apply_squash(b, -0.2, 0.2)
					bounced.emit(absf(rel_vel))

# --- Active Stack Movement & Sprint-Roll ---

func _update_active_stack(delta: float, axes: Vector2, camera_yaw: float) -> void:
	var bottom := _active_nodes[0]
	var input_dir := Vector3.ZERO

	if not is_zero_approx(axes.x) or not is_zero_approx(axes.y):
		var sin_y := sin(camera_yaw)
		var cos_y := cos(camera_yaw)
		var forward_x := -sin_y
		var forward_z := -cos_y
		var right_x := cos_y
		var right_z := -sin_y

		input_dir = Vector3(
			right_x * axes.x + forward_x * (-axes.y),
			0.0,
			right_z * axes.x + forward_z * (-axes.y)
		)
		if input_dir.length_squared() > 0.0001:
			input_dir = input_dir.normalized()

	var sprint_held := _read_sprint_held()
	var has_move_input := input_dir.length_squared() > 0.0
	var forced_crouch := (not sprint_held) and _active_nodes.size() > 1 and not _can_stand_up()
	var wants_sprint_roll := sprint_held or forced_crouch

	if wants_sprint_roll and not _is_sprint_rolling:
		_is_sprint_rolling = true
		_roll_entry_timer = 0.08
		_roll_exit_timer = 0.0
		var cur_speed := Vector2(_leader_vel.x, _leader_vel.z).length()
		if has_move_input:
			_facing_angle = atan2(input_dir.x, input_dir.z)
		elif cur_speed > 1.0:
			_facing_angle = atan2(_leader_vel.x, _leader_vel.z)
		bottom.pivot.rotation.y = _facing_angle

		var back_x := -sin(_facing_angle)
		var back_z := -cos(_facing_angle)
		for i in range(1, _active_nodes.size()):
			_active_nodes[i].velocity = Vector3(back_x * 4.0 * float(i), 0.0, back_z * 4.0 * float(i))

		for idx in range(_active_nodes.size()):
			_apply_squash(_active_nodes[idx], -0.2 + idx * 0.02, 0.22 - idx * 0.02)

	elif not wants_sprint_roll and _is_sprint_rolling:
		_is_sprint_rolling = false
		_roll_exit_timer = 0.12
		_roll_entry_timer = 0.0

		var blue_idx := -1
		for idx in range(_active_nodes.size()):
			if _active_nodes[idx].id == 0:
				blue_idx = idx
				break
		if blue_idx > 0:
			var anchor_x := _active_nodes[0].body.global_position.x
			var anchor_z := _active_nodes[0].body.global_position.z
			var anchor_feet_y := _active_nodes[0].body.global_position.y - _active_nodes[0].radius * 0.92
			var blue_node: StackBlob = _active_nodes[blue_idx]
			_active_nodes.remove_at(blue_idx)
			blue_node.body.global_position = Vector3(anchor_x, anchor_feet_y + blue_node.radius * 0.92, anchor_z)
			_active_nodes.push_front(blue_node)
			_sync_collider_states()

		var exit_speed := Vector2(_leader_vel.x, _leader_vel.z).length()
		if exit_speed > move_speed and _launch_momentum_timer <= 0.0:
			var carry_ratio := (move_speed * 1.1) / exit_speed
			_leader_vel.x *= carry_ratio
			_leader_vel.z *= carry_ratio

		for idx in range(_active_nodes.size()):
			_apply_squash(_active_nodes[idx], 0.24 - idx * 0.03, -0.22 + idx * 0.03)

	var target_blend := 0.0
	var blend_rate := 26.0
	if _roll_entry_timer > 0.0:
		target_blend = 1.0
		_roll_entry_timer = maxf(0.0, _roll_entry_timer - delta)
		blend_rate = 48.0
	elif _roll_exit_timer > 0.0:
		target_blend = 0.0
		_roll_exit_timer = maxf(0.0, _roll_exit_timer - delta)
		blend_rate = 34.0
	else:
		target_blend = 1.0 if _is_sprint_rolling else 0.0

	_roll_blend = lerpf(_roll_blend, target_blend, 1.0 - exp(-blend_rate * delta))
	_update_stack_hull_collider()

	if _is_grounded and _leader_vel.y <= 0.0:
		_launch_momentum_timer = 0.0
	else:
		_launch_momentum_timer = maxf(0.0, _launch_momentum_timer - delta)

	var rolling_with_input := _is_sprint_rolling and has_move_input
	var active_max_speed := sprint_roll_speed if rolling_with_input else move_speed
	var effective_max_speed := maxf(active_max_speed, Vector2(_leader_vel.x, _leader_vel.z).length()) if _launch_momentum_timer > 0.0 else active_max_speed
	var accel := ground_accel if _is_grounded else air_accel
	var friction := ground_friction if _is_grounded else air_friction

	if has_move_input:
		_facing_angle = atan2(input_dir.x, input_dir.z)
		var cur_speed := Vector2(_leader_vel.x, _leader_vel.z).length()
		if _launch_momentum_timer <= 0.0:
			if _is_grounded:
				var target_vx := input_dir.x * effective_max_speed
				var target_vz := input_dir.z * effective_max_speed
				var turn_rate := 22.0 if _is_sprint_rolling else 24.0
				var turn_t := 1.0 - exp(-turn_rate * delta)
				_leader_vel.x = lerpf(_leader_vel.x, target_vx, turn_t)
				_leader_vel.z = lerpf(_leader_vel.z, target_vz, turn_t)
			else:
				var air_target := maxf(cur_speed, effective_max_speed * 0.96)
				var target_vx := input_dir.x * air_target
				var target_vz := input_dir.z * air_target
				var air_turn_t := 1.0 - exp(-15.0 * delta)
				_leader_vel.x = lerpf(_leader_vel.x, target_vx, air_turn_t)
				_leader_vel.z = lerpf(_leader_vel.z, target_vz, air_turn_t)
				_leader_vel.x += input_dir.x * accel * delta
				_leader_vel.z += input_dir.z * accel * delta

		var horiz_speed := Vector2(_leader_vel.x, _leader_vel.z).length()
		if horiz_speed > effective_max_speed:
			var clamp_ratio := effective_max_speed / horiz_speed
			_leader_vel.x *= clamp_ratio
			_leader_vel.z *= clamp_ratio
	elif _launch_momentum_timer <= 0.0:
		var damp := exp(-friction * delta)
		_leader_vel.x *= damp
		_leader_vel.z *= damp
		if _is_grounded and Vector2(_leader_vel.x, _leader_vel.z).length() < 0.25:
			_leader_vel.x = 0.0
			_leader_vel.z = 0.0

	var coyote_limit := coyote_time_max * 1.25 if _is_sprint_rolling else coyote_time_max
	if _is_grounded:
		_coyote_timer = coyote_limit
		_has_air_combo_jump = false
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	var can_coyote_jump := _coyote_timer > 0.0 and not _is_grounded
	var can_combo_air_jump := _has_air_combo_jump and not _is_grounded
	if (_is_grounded or can_coyote_jump or can_combo_air_jump) and _jump_buffer_timer > 0.0:
		var is_combo_air := can_combo_air_jump and not can_coyote_jump
		if is_combo_air:
			_has_air_combo_jump = false
		_leader_vel.y = jump_force
		_is_grounded = false
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		jumped.emit(_active_nodes.size(), is_combo_air)

		for idx in range(_active_nodes.size()):
			var b := _active_nodes[idx]
			_apply_squash(b, -0.3 + idx * 0.02, 0.38 - idx * 0.03)
			b.spring_vel.y = 18.0 + idx * 2.0

	var is_near_apex := absf(_leader_vel.y) < 3.5
	var eff_gravity := gravity
	if is_near_apex:
		eff_gravity = gravity * 0.5
	elif _leader_vel.y < 0.0:
		eff_gravity = gravity * 1.5

	_leader_vel.y = maxf(_leader_vel.y - eff_gravity * delta, -terminal_velocity)

	if _leader_vel.y > 0.0 and not _jump_held and _launch_momentum_timer <= 0.0:
		_leader_vel.y *= 0.4

	var was_grounded := _is_grounded
	var impact_speed := absf(_leader_vel.y)

	bottom.body.velocity = _leader_vel
	bottom.body.move_and_slide()
	_is_grounded = bottom.body.is_on_floor()

	if _is_grounded and _leader_vel.y < 0.0:
		_leader_vel.y = 0.0
	elif not _is_grounded:
		_leader_vel.y = bottom.body.velocity.y

	if not was_grounded and _is_grounded and impact_speed > 3.0:
		landed.emit(impact_speed, _active_nodes.size())
		var intensity := clampf(impact_speed / 22.0, 0.35, 1.0)
		for idx in range(_active_nodes.size()):
			var b := _active_nodes[idx]
			var f := intensity * (1.0 - idx * 0.14)
			_apply_squash(b, 0.38 * f, -0.34 * f)
			b.spring_vel.y = 24.0 * intensity + idx * 3.0
			b.spring_vel.x = randf_range(-4.0, 4.0) * intensity
			b.spring_vel.z = randf_range(-4.0, 4.0) * intensity

	var roll_speed := Vector2(_leader_vel.x, _leader_vel.z).length()
	if _roll_blend > 0.05:
		_roll_spin_angle += (roll_speed / maxf(0.4, bottom.radius)) * delta * _roll_blend
	else:
		_roll_spin_angle = 0.0

	bottom.pivot.rotation.y = _lerp_angle(bottom.pivot.rotation.y, _facing_angle, 22.0 * delta)
	bottom.pivot.rotation.x = _lerp_angle(bottom.pivot.rotation.x, 0.0, 20.0 * delta)
	bottom.visual_root.rotation.x = _roll_spin_angle * _roll_blend

	_update_squash_springs(delta)

	var speed_stretch := _roll_blend * clampf(roll_speed / sprint_roll_speed, 0.0, 1.0) * 0.06
	var roll_roundness := 1.0 - _roll_blend * 0.06
	var breath := sin(_elapsed * 5.0) * 0.03 * (1.0 - _roll_blend)
	bottom.squash = bottom.squash.lerp(Vector3.ZERO, minf(1.0, 16.0 * delta))
	bottom.visual_root.scale = Vector3(
		(1.0 + breath + bottom.squash.x - speed_stretch * 0.5) * roll_roundness,
		1.0 - breath + bottom.squash.y - speed_stretch * 0.5,
		(1.0 + breath + bottom.squash.z + speed_stretch) * roll_roundness
	)

	if _is_sprint_rolling:
		_update_sprint_roll_followers(delta, speed_stretch, roll_roundness)
	else:
		_update_vertical_stack_followers(delta)

func _update_vertical_stack_followers(delta: float) -> void:
	var line_heading := _active_nodes[0].pivot.rotation.y
	for i in range(1, _active_nodes.size()):
		var below := _active_nodes[i - 1]
		var curr := _active_nodes[i]

		var node_breath := sin(_elapsed * 5.0 - float(i) * 0.8) * 0.035
		curr.squash = curr.squash.lerp(Vector3.ZERO, minf(1.0, 16.0 * delta))
		curr.visual_root.scale = Vector3(
			1.0 + node_breath + curr.squash.x,
			1.0 - node_breath + curr.squash.y,
			1.0 + node_breath + curr.squash.z
		)

		var spacing := below.radius + curr.radius * 0.92
		var v_stretch := clampf(_leader_vel.y * 0.012, -0.18, 0.22)
		var target_y := below.body.global_position.y + spacing + v_stretch

		var disp_x := below.body.global_position.x - curr.body.global_position.x
		var disp_z := below.body.global_position.z - curr.body.global_position.z

		var fx := disp_x * follower_spring_stiffness - curr.velocity.x * follower_spring_damping
		var fz := disp_z * follower_spring_stiffness - curr.velocity.z * follower_spring_damping

		curr.velocity.x += fx * delta
		curr.velocity.z += fz * delta

		curr.body.global_position.x += curr.velocity.x * delta
		curr.body.global_position.z += curr.velocity.z * delta
		curr.body.global_position.y = lerpf(
			curr.body.global_position.y,
			target_y,
			1.0 - exp(-32.0 * delta)
		)

		curr.pivot.rotation.y = _lerp_angle(curr.pivot.rotation.y, line_heading, 20.0 * delta)
		curr.pivot.rotation.x = _lerp_angle(curr.pivot.rotation.x, 0.0, 20.0 * delta)
		curr.visual_root.rotation.x = curr.velocity.z * 0.035
		curr.visual_root.rotation.z = -curr.velocity.x * 0.035

func _sample_follower_feet_y(
	pos_x: float,
	pos_z: float,
	curr_feet_y: float,
	ahead_feet_y: float,
	chain_index: int,
	exclude_rids: Array[RID]
) -> float:
	if not _is_grounded:
		return ahead_feet_y

	var space_state := get_world_3d().direct_space_state
	var probe_top := maxf(curr_feet_y, ahead_feet_y) + 1.45
	var max_drop := 1.65
	var probe_bottom := ahead_feet_y - max_drop

	var query := PhysicsRayQueryParameters3D.create(
		Vector3(pos_x, probe_top, pos_z),
		Vector3(pos_x, probe_bottom, pos_z)
	)
	query.exclude = exclude_rids
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_y := (hit["position"] as Vector3).y
		return clampf(hit_y, ahead_feet_y - max_drop, ahead_feet_y + 1.25)

	# Over a sheer ledge/drop: drape slightly downward instead of sticking straight out
	return ahead_feet_y - 0.28 * float(chain_index)

func _update_sprint_roll_followers(delta: float, speed_stretch: float, roll_roundness: float) -> void:
	var back_x := -sin(_facing_angle)
	var back_z := -cos(_facing_angle)
	var exclude_rids := _get_all_blob_rids()

	for i in range(1, _active_nodes.size()):
		var ahead := _active_nodes[i - 1]
		var curr := _active_nodes[i]

		var spacing := (ahead.radius + curr.radius) * roll_spacing_factor * maxf(0.3, _roll_blend)
		var target_x := ahead.body.global_position.x + back_x * spacing
		var target_z := ahead.body.global_position.z + back_z * spacing

		var disp_x := target_x - curr.body.global_position.x
		var disp_z := target_z - curr.body.global_position.z

		var fx := disp_x * roll_spring_stiffness - curr.velocity.x * roll_spring_damping
		var fz := disp_z * roll_spring_stiffness - curr.velocity.z * roll_spring_damping

		curr.velocity.x += fx * delta
		curr.velocity.z += fz * delta

		curr.body.global_position.x += curr.velocity.x * delta
		curr.body.global_position.z += curr.velocity.z * delta

		var offset_x := curr.body.global_position.x - ahead.body.global_position.x
		var offset_z := curr.body.global_position.z - ahead.body.global_position.z
		var dist := Vector2(offset_x, offset_z).length()
		var max_dist := spacing * 1.18
		if dist > max_dist and dist > 0.0001:
			var pull := max_dist / dist
			curr.body.global_position.x = ahead.body.global_position.x + offset_x * pull
			curr.body.global_position.z = ahead.body.global_position.z + offset_z * pull

		var ahead_feet_y := ahead.body.global_position.y - ahead.radius * 0.92
		var curr_feet_y := curr.body.global_position.y - curr.radius * 0.92
		var surface_feet_y := _sample_follower_feet_y(
			curr.body.global_position.x,
			curr.body.global_position.z,
			curr_feet_y,
			ahead_feet_y,
			i,
			exclude_rids
		)
		var target_y := surface_feet_y + curr.radius * 0.92
		var y_follow_rate := 36.0 if _is_grounded else 26.0
		curr.body.global_position.y = lerpf(
			curr.body.global_position.y,
			target_y,
			1.0 - exp(-y_follow_rate * delta)
		)

		var look_x := ahead.body.global_position.x - curr.body.global_position.x
		var look_z := ahead.body.global_position.z - curr.body.global_position.z
		var horiz_sep := Vector2(look_x, look_z).length()
		var look_heading := atan2(look_x, look_z) if horiz_sep > 0.05 else _facing_angle

		# Tilt follower pivot along the ramp/stair contour while preserving spin on visual_root
		var updated_feet_y := curr.body.global_position.y - curr.radius * 0.92
		var slope_pitch := clampf(-atan2(ahead_feet_y - updated_feet_y, maxf(0.25, horiz_sep)), -0.65, 0.65)

		curr.pivot.rotation.y = _lerp_angle(curr.pivot.rotation.y, look_heading, 22.0 * delta)
		curr.pivot.rotation.x = _lerp_angle(curr.pivot.rotation.x, slope_pitch * _roll_blend, 18.0 * delta)
		curr.visual_root.rotation.x = _roll_spin_angle * (_active_nodes[0].radius / maxf(0.4, curr.radius)) * _roll_blend
		curr.visual_root.rotation.z = 0.0

		var node_breath := sin(_elapsed * 5.0 - float(i) * 0.8) * 0.025 * (1.0 - _roll_blend)
		curr.squash = curr.squash.lerp(Vector3.ZERO, minf(1.0, 16.0 * delta))
		curr.visual_root.scale = Vector3(
			(1.0 + node_breath + curr.squash.x - speed_stretch * 0.5) * roll_roundness,
			1.0 - node_breath + curr.squash.y - speed_stretch * 0.5,
			(1.0 + node_breath + curr.squash.z + speed_stretch) * roll_roundness
		)

func _apply_squash(blob: StackBlob, xz_delta: float, y_delta: float) -> void:
	blob.squash = Vector3(xz_delta, y_delta, xz_delta)

func _update_squash_springs(delta: float) -> void:
	for blob in _active_nodes:
		var fx := -squash_spring_stiffness * blob.spring_pos.x - squash_spring_damping * blob.spring_vel.x
		var fy := -squash_spring_stiffness * blob.spring_pos.y - squash_spring_damping * blob.spring_vel.y
		var fz := -squash_spring_stiffness * blob.spring_pos.z - squash_spring_damping * blob.spring_vel.z

		blob.spring_vel += Vector3(fx, fy, fz) * delta
		blob.spring_pos += blob.spring_vel * delta
		blob.squash += blob.spring_pos * 0.015

func _lerp_angle(a: float, b: float, t: float) -> float:
	var diff := fposmod(b - a + PI, TAU) - PI
	return a + diff * minf(1.0, t)

func get_stack_statuses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in _all_nodes:
		var stacked_idx := _active_nodes.find(b)
		var is_dead := _dead_nodes.has(b)
		out.append({
			"id": b.id,
			"name": b.blob_name,
			"color": b.color,
			"is_stacked": stacked_idx != -1 and not is_dead,
			"stack_pos": stacked_idx,
			"is_dead": is_dead,
		})
	return out

func is_high_speed_state() -> bool:
	return _is_sprint_rolling or _stack_swoop_target != null or Vector2(_leader_vel.x, _leader_vel.z).length() > move_speed * 1.25
