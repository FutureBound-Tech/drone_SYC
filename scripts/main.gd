extends Node

const STORE = preload("res://scripts/profile_store.gd")
const DRONE = preload("res://scripts/drone.gd")
const WORLD = preload("res://scripts/training_world.gd")
const CHANNELS = ["roll", "pitch", "yaw", "throttle"]
const BG = Color(0.027, 0.039, 0.057)
const PANEL = Color(0.052, 0.072, 0.095)
const LIGHT = Color(0.078, 0.105, 0.13)
const WHITE = Color(0.88, 0.93, 0.95)
const MUTED = Color(0.48, 0.57, 0.63)
const CYAN = Color(0.16, 0.84, 0.88)
const ORANGE = Color(1.0, 0.40, 0.18)

var store
var settings: Dictionary
var flight: Dictionary
var controller: Dictionary
var ui: Control
var page: Control
var drone
var world
var mode := "home"
var joy_device := -1
var capture_channel := ""
var capture_maps: Dictionary = {}
var range_capture_active := false
var range_capture_remaining := 0.0
var race_active := false
var race_time := 0.0
var gate_index := 0
var course_id := "yard_loop"
var race_label: Label
var timer_label: Label
var speed_label: Label
var assist_label: Label
var toast: Label
var profile_name_input: LineEdit

func _ready() -> void:
	store = STORE.new()
	store.load_data()
	settings = store.settings()
	flight = store.flight()
	controller = store.controller()
	_create_audio_buses()
	_apply_settings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	_show_home()

func _input(event: InputEvent) -> void:
	if not capture_channel.is_empty() and event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.device == joy_device and absf(motion.axis_value) > 0.48:
			for other_channel in CHANNELS:
				if other_channel == capture_channel: continue
				var other_mapping: Dictionary = capture_maps.get(other_channel, _channel_map(other_channel))
				if int(other_mapping.get("axis", -1)) == int(motion.axis):
					var duplicate_prompt := page.find_child("CapturePrompt", true, false) as Label
					if duplicate_prompt != null: duplicate_prompt.text = "That axis is already assigned to %s. Move a different control." % other_channel.to_upper()
					return
			capture_maps[capture_channel] = {"axis": motion.axis, "reversed": false, "min": -1.0, "max": 1.0}
			var prompt := page.find_child("CapturePrompt", true, false) as Label
			if prompt != null:
				prompt.text = "%s mapped to axis %d. Check direction and reverse if needed." % [capture_channel.to_upper(), motion.axis]
			capture_channel = ""
			_refresh_calibration()
	if mode == "flight" and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_show_pause()
		elif event.keycode == KEY_R:
			_reset_session()

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if device != int(controller.get("device", -1)):
		return
	if not connected and mode == "flight":
		mode = "disconnected"
		drone.set_physics_process(false)
		drone.set_audio_paused(true)
		var dim := ColorRect.new()
		dim.name = "DisconnectOverlay"
		dim.color = Color(0.01, 0.02, 0.03, 0.82)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		page.add_child(dim)
		var box := _modal_box(dim, 440, 220)
		_label(box, "RADIO DISCONNECTED", 21, ORANGE, true)
		_label(box, "Reconnect the selected joystick to resume flight.", 13, MUTED)
		var menu := _button("RETURN TO MENU", LIGHT)
		menu.pressed.connect(_show_home)
		box.add_child(menu)
	elif connected and mode == "disconnected":
		var overlay := page.get_node_or_null("DisconnectOverlay")
		if overlay != null: overlay.queue_free()
		mode = "flight"
		drone.set_physics_process(true)
		drone.set_audio_paused(false)
	elif not connected and mode == "calibration":
		_show_toast("Selected joystick disconnected. Reconnect or choose another device.")

func _process(delta: float) -> void:
	if mode == "calibration":
		_update_calibration_meters()
		if range_capture_active:
			_update_range_capture(delta)
		return
	if mode != "flight" or not is_instance_valid(drone):
		return
	var controls := _read_controls()
	drone.set_controls(controls)
	if speed_label != null:
		speed_label.text = "%03d KM/H" % int(drone.velocity.length() * 3.6)
	if assist_label != null:
		assist_label.text = "ASSIST ON" if drone.assists_enabled else "ACRO"
	if race_active:
		race_time += delta
		if timer_label != null:
			timer_label.text = _time(race_time)
		_update_gates()
	if mode == "flight" and drone.has_crashed:
		_show_crash()

