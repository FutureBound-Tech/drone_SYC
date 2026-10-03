class_name TrainingDrone
extends CharacterBody3D

var flight_profile: Dictionary = {}
var channels := Vector4(0.0, 0.0, 0.0, 0.0) # roll, pitch, yaw, throttle
var assists_enabled := true
var armed := false
var has_crashed := false
var body_rates := Vector3.ZERO
var motor_output := 0.0
var sound_playback
var sound_phase := 0.0
var motor_player: AudioStreamPlayer

func _ready() -> void:
	_build_visuals()
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.22
	collision.shape = shape
	add_child(collision)
	_setup_motor_audio()

func configure(profile: Dictionary) -> void:
	flight_profile = profile.duplicate(true)

func set_controls(value: Vector4) -> void:
	channels = value

func set_audio_paused(paused: bool) -> void:
	if is_instance_valid(motor_player):
		motor_player.stream_paused = paused

func reset_at(point: Vector3) -> void:
	global_position = point
	global_rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	body_rates = Vector3.ZERO
	motor_output = 0.0
	has_crashed = false
	armed = true

func _process(_delta: float) -> void:
	if sound_playback == null or not is_instance_valid(motor_player) or not motor_player.playing:
		return
	var frames: int = sound_playback.get_frames_available()
	var mix_rate := 22050.0
	var frequency := 72.0 + channels.w * 185.0
	while frames > 0:
		var sample := 0.0
		if armed:
			sample = (sin(sound_phase) + 0.28 * sin(sound_phase * 2.03) + 0.09 * sin(sound_phase * 3.97)) * (0.025 + channels.w * 0.045)
		sound_playback.push_frame(Vector2(sample, sample))
		sound_phase = fmod(sound_phase + TAU * frequency / mix_rate, TAU)
		frames -= 1

func _physics_process(delta: float) -> void:
	if not armed:
		return
	var roll_rate := float(flight_profile.get("roll_rate", 720.0))
	var pitch_rate := float(flight_profile.get("pitch_rate", 720.0))
	var yaw_rate := float(flight_profile.get("yaw_rate", 540.0))
	var rate_scale := 1.0 if not assists_enabled else 0.62
	var target_rates := Vector3(
		-channels.x * deg_to_rad(roll_rate * rate_scale),
		-channels.y * deg_to_rad(pitch_rate * rate_scale),
		-channels.z * deg_to_rad(yaw_rate * rate_scale)
	)
	body_rates = body_rates.lerp(target_rates, 1.0 - exp(-8.0 * delta))
	rotate_object_local(Vector3.FORWARD, body_rates.x * delta)
	rotate_object_local(Vector3.RIGHT, body_rates.y * delta)
	rotate_object_local(Vector3.UP, body_rates.z * delta)
	if assists_enabled:
		var correction_axis := global_basis.y.cross(Vector3.UP)
		if correction_axis.length() > 0.001:
			var tilt_angle := acos(clampf(global_basis.y.dot(Vector3.UP), -1.0, 1.0))
			global_rotate(correction_axis.normalized(), minf(tilt_angle, 1.6 * delta))
	motor_output = lerpf(motor_output, clampf(channels.w, 0.0, 1.0), 1.0 - exp(-12.0 * delta))
	var thrust := float(flight_profile.get("thrust", 22.0)) * motor_output
	velocity += (global_basis.y * thrust + Vector3.DOWN * 9.8) * delta
	velocity *= exp(-0.025 * delta)
	var impact_speed := velocity.length()
	move_and_slide()
	if get_slide_collision_count() > 0 and impact_speed > 8.0:
		has_crashed = true
		armed = false
		velocity = Vector3.ZERO
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0

func _setup_motor_audio() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.12
	motor_player = AudioStreamPlayer.new()
	motor_player.name = "MotorAudio"
	motor_player.bus = "Effects"
	motor_player.stream = stream
	add_child(motor_player)
	motor_player.play()
	sound_playback = motor_player.get_stream_playback()

func _build_visuals() -> void:
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.34, 0.09, 0.28)
	body.mesh = body_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.08, 0.12, 0.17)
	body_mat.metallic = 0.45
	body_mat.roughness = 0.38
	body.material_override = body_mat
	add_child(body)
	for side in [-1.0, 1.0]:
		for forward in [-1.0, 1.0]:
			var arm := MeshInstance3D.new()
			var arm_mesh := BoxMesh.new()
			arm_mesh.size = Vector3(0.06, 0.035, 0.42)
			arm.mesh = arm_mesh
			arm.position = Vector3(side * 0.13, 0.0, forward * 0.16)
			arm.rotation.y = side * forward * 0.75
			var arm_mat := StandardMaterial3D.new()
			arm_mat.albedo_color = Color(0.12, 0.82, 0.86) if forward < 0.0 else Color(1.0, 0.39, 0.16)
			arm.material_override = arm_mat
			add_child(arm)
			var motor := MeshInstance3D.new()
			var motor_mesh := CylinderMesh.new()
			motor_mesh.top_radius = 0.045
			motor_mesh.bottom_radius = 0.045
			motor_mesh.height = 0.04
			motor.mesh = motor_mesh
			motor.position = Vector3(side * 0.26, 0.02, forward * 0.31)
			motor.material_override = body_mat
			add_child(motor)
	var camera := Camera3D.new()
	camera.name = "FPVCamera"
	camera.position = Vector3(0.0, 0.05, -0.14)
	camera.rotation.x = deg_to_rad(-float(flight_profile.get("camera_angle", 25.0)))
	camera.fov = 100.0
	camera.current = true
	add_child(camera)
