extends Node3D
class_name EnemyProjectile

var velocity: Vector3 = Vector3.ZERO
var gravity_accel: float = 0.0
var max_lifetime: float = 4.5
var explosion_radius: float = 3.2
var jostle_horizontal: float = 15.5
var jostle_upward: float = 8.5
var proj_color: Color = Color("f97316")
var owner_enemy: Node3D = null

var _age: float = 0.0
var _exploded: bool = false
var _mesh: MeshInstance3D = null

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.30
	sphere.height = 0.60
	_mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = proj_color
	mat.emission_enabled = true
	mat.emission = proj_color
	mat.emission_energy_multiplier = 1.6
	_mesh.material_override = mat
	add_child(_mesh)

func _physics_process(delta: float) -> void:
	if _exploded:
		return

	_age += delta
	if _age >= max_lifetime:
		_detonate(global_position)
		return

	velocity.y -= gravity_accel * delta
	var next_pos := global_position + velocity * delta

	var exclude: Array[RID] = []
	if owner_enemy is CollisionObject3D:
		exclude.append((owner_enemy as CollisionObject3D).get_rid())

	var query := PhysicsRayQueryParameters3D.create(global_position, next_pos)
	query.exclude = exclude
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		_detonate(hit["position"] as Vector3)
		return

	global_position = next_pos
	if _mesh != null:
		var pulse := 1.0 + sin(_age * 28.0) * 0.14
		_mesh.scale = Vector3.ONE * pulse

func _detonate(impact_pos: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	global_position = impact_pos

	# Jostle PlayerStack if within explosion radius
	var stacks := get_tree().get_nodes_in_group("player_stack")
	if stacks.is_empty():
		var fallback := get_tree().root.find_child("PlayerStack", true, false)
		if fallback != null:
			stacks = [fallback]

	for node in stacks:
		if not (node is PlayerStack):
			continue
		var ps := node as PlayerStack
		var stack_center := ps.get_stack_center()
		var diff := stack_center - impact_pos
		var dist := diff.length()
		if dist <= explosion_radius:
			var falloff := clampf(1.0 - (dist / maxf(0.1, explosion_radius)) * 0.55, 0.45, 1.0)
			var push_dir := Vector3(diff.x, 0.0, diff.z)
			if push_dir.length_squared() < 0.001:
				push_dir = Vector3(velocity.x, 0.0, velocity.z)
			if push_dir.length_squared() < 0.001:
				push_dir = Vector3.FORWARD
			push_dir = push_dir.normalized()

			var impulse := Vector3(
				push_dir.x * jostle_horizontal * falloff,
				jostle_upward * falloff,
				push_dir.z * jostle_horizontal * falloff
			)
			ps.apply_external_jostle(impulse, 0.65 * falloff)

	# Play explosion sound if SoundEngine exists
	var snd := get_tree().root.find_child("SoundEngine", true, false)
	if snd != null and snd.has_method("play"):
		snd.call("play", &"explode", 0.65, randf_range(0.95, 1.15))

	# Spawn expanding blast sphere visual then free
	_spawn_blast_ring(impact_pos)
	queue_free()

func _spawn_blast_ring(at_pos: Vector3) -> void:
	var blast := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	blast.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(proj_color.r, proj_color.g, proj_color.b, 0.75)
	blast.material_override = mat

	get_parent().add_child(blast)
	blast.global_position = at_pos

	var tween := blast.create_tween()
	tween.set_parallel(true)
	tween.tween_property(blast, "scale", Vector3.ONE * (explosion_radius * 2.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tween.chain().tween_callback(blast.queue_free)