func _show_home() -> void:
	mode = "home"
	_unlock_mouse()
	if is_instance_valid(world):
		world.queue_free()
		world = null
	if is_instance_valid(drone):
		drone.queue_free()
		drone = null
	race_label = null
	timer_label = null
	speed_label = null
	assist_label = null
	_new_page()
	var layout := _base_layout()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 45)
	layout.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 430
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	_label(left, "ROTORLINE  /  FPV TRAINER", 12, CYAN, true)
	_spacer(left, 25)
	_label(left, "Find your\nline.", 60, WHITE, true)
	_label(left, "A flight lab for pilots who want more stick time.", 16, MUTED)
	_spacer(left, 18)
	var ready := _radio_ready()
	_label(left, "RADIO READY" if ready else "RADIO NOT CALIBRATED  ·  KEYBOARD PRACTICE AVAILABLE", 11, CYAN if ready else ORANGE, true)
	_spacer(left, 12)
	_menu_button(left, "FREE FLIGHT", "Open the practice yard", Callable(self, "_start_free"), CYAN)
	_menu_button(left, "RACE", "Timed checkpoint courses", Callable(self, "_show_races"), ORANGE)
	_menu_button(left, "TRANSMITTER SETUP", "Map channels and save a radio profile", Callable(self, "_show_calibration"), LIGHT)
	_menu_button(left, "FLIGHT TUNING", "Presets, rates, camera angle", Callable(self, "_show_flight_settings"), LIGHT)
	_menu_button(left, "SETTINGS", "Graphics and audio", Callable(self, "_show_settings"), LIGHT)
	_spacer(left, 10)
	_label(left, "V1  ·  SOLO PRACTICE  ·  OFFLINE READY", 10, MUTED, true)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style(PANEL, 18, Color(0.15, 0.21, 0.26), 1))
	row.add_child(card)
	var art := Control.new()
	card.add_child(art)
	var title := Label.new()
	title.text = "PRACTICE YARD  /  01"
	title.position = Vector2(24, 22)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", MUTED)
	art.add_child(title)
	var drone_art := Control.new()
	drone_art.position = Vector2(300, 260)
	var body := ColorRect.new()
	body.color = Color(0.14, 0.19, 0.23)
	body.size = Vector2(110, 22)
	body.position = Vector2(-55, -11)
	drone_art.add_child(body)
	for side in [-1, 1]:
		for front in [-1, 1]:
			var arm := ColorRect.new()
			arm.color = CYAN if front < 0 else ORANGE
			arm.size = Vector2(75, 6)
			arm.position = Vector2(side * 10 - 38, front * 26 - 3)
			arm.rotation = deg_to_rad(side * front * 35.0)
			drone_art.add_child(arm)
	art.add_child(drone_art)
	var legend := Label.new()
	legend.text = "5 INCH  /  ACRO  /  25° CAMERA"
	legend.position = Vector2(24, 490)
	legend.add_theme_color_override("font_color", CYAN)
	art.add_child(legend)
	if not store.load_warning.is_empty():
		_show_toast(store.load_warning)

