class_name ButtonGate
extends Node3D

@export_group("Button Pad")
@export var button_offset: Vector3 = Vector3(-6.5, 0.0, 2.5)
@export var button_size: float = 2.4
@export var button_press_depth: float = 0.14

@export_group("Archway & Gate")
@export var gate_width: float = 6.4
@export var gate_height: float = 4.8
@export var gate_depth: float = 1.1
@export var lift_height: float = 4.2
@export var open_speed: float = 1.75
@export var close_speed: float = 1.45

var _pad_body: Node3D
var _pad_mat: StandardMaterial3D
var _bars_body: StaticBody3D
var _trigger_area: Area3D

var _pad_rest_y: float = 0.0
var _pad_pressed_y: float = 0.0
var _closed_bars_y: float = 0.0
var _open_progress: float = 0.0
var _is_pressed: bool = false
var _was_pressed: bool = false
var _move_sound_timer: float = 0.0

func _ready() -> void:
	_build_button()
	_build_arch_and_gate()
	reset_gate()

func _get_sound_engine() -> SoundEngine:
	var parent_node: Node = get_parent()
	if parent_node != null:
		var direct: SoundEngine = parent_node.get_node_or_null("SoundEngine") as SoundEngine
		if direct != null:
			return direct
	return get_tree().root.find_child("SoundEngine", true, false) as SoundEngine

func _build_button() -> void:
	var base_h: float = 0.14
	var pad_h: float = 0.22
	var pad_w: float = button_size * 0.78

	var base_mesh: MeshInstance3D = MeshInstance3D.new()
	var base_box: BoxMesh = BoxMesh.new()
	base_box.size = Vector3(button_size, base_h, button_size)
	base_mesh.mesh = base_box
	var base_mat: StandardMaterial3D = StandardMaterial3D.new()
	base_mat.albedo_color = Color("f8fafc")
	base_mat.roughness = 0.5
	base_mesh.material_override = base_mat
	base_mesh.position = button_offset + Vector3(0.0, base_h * 0.5, 0.0)
	add_child(base_mesh)

	_pad_body = Node3D.new()
	_pad_rest_y = button_offset.y + base_h + pad_h * 0.5
	_pad_pressed_y = _pad_rest_y - button_press_depth
	_pad_body.position = Vector3(button_offset.x, _pad_rest_y, button_offset.z)
	add_child(_pad_body)

	var pad_mesh: MeshInstance3D = MeshInstance3D.new()
	var pad_box: BoxMesh = BoxMesh.new()
	pad_box.size = Vector3(pad_w, pad_h, pad_w)
	pad_mesh.mesh = pad_box
	_pad_mat = StandardMaterial3D.new()
	_pad_mat.albedo_color = Color("ef4444")
	_pad_mat.emission_enabled = true
	_pad_mat.emission = Color("991b1b")
	_pad_mat.emission_energy_multiplier = 0.4
	_pad_mat.roughness = 0.35
	pad_mesh.material_override = _pad_mat
	_pad_body.add_child(pad_mesh)

	_trigger_area = Area3D.new()
	_trigger_area.position = button_offset + Vector3(0.0, base_h + 0.5, 0.0)
	_trigger_area.monitoring = true
	_trigger_area.monitorable = false
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(pad_w * 1.1, 1.0, pad_w * 1.1)
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	_trigger_area.add_child(col)
	add_child(_trigger_area)

