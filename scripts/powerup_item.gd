@tool
class_name PowerupItem
extends Node3D

enum PowerupType {
	PYRAMID = 0,
	BOMB = 1,
}

signal collected(powerup_type: PowerupType, collector: Node3D)

@export_group("Powerup Settings")
@export var powerup_type: PowerupType = PowerupType.PYRAMID:
	set(value):
		powerup_type = value
		_rebuild()

@export var tint_color: Color = Color("facc15"):
	set(value):
		tint_color = value
		_rebuild()

@export var hover_height: float = 1.15:
	set(value):
		hover_height = maxf(0.2, value)
		_rebuild()

@export var respawn_seconds: float = 4.0

@export_group("Editor Guides")
@export var show_editor_guides: bool = true:
	set(value):
		show_editor_guides = value
		_rebuild()

var _visual_pivot: Node3D
var _area: Area3D
var _collected: bool = false
var _respawn_timer: float = 0.0
var _elapsed: float = 0.0

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_visual_pivot = Node3D.new()
	_visual_pivot.position.y = hover_height
	add_child(_visual_pivot)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()

	if powerup_type == PowerupType.BOMB:
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.56
		sphere.height = 1.12
		mesh_inst.mesh = sphere
		mat.albedo_color = Color("090d16")
		mat.roughness = 0.18
		mat.metallic = 0.45
		mat.emission_enabled = true
		mat.emission = Color("f97316")
		mat.emission_energy_multiplier = 0.35
	else:
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.62
		cone.height = 1.05
		cone.radial_segments = 4
		mesh_inst.mesh = cone
		mat.albedo_color = tint_color
		mat.roughness = 0.25
		mat.metallic = 0.15
		mat.emission_enabled = true
		mat.emission = tint_color
		mat.emission_energy_multiplier = 0.45

	mesh_inst.material_override = mat
	_visual_pivot.add_child(mesh_inst)

	_area = Area3D.new()
	_area.position.y = hover_height
	_area.monitoring = true
	_area.monitorable = false
	_area.collision_mask = 1
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.5, 1.6, 1.5)
	col.shape = box
	_area.add_child(col)
	add_child(_area)

	if not Engine.is_editor_hint():
		_area.body_entered.connect(_on_body_entered)
	elif show_editor_guides:
		var guide_mat: StandardMaterial3D = StandardMaterial3D.new()
		guide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		guide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var accent: Color = Color("f97316") if powerup_type == PowerupType.BOMB else tint_color
		guide_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.35)

		var ring: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.72
		torus.outer_radius = 0.82
		ring.mesh = torus
		ring.material_override = guide_mat
		ring.position.y = 0.04
		add_child(ring)

func reset_powerup() -> void:
	_collected = false
	_respawn_timer = 0.0
	visible = true
	if _area != null:
		_area.set_deferred("monitoring", true)

func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	_collected = true
	_respawn_timer = respawn_seconds
	visible = false
	_area.set_deferred("monitoring", false)

	var sfx: SoundEngine = get_tree().root.find_child("SoundEngine", true, false) as SoundEngine
	if sfx != null:
		sfx.play(&"recall", 1.0)

	collected.emit(powerup_type, body)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _visual_pivot == null:
		return

	_elapsed += delta
	if _collected:
		if respawn_seconds > 0.0:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				reset_powerup()
		return

	_visual_pivot.position.y = hover_height + sin(_elapsed * 3.2) * 0.18
	_visual_pivot.rotation.y = _elapsed * 2.0