func _show_calibration() -> void:
	mode = "calibration"
	var saved_channels: Dictionary = controller.get("channels", {})
	capture_maps = saved_channels.duplicate(true)
	range_capture_active = false
	_new_page()
	var layout := _base_layout()
	_page_header(layout, "RADIO SETUP", "Map the transmitter axes used for flight.")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	layout.add_child(columns)
	var left := _card(columns, 620)
	_label(left, "01  /  DEVICE", 12, CYAN, true)
	_label(left, "Select a Linux joystick device.", 14, MUTED)
	var devices := OptionButton.new()
	var found := Input.get_connected_joypads()
	for id in found:
		devices.add_item("%s  ·  device %d" % [Input.get_joy_name(id), id], id)
	if found.is_empty():
		devices.add_item("No joystick detected", -1)
	elif devices.item_count > 0:
		devices.select(0)
	for i in range(devices.item_count):
		if devices.get_item_id(i) == int(controller.get("device", -1)):
			devices.select(i)
	devices.item_selected.connect(func(i: int) -> void: joy_device = devices.get_item_id(i))
	joy_device = devices.get_item_id(devices.selected)
	left.add_child(devices)
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 8)
	left.add_child(profile_row)
	var picker := OptionButton.new()
	picker.add_item("New profile")
	var saved_profiles: Dictionary = store.controller_profiles()
	for profile_id in saved_profiles.keys(): picker.add_item(str(profile_id))
	var active_id := str(controller.get("profile_id", ""))
	if not active_id.is_empty():
		for i in range(picker.item_count):
			if picker.get_item_text(i) == active_id: picker.select(i)
	picker.item_selected.connect(func(index: int) -> void:
		if index == 0:
			controller = {"name": "", "device": joy_device, "channels": {}}
			capture_maps.clear()
		else:
			var profile_id: String = picker.get_item_text(index)
			controller = saved_profiles[profile_id].duplicate(true)
			capture_maps = controller.get("channels", {}).duplicate(true)
			profile_name_input.text = profile_id
			for device_index in range(devices.item_count):
				if devices.get_item_id(device_index) == int(controller.get("device", -1)):
					devices.select(device_index)
					joy_device = devices.get_item_id(device_index)
		_refresh_calibration()
	)
	profile_row.add_child(picker)
	profile_name_input = LineEdit.new()
	profile_name_input.placeholder_text = "Local profile name"
	profile_name_input.text = str(controller.get("profile_id", ""))
	profile_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(profile_name_input)
	_spacer(left, 8)
	_label(left, "02  /  CHANNEL MAP", 12, CYAN, true)
	_label(left, "Assign each channel, then move the stick through its range.", 14, MUTED)
	for channel in CHANNELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		left.add_child(row)
		var channel_title := _label(row, channel.to_upper(), 12, WHITE, true)
		channel_title.custom_minimum_size.x = 96
		var status := _label(row, _map_text(channel), 12, CYAN if _is_mapped(channel) else MUTED)
		status.name = "Map_" + channel
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var assign := _button("ASSIGN", LIGHT)
		assign.pressed.connect(_begin_capture.bind(channel))
		row.add_child(assign)
		var reverse := _button("REVERSE", LIGHT)
		reverse.modulate = ORANGE if _is_reversed(channel) else Color.WHITE
		reverse.pressed.connect(_reverse_channel.bind(channel))
		row.add_child(reverse)
	var right := _card(columns, 360)
	_label(right, "STICK MONITOR", 12, CYAN, true)
	_label(right, "Live transmitter input", 15, WHITE)
	for channel in CHANNELS:
		var meter := ProgressBar.new()
		meter.name = "Meter_" + channel
		meter.min_value = -1.0 if channel != "throttle" else 0.0
		meter.max_value = 1.0
		meter.show_percentage = false
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var meter_row := HBoxContainer.new()
		var meter_title := _label(meter_row, channel.to_upper(), 10, MUTED)
		meter_title.custom_minimum_size.x = 86
		meter_row.add_child(meter)
		right.add_child(meter_row)
	var prompt := _label(right, "Choose a device and assign all four controls.", 13, MUTED)
	prompt.name = "CapturePrompt"
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ranges := _button("CALIBRATE ENDPOINTS  ·  8 SEC", LIGHT)
	ranges.pressed.connect(_start_range_calibration)
	right.add_child(ranges)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	layout.add_child(buttons)
	var save := _button("SAVE RADIO PROFILE", CYAN)
	save.pressed.connect(_save_controller)
	buttons.add_child(save)
	var back := _button("BACK", LIGHT)
	back.pressed.connect(_show_home)
	buttons.add_child(back)
	if found.is_empty():
		_label(right, "You can practice with keyboard controls while connecting a transmitter.", 11, ORANGE)
	_refresh_calibration()

func _begin_capture(channel: String) -> void:
	if not Input.get_connected_joypads().has(joy_device):
		_show_toast("Connect and select a joystick first.")
		return
	capture_channel = channel
	var prompt := page.find_child("CapturePrompt", true, false) as Label
	if prompt != null:
		prompt.text = "Move only the %s stick axis now." % channel.to_upper()
		prompt.add_theme_color_override("font_color", ORANGE)

func _start_range_calibration() -> void:
	for channel in CHANNELS:
		if not _is_mapped(channel):
			_show_toast("Assign all four channels before calibrating endpoints.")
			return
	if not Input.get_connected_joypads().has(joy_device):
		_show_toast("Connect the selected joystick before calibrating endpoints.")
		return
	for channel in CHANNELS:
		var entry: Dictionary = capture_maps.get(channel, _channel_map(channel)).duplicate(true)
		entry["min"] = 1.0
		entry["max"] = -1.0
		capture_maps[channel] = entry
	range_capture_remaining = 8.0
	range_capture_active = true
	var prompt := page.find_child("CapturePrompt", true, false) as Label
	if prompt != null:
		prompt.text = "Move each stick axis through both full endpoints. Saving in 8 seconds."
		prompt.add_theme_color_override("font_color", ORANGE)