func _build_arch_and_gate() -> void:
	var pillar_w: float = 0.9
	var lintel_h: float = 0.95
	var inner_w: float = maxf(1.2, gate_width - pillar_w * 2.0)
	var inner_h: float = maxf(1.2, gate_height - lintel_h)

	var arch_static: StaticBody3D = StaticBody3D.new()
	add_child(arch_static)

	var arch_mat: StandardMaterial3D = StandardMaterial3D.new()
	arch_mat.albedo_color = Color("854d27")
	arch_mat.roughness = 0.8

	var pillar_d: float = gate_depth * 1.15
	var sides: Array[float] = [-1.0, 1.0]
	for side: float in sides:
		var px: float = side * (inner_w * 0.5 + pillar_w * 0.5)
		var py: float = gate_height * 0.5
		var p_mesh: MeshInstance3D = MeshInstance3D.new()
		var p_box: BoxMesh = BoxMesh.new()
		p_box.size = Vector3(pillar_w, gate_height, pillar_d)
		p_mesh.mesh = p_box
		p_mesh.material_override = arch_mat
		p_mesh.position = Vector3(px, py, 0.0)
		arch_static.add_child(p_mesh)

		var p_col: CollisionShape3D = CollisionShape3D.new()
		var p_shape: BoxShape3D = BoxShape3D.new()
		p_shape.size = p_box.size
		p_col.shape = p_shape
		p_col.position = p_mesh.position
		arch_static.add_child(p_col)

	var lintel_w: float = gate_width + 0.3
	var lintel_d: float = gate_depth * 1.25
	var lintel_y: float = inner_h + lintel_h * 0.5
	var l_mesh: MeshInstance3D = MeshInstance3D.new()
	var l_box: BoxMesh = BoxMesh.new()
	l_box.size = Vector3(lintel_w, lintel_h, lintel_d)
	l_mesh.mesh = l_box
	l_mesh.material_override = arch_mat
	l_mesh.position = Vector3(0.0, lintel_y, 0.0)
	arch_static.add_child(l_mesh)

	var l_col: CollisionShape3D = CollisionShape3D.new()
	var l_shape: BoxShape3D = BoxShape3D.new()
	l_shape.size = l_box.size
	l_col.shape = l_shape
	l_col.position = l_mesh.position
	arch_static.add_child(l_col)

	_bars_body = StaticBody3D.new()
	_closed_bars_y = inner_h * 0.5
	_bars_body.position = Vector3(0.0, _closed_bars_y, 0.0)
	add_child(_bars_body)

	var bar_mat: StandardMaterial3D = StandardMaterial3D.new()
	bar_mat.albedo_color = Color("1e293b")
	bar_mat.roughness = 0.35
	bar_mat.metallic = 0.65

	var num_bars: int = maxi(4, int(round(inner_w / 0.85)))
	var v_cyl: CylinderMesh = CylinderMesh.new()
	v_cyl.top_radius = 0.11
	v_cyl.bottom_radius = 0.11
	v_cyl.height = inner_h
	for i: int in range(num_bars):
		var frac: float = (float(i) + 0.5) / float(num_bars) - 0.5
		var v_mesh: MeshInstance3D = MeshInstance3D.new()
		v_mesh.mesh = v_cyl
		v_mesh.material_override = bar_mat
		v_mesh.position = Vector3(frac * inner_w, 0.0, 0.0)
		_bars_body.add_child(v_mesh)

	var h_box: BoxMesh = BoxMesh.new()
	h_box.size = Vector3(inner_w, 0.18, 0.24)
	var y_fracs: Array[float] = [-0.28, 0.0, 0.28]
	for y_frac: float in y_fracs:
		var h_mesh: MeshInstance3D = MeshInstance3D.new()
		h_mesh.mesh = h_box
		h_mesh.material_override = bar_mat
		h_mesh.position = Vector3(0.0, y_frac * inner_h, 0.0)
		_bars_body.add_child(h_mesh)

	var gate_col: CollisionShape3D = CollisionShape3D.new()
	var gate_shape: BoxShape3D = BoxShape3D.new()
	gate_shape.size = Vector3(inner_w, inner_h, gate_depth * 0.7)
	gate_col.shape = gate_shape
	_bars_body.add_child(gate_col)

func reset_gate() -> void:
	_open_progress = 0.0
	_is_pressed = false
	_was_pressed = false
	_move_sound_timer = 0.0
	_pad_body.position.y = _pad_rest_y
	_bars_body.position.y = _closed_bars_y
	_bars_body.collision_layer = 1
	_bars_body.collision_mask = 1

func _physics_process(delta: float) -> void:
	_is_pressed = _trigger_area.get_overlapping_bodies().size() > 0 or _trigger_area.get_overlapping_areas().size() > 0
	var sfx: SoundEngine = _get_sound_engine()

	if _is_pressed and not _was_pressed:
		if sfx != null:
			sfx.play(&"button_down", 0.95)
	elif not _is_pressed and _was_pressed:
		if sfx != null:
			sfx.play(&"button_up", 0.9)
	_was_pressed = _is_pressed

	var target_pad_y: float = _pad_pressed_y if _is_pressed else _pad_rest_y
	_pad_body.position.y = lerpf(_pad_body.position.y, target_pad_y, 1.0 - exp(-28.0 * delta))
	_pad_mat.emission = Color("f97316") if _is_pressed else Color("991b1b")
	_pad_mat.emission_energy_multiplier = 1.2 if _is_pressed else 0.4

	var prev_p: float = _open_progress
	if _is_pressed:
		_open_progress = minf(1.0, _open_progress + open_speed * delta)
	else:
		_open_progress = maxf(0.0, _open_progress - close_speed * delta)

	if absf(_open_progress - prev_p) > 0.0001:
		_move_sound_timer -= delta
		if _move_sound_timer <= 0.0 and sfx != null:
			sfx.play(&"gate_move", 0.55)
			_move_sound_timer = 0.13
	else:
		_move_sound_timer = 0.0

	var eased: float = smoothstep(0.0, 1.0, _open_progress)
	_bars_body.position.y = _closed_bars_y + eased * lift_height
	var solid: bool = _open_progress < 0.85
	_bars_body.collision_layer = 1 if solid else 0
	_bars_body.collision_mask = 1 if solid else 0