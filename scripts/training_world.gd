class_name TrainingWorld
extends Node3D

var gates: Array[Node3D] = []
var course_id := "yard_loop"
var spawn_point := Vector3(0.0, 1.1, 0.0)

func build() -> void:
	_add_environment()
	_add_floor()
	_add_practice_obstacles()
	_add_gates()

func _add_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.035, 0.075, 0.14)
	sky_mat.sky_horizon_color = Color(0.28, 0.42, 0.54)
	sky_mat.ground_bottom_color = Color(0.025, 0.04, 0.045)
	sky_mat.ground_horizon_color = Color(0.16, 0.21, 0.19)
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.46, 0.58)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

func _add_floor() -> void:
	var floor := StaticBody3D.new()
	floor.name = "Ground"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	mesh.mesh = box
	mesh.position.y = -0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.105, 0.145, 0.13)
	mat.roughness = 0.96
	mesh.material_override = mat
	floor.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	collision.position.y = -0.5
	floor.add_child(collision)
	add_child(floor)
	for i in range(-5, 6):
		var stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(0.025, 0.006, 100.0)
		stripe.mesh = stripe_mesh
		stripe.position = Vector3(i * 5.0, 0.008, 0.0)
		var stripe_mat := StandardMaterial3D.new()
		stripe_mat.albedo_color = Color(0.19, 0.26, 0.23, 0.6)
		stripe_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		stripe.material_override = stripe_mat
		add_child(stripe)

func _add_practice_obstacles() -> void:
	var positions := [Vector3(-12, 0, -10), Vector3(12, 0, -13), Vector3(-15, 0, 12), Vector3(14, 0, 10), Vector3(0, 0, 19)]
	for index in range(positions.size()):
		var pillar := StaticBody3D.new()
		pillar.position = positions[index]
		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.42
		cylinder.bottom_radius = 0.62
		cylinder.height = 3.2 + float(index % 3) * 0.8
		mesh.mesh = cylinder
		mesh.position.y = cylinder.height * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.26, 0.28)
		mat.roughness = 0.8
		mesh.material_override = mat
		pillar.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.55
		shape.height = cylinder.height
		collision.shape = shape
		collision.position.y = cylinder.height * 0.5
		pillar.add_child(collision)
		add_child(pillar)
	_add_arch(Vector3(-7, 0, -18), Vector3(4.0, 3.2, 0.35), Color(0.95, 0.38, 0.14))
	_add_arch(Vector3(8, 0, 17), Vector3(4.0, 3.2, 0.35), Color(0.14, 0.75, 0.82))

func _add_gates() -> void:
	var gate_data := [
		{"pos": Vector3(0, 2.2, -9), "yaw": 0.0},
		{"pos": Vector3(9, 2.3, -13), "yaw": -45.0},
		{"pos": Vector3(14, 2.1, 0), "yaw": -90.0},
		{"pos": Vector3(7, 2.4, 12), "yaw": -135.0},
		{"pos": Vector3(-8, 2.2, 11), "yaw": -180.0},
		{"pos": Vector3(-13, 2.0, 0), "yaw": -225.0},
	]
	for index in range(gate_data.size()):
		var gate: Node3D = _make_gate(index + 1)
		gate.position = gate_data[index].pos
		gate.rotation.y = deg_to_rad(float(gate_data[index].yaw))
		gates.append(gate)
		add_child(gate)

func _make_gate(number: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Gate_%02d" % number
	var color := Color(0.13, 0.82, 0.85) if number % 2 == 1 else Color(1.0, 0.4, 0.17)
	for side in [-1.0, 1.0]:
		_add_gate_bar(root, Vector3(side * 2.0, 1.5, 0.0), Vector3(0.14, 3.0, 0.16), color)
	_add_gate_bar(root, Vector3(0.0, 3.0, 0.0), Vector3(4.1, 0.14, 0.16), color)
	return root

func _add_gate_bar(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var bar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	bar.mesh = mesh
	bar.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.22
	bar.material_override = mat
	parent.add_child(bar)

func _add_arch(pos: Vector3, size: Vector3, color: Color) -> void:
	var arch := Node3D.new()
	arch.position = pos
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.18, size.y, size.z)
		leg.mesh = leg_mesh
		leg.position = Vector3(side * size.x * 0.5, size.y * 0.5, 0.0)
		leg.material_override = _accent_material(color)
		arch.add_child(leg)
	var top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(size.x, 0.18, size.z)
	top.mesh = top_mesh
	top.position.y = size.y
	top.material_override = _accent_material(color)
	arch.add_child(top)
	add_child(arch)

func _accent_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.18
	return material