func _update_range_capture(delta: float) -> void:
	var channels: Dictionary = controller.get("channels", {})
	for channel in CHANNELS:
		var entry: Dictionary = capture_maps.get(channel, channels.get(channel, {}))
		var axis := int(entry.get("axis", -1))
		if axis < 0: continue
		var value := Input.get_joy_axis(joy_device, axis)
		entry["min"] = minf(float(entry.get("min", 1.0)), value)
		entry["max"] = maxf(float(entry.get("max", -1.0)), value)
		capture_maps[channel] = entry
	range_capture_remaining -= delta
	var prompt := page.find_child("CapturePrompt", true, false) as Label
	if range_capture_remaining > 0.0:
		if prompt != null: prompt.text = "Move each axis to both endpoints. %.1f seconds remaining." % range_capture_remaining
		return
	range_capture_active = false
	var incomplete: Array[String] = []
	for channel in CHANNELS:
		var entry: Dictionary = capture_maps.get(channel, {})
		if float(entry.get("max", -1.0)) - float(entry.get("min", 1.0)) < 0.8:
			incomplete.append(channel.to_upper())
	if prompt != null:
		var missing := ""
		for channel_name in incomplete:
			missing += (", " if not missing.is_empty() else "") + channel_name
		prompt.text = "Range complete." if incomplete.is_empty() else "Insufficient movement for %s. Run endpoint calibration again." % missing
		prompt.add_theme_color_override("font_color", CYAN if incomplete.is_empty() else ORANGE)

func _normalized_axis(raw: float, mapping: Dictionary, throttle: bool) -> float:
	var low := float(mapping.get("min", -1.0))
	var high := float(mapping.get("max", 1.0))
	if high - low < 0.1:
		low = -1.0
		high = 1.0
	if throttle:
		return clampf((raw - low) / (high - low), 0.0, 1.0)
	var center := (low + high) * 0.5
	var half_range := maxf((high - low) * 0.5, 0.05)
	return clampf((raw - center) / half_range, -1.0, 1.0)

func _reverse_channel(channel: String) -> void:
	var entry: Dictionary = capture_maps.get(channel, _channel_map(channel))
	if entry.is_empty():
		entry = {"axis": -1, "reversed": false, "min": -1.0, "max": 1.0}
	entry["reversed"] = not bool(entry.get("reversed", false))
	capture_maps[channel] = entry
	_refresh_calibration()

func _refresh_calibration() -> void:
	if page == null:
		return
	for channel in CHANNELS:
		var label := page.find_child("Map_" + channel, true, false) as Label
		if label != null:
			label.text = _map_text(channel)
			label.add_theme_color_override("font_color", CYAN if _is_mapped(channel) else MUTED)

func _save_controller() -> void:
	for channel in CHANNELS:
		if not _is_mapped(channel):
			_show_toast("Assign all four channels before saving.")
			return
	var profile_id := profile_name_input.text.strip_edges()
	if profile_id.is_empty():
		profile_id = Input.get_joy_name(joy_device)
	var profile := {"name": Input.get_joy_name(joy_device), "profile_id": profile_id, "device": joy_device, "channels": capture_maps.duplicate(true)}
	var err: Error = store.save_controller(profile)
	if err != OK:
		_show_toast("Could not save the radio profile.")
		return
	controller = profile
	_show_toast("Radio profile saved.")

func _show_flight_settings() -> void:
	mode = "flight_settings"
	_new_page()
	var layout := _base_layout()
	_page_header(layout, "FLIGHT TUNING", "Start from a preset, then adjust key rates and camera angle.")
	var card := _card(layout, 850)
	_label(card, "FLIGHT PRESETS", 12, CYAN, true)
	var presets := HBoxContainer.new()
	for preset in ["Balanced 5 inch", "Smooth freestyle", "Quick racing"]:
		var button := _button(preset.to_upper(), LIGHT)
		button.pressed.connect(_apply_preset.bind(preset))
		presets.add_child(button)
	card.add_child(presets)
	_spacer(card, 8)
	_flight_slider(card, "roll_rate", "ROLL RATE", 200, 1200, "°/s")
	_flight_slider(card, "pitch_rate", "PITCH RATE", 200, 1200, "°/s")
	_flight_slider(card, "yaw_rate", "YAW RATE", 150, 900, "°/s")
	_flight_slider(card, "thrust", "MAX THRUST", 14, 32, "m/s²")
	_flight_slider(card, "camera_angle", "CAMERA ANGLE", 0, 45, "°")
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	var save := _button("SAVE FLIGHT PROFILE", CYAN)
	save.pressed.connect(func() -> void: _show_toast("Flight profile saved." if store.save_flight(flight) == OK else "Could not save flight profile."))
	actions.add_child(save)
	var back := _button("BACK", LIGHT)
	back.pressed.connect(_show_home)
	actions.add_child(back)

func _apply_preset(name: String) -> void:
	flight["name"] = name
	match name:
		"Smooth freestyle": flight.merge({"roll_rate": 560.0, "pitch_rate": 560.0, "yaw_rate": 430.0, "thrust": 20.0, "camera_angle": 18.0}, true)
		"Quick racing": flight.merge({"roll_rate": 920.0, "pitch_rate": 920.0, "yaw_rate": 680.0, "thrust": 25.0, "camera_angle": 35.0}, true)
		_: flight.merge({"roll_rate": 720.0, "pitch_rate": 720.0, "yaw_rate": 540.0, "thrust": 22.0, "camera_angle": 25.0}, true)
	_show_flight_settings()

func _flight_slider(parent: Control, key: String, title: String, low: float, high: float, units: String) -> void:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var heading := HBoxContainer.new()
	row.add_child(heading)
	_label(heading, title, 11, MUTED, true)
	var value := _label(heading, "", 11, WHITE)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.value = float(flight.get(key, low))
	slider.value_changed.connect(func(v: float) -> void:
		flight[key] = v
		value.text = "%.0f %s" % [v, units]
	)
	value.text = "%.0f %s" % [slider.value, units]
	row.add_child(slider)

func _show_settings() -> void:
	mode = "settings"
	_new_page()
	var layout := _base_layout()
	_page_header(layout, "SETTINGS", "Display, performance, and audio.")
	var card := _card(layout, 850)
	_label(card, "DISPLAY", 12, CYAN, true)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = bool(settings.get("fullscreen", false))
	fullscreen.toggled.connect(func(v: bool) -> void:
		settings["fullscreen"] = v
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if v else Window.MODE_WINDOWED
	)
	card.add_child(fullscreen)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	_label(row, "QUALITY", 12, WHITE)
	var quality := OptionButton.new()
	for option in ["Low", "Medium", "High"]:
		quality.add_item(option)
	quality.select(["Low", "Medium", "High"].find(str(settings.get("quality", "High"))))
	quality.item_selected.connect(func(index: int) -> void: settings["quality"] = quality.get_item_text(index); _apply_quality())
	row.add_child(quality)
	_label(row, "RESOLUTION", 12, WHITE)
	var resolution := OptionButton.new()
	var resolutions := ["1280x720", "1600x900", "1920x1080"]
	for option in resolutions:
		resolution.add_item(option)
	resolution.select(maxi(0, resolutions.find(str(settings.get("resolution", "1280x720")))))
	resolution.item_selected.connect(func(index: int) -> void:
		settings["resolution"] = resolution.get_item_text(index)
		_apply_resolution()
	)
	row.add_child(resolution)
	_label(row, "FRAME CAP", 12, WHITE)
	var fps := OptionButton.new()
	for cap in [30, 60, 90, 120, 144, 0]:
		fps.add_item("Unlimited" if cap == 0 else "%d FPS" % cap, cap)
	for i in range(fps.item_count):
		if fps.get_item_id(i) == int(settings.get("frame_cap", 60)):
			fps.select(i)
	fps.item_selected.connect(func(i: int) -> void: settings["frame_cap"] = fps.get_item_id(i); Engine.max_fps = int(settings.frame_cap))
	row.add_child(fps)
	_spacer(card, 12)
	_label(card, "AUDIO", 12, CYAN, true)
	_audio_slider(card, "master_volume", "MASTER", "Master")
	_audio_slider(card, "music_volume", "MUSIC", "Music")
	_audio_slider(card, "effects_volume", "EFFECTS", "Effects")
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	var save := _button("SAVE SETTINGS", CYAN)
	save.pressed.connect(func() -> void: _show_toast("Settings saved." if store.save_settings(settings) == OK else "Could not save settings."))
	actions.add_child(save)
	var back := _button("BACK", LIGHT)
	back.pressed.connect(_show_home)
	actions.add_child(back)

func _audio_slider(parent: Control, key: String, title: String, bus: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var title_label := _label(row, title, 11, MUTED, true)
	title_label.custom_minimum_size.x = 95
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(settings.get(key, 0.8))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		settings[key] = value
		var index := AudioServer.get_bus_index(bus)
		if index >= 0: AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	)
	row.add_child(slider)

func _apply_settings() -> void:
	Engine.max_fps = int(settings.get("frame_cap", 60))
	get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if bool(settings.get("fullscreen", false)) else Window.MODE_WINDOWED
	_apply_resolution()
	for pair in [["Master", "master_volume"], ["Music", "music_volume"], ["Effects", "effects_volume"]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index >= 0: AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(settings.get(pair[1], 0.8)), 0.0001)))
	_apply_quality()

func _apply_resolution() -> void:
	var parts := str(settings.get("resolution", "1280x720")).split("x")
	if parts.size() == 2:
		get_window().size = Vector2i(int(parts[0]), int(parts[1]))

func _create_audio_buses() -> void:
	for name in ["Music", "Effects"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")

func _apply_quality() -> void:
	if is_instance_valid(world):
		var sun := world.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = settings.get("quality", "High") != "Low"
			sun.directional_shadow_max_distance = 35.0 if settings.get("quality", "High") == "Low" else 80.0

func _show_races() -> void:
	mode = "race_select"
	_new_page()
	var layout := _base_layout()
	_page_header(layout, "RACE  /  TIME TRIAL", "Pass every checkpoint in sequence. Results are saved locally.")
	var card := _card(layout, 760)
	_label(card, "YARD LOOP", 22, WHITE, true)
	var best: float = store.best_time("yard_loop")
	_label(card, "6 gates  ·  1 lap  ·  best time " + (_time(best) if best > 0.0 else "—"), 14, MUTED)
	var start := _button("FLY YARD LOOP", ORANGE)
	start.pressed.connect(func() -> void: _start_race("yard_loop"))
	card.add_child(start)
	var back := _button("BACK", LIGHT)
	back.pressed.connect(_show_home)
	layout.add_child(back)

func _start_free() -> void:
	_start_session("freestyle")

func _start_race(course: String) -> void:
	course_id = course
	_start_session("race")

func _start_session(kind: String) -> void:
	mode = "flight"
	_unlock_mouse()
	_new_page()
	if is_instance_valid(world): world.queue_free()
	if is_instance_valid(drone): drone.queue_free()
	world = WORLD.new()
	world.name = "TrainingWorld"
	world.build()
	add_child(world)
	drone = DRONE.new()
	drone.name = "Quadcopter"
	drone.configure(flight)
	add_child(drone)
	drone.reset_at(Vector3(0.0, 1.1, -1.0))
	drone.assists_enabled = true
	race_active = kind == "race"
	race_time = 0.0
	gate_index = 0
	_build_flight_hud(kind)
	_apply_quality()

func _build_flight_hud(kind: String) -> void:
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(page)
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 60
	top.add_theme_stylebox_override("panel", _style(Color(0.025, 0.04, 0.055, 0.9), 0, Color.TRANSPARENT, 0))
	page.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	top.add_child(row)
	_label(row, "ROTORLINE  /  " + ("FREE FLIGHT" if kind == "freestyle" else "YARD LOOP"), 12, CYAN, true)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	assist_label = _label(row, "ASSIST ON", 11, WHITE, true)
	speed_label = _label(row, "000 KM/H", 12, WHITE, true)
	timer_label = _label(row, "00:00.000", 15, ORANGE, true)
	var pause := _button("PAUSE  [ESC]", LIGHT)
	pause.pressed.connect(_show_pause)
	row.add_child(pause)
	var crosshair := _label(page, "+", 20, Color(1, 1, 1, 0.75))
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-5, -15)
	var help := _label(page, "A / D ROLL     W / S PITCH     Q / E YAW     SPACE / CTRL THROTTLE     R RESET", 10, MUTED)
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -34
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var assist := _button("TOGGLE ASSIST", LIGHT)
	assist.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	assist.position = Vector2(20, -56)
	assist.pressed.connect(func() -> void: drone.assists_enabled = not drone.assists_enabled)
	page.add_child(assist)
	if kind == "race":
		race_label = _label(page, "GATE 01 / %02d" % world.gates.size(), 14, ORANGE, true)
		race_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		race_label.position.y = 80

func _read_controls() -> Vector4:
	var selected_device := int(controller.get("device", -1))
	if Input.get_connected_joypads().has(selected_device):
		var channels: Dictionary = controller.get("channels", {})
		var values := Vector4.ZERO
		for i in range(CHANNELS.size()):
			var entry: Dictionary = channels.get(CHANNELS[i], {})
			var axis := int(entry.get("axis", -1))
			if axis < 0: continue
			var raw := Input.get_joy_axis(selected_device, axis)
			var normalized := _normalized_axis(raw, entry, i == 3)
			if entry.get("reversed", false): normalized = -normalized
			values[i] = clampf(normalized, 0.0, 1.0) if i == 3 else _deadzone(normalized, 0.035)
		return values
	return Vector4(
		(1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0),
		(1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0),
		(1.0 if Input.is_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_key_pressed(KEY_Q) else 0.0),
		clampf(0.48 + ((1.0 if Input.is_key_pressed(KEY_SPACE) else 0.0) - (1.0 if Input.is_key_pressed(KEY_CTRL) else 0.0)) * 0.5, 0.0, 1.0)
	)

func _update_gates() -> void:
	if world.gates.is_empty() or gate_index >= world.gates.size(): return
	var gate: Node3D = world.gates[gate_index]
	var local: Vector3 = gate.global_basis.inverse() * (drone.global_position - gate.global_position)
	if absf(local.x) < 1.75 and absf(local.y) < 1.25 and absf(local.z) < 1.4:
		gate_index += 1
		if gate_index >= world.gates.size():
			race_active = false
			_show_result(race_time, store.set_best_time(course_id, race_time))
		elif race_label != null:
			race_label.text = "GATE %02d / %02d" % [gate_index + 1, world.gates.size()]

func _show_result(elapsed: float, record: bool) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(dim)
	var box := _modal_box(dim, 480, 280)
	_label(box, "COURSE COMPLETE", 23, CYAN, true)
	_label(box, _time(elapsed), 36, WHITE, true)
	_label(box, "NEW LOCAL BEST" if record else "BEST  " + _time(store.best_time(course_id)), 11, ORANGE, true)
	var back := _button("RETURN TO MENU", LIGHT)
	back.pressed.connect(_show_home)
	box.add_child(back)

func _show_crash() -> void:
	if mode != "flight": return
	mode = "crashed"
	race_active = false
	drone.set_physics_process(false)
	var dim := ColorRect.new()
	dim.name = "CrashOverlay"
	dim.color = Color(0.01, 0.02, 0.03, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(dim)
	var box := _modal_box(dim, 420, 260)
	_label(box, "QUAD DOWN", 24, ORANGE, true)
	_label(box, "Reset and try the line again.", 13, MUTED)
	var reset := _button("RESET TO START", CYAN)
	reset.pressed.connect(_reset_session)
	box.add_child(reset)
	var exit := _button("RETURN TO MENU", LIGHT)
	exit.pressed.connect(_show_home)
	box.add_child(exit)

func _show_pause() -> void:
	if mode != "flight": return
	mode = "paused"
	drone.set_physics_process(false)
	drone.set_audio_paused(true)
	var dim := ColorRect.new()
	dim.name = "PauseOverlay"
	dim.color = Color(0.01, 0.02, 0.03, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(dim)
	var box := _modal_box(dim, 420, 300)
	_label(box, "FLIGHT PAUSED", 22, WHITE, true)
	var resume := _button("RESUME FLIGHT", CYAN)
	resume.pressed.connect(func() -> void:
		dim.queue_free()
		mode = "flight"
		drone.set_physics_process(true)
		drone.set_audio_paused(false)
	)
	box.add_child(resume)
	var reset := _button("RESET TO START", LIGHT)
	reset.pressed.connect(_reset_session)
	box.add_child(reset)
	var exit := _button("RETURN TO MENU", LIGHT)
	exit.pressed.connect(_show_home)
	box.add_child(exit)
	_unlock_mouse()

func _reset_session() -> void:
	if is_instance_valid(drone):
		drone.set_physics_process(true)
		drone.set_audio_paused(false)
		drone.reset_at(Vector3(0.0, 1.1, -1.0))
	if race_label != null:
		race_time = 0.0
		gate_index = 0
		race_active = true
		race_label.text = "GATE 01 / %02d" % world.gates.size()
	if page != null:
		var overlay := page.get_node_or_null("PauseOverlay")
		if overlay == null: overlay = page.get_node_or_null("CrashOverlay")
		if overlay != null: overlay.queue_free()
	mode = "flight"

func _radio_ready() -> bool:
	var device := int(controller.get("device", -1))
	var channels: Dictionary = controller.get("channels", {})
	return Input.get_connected_joypads().has(device) and channels.size() == 4

func _channel_map(key: String) -> Dictionary:
	var channels: Dictionary = controller.get("channels", {})
	var entry: Variant = channels.get(key, {})
	return entry if entry is Dictionary else {}

func _is_mapped(key: String) -> bool:
	return int(capture_maps.get(key, _channel_map(key)).get("axis", -1)) >= 0

func _is_reversed(key: String) -> bool:
	return bool(capture_maps.get(key, _channel_map(key)).get("reversed", false))

func _map_text(key: String) -> String:
	var entry: Dictionary = capture_maps.get(key, _channel_map(key))
	return "Not mapped" if int(entry.get("axis", -1)) < 0 else "Axis %d  ·  %s" % [entry.axis, "Reversed" if entry.get("reversed", false) else "Normal"]

func _deadzone(value: float, zone: float) -> float:
	return 0.0 if absf(value) < zone else signf(value) * (absf(value) - zone) / (1.0 - zone)

func _unlock_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _time(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	return "%02d:%06.3f" % [minutes, seconds - minutes * 60.0]

func _new_page() -> void:
	if page != null and is_instance_valid(page):
		page.queue_free()
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(page)

func _base_layout() -> VBoxContainer:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	page.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 17)
	margin.add_child(layout)
	return layout

func _page_header(parent: Control, title: String, subtitle: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	_label(row, title, 23, WHITE, true)
	var sub := _label(row, subtitle, 13, MUTED)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _card(parent: Control, width: float = 0.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	if width > 0.0:
		panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(PANEL, 14, Color(0.13, 0.19, 0.23), 1))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 17)
	margin.add_theme_constant_override("margin_bottom", 17)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 11)
	margin.add_child(content)
	return content

func _modal_box(parent: Control, width: float, height: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	panel.add_theme_stylebox_override("panel", _style(PANEL, 14, Color(0.15, 0.21, 0.26), 1))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	return content

func _label(parent: Control, text_value: String, size: int = 14, color: Color = WHITE, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
	parent.add_child(label)
	return label

func _button(text_value: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(142, 40)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_stylebox_override("normal", _style(LIGHT, 7, Color(0.15, 0.23, 0.27), 1))
	button.add_theme_stylebox_override("hover", _style(accent.darkened(0.4), 7, accent, 1))
	button.add_theme_stylebox_override("pressed", _style(accent.darkened(0.55), 7, accent, 2))
	return button

func _menu_button(parent: Control, title: String, subtitle: String, callback: Callable, accent: Color) -> void:
	var button := Button.new()
	button.text = title + "\n" + subtitle
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(390, 64)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_stylebox_override("normal", _style(PANEL, 8, Color(0.13, 0.19, 0.23), 1))
	button.add_theme_stylebox_override("hover", _style(LIGHT, 8, accent, 1))
	button.pressed.connect(callback)
	parent.add_child(button)

func _style(color: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	return style

func _spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)

func _update_calibration_meters() -> void:
	if page == null: return
	var channels: Dictionary = controller.get("channels", {})
	for channel in CHANNELS:
		var meter := page.find_child("Meter_" + channel, true, false) as ProgressBar
		if meter == null: continue
		var mapping: Dictionary = capture_maps.get(channel, channels.get(channel, {}))
		var axis := int(mapping.get("axis", -1))
		var value := 0.0
		if axis >= 0 and Input.get_connected_joypads().has(joy_device):
			value = Input.get_joy_axis(joy_device, axis)
			value = _normalized_axis(value, mapping, channel == "throttle")
			if mapping.get("reversed", false): value = -value
		meter.value = clampf(value, 0.0, 1.0) if channel == "throttle" else value

func _show_toast(message: String) -> void:
	if toast != null and is_instance_valid(toast): toast.queue_free()
	toast = _label(ui, message, 12, WHITE)
	toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toast.offset_top = -68
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_stylebox_override("normal", _style(PANEL, 6, CYAN, 1))
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(toast): toast.queue_free()
	)
