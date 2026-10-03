class_name ProfileStore
extends RefCounted

const SAVE_PATH := "user://rotorline.cfg"
const DEFAULT_FLIGHT := {
	"name": "Balanced 5 inch",
	"roll_rate": 720.0,
	"pitch_rate": 720.0,
	"yaw_rate": 540.0,
	"thrust": 22.0,
	"camera_angle": 25.0,
}
const DEFAULT_SETTINGS := {
	"master_volume": 0.8,
	"music_volume": 0.55,
	"effects_volume": 0.8,
	"quality": "High",
	"frame_cap": 60,
	"resolution": "1280x720",
	"fullscreen": false,
}

var data: ConfigFile = ConfigFile.new()
var load_warning := ""

func load_data() -> void:
	var err := data.load(SAVE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		load_warning = "Settings could not be read. Defaults are active; saving will replace the damaged file."
	if not data.has_section("settings"):
		for key in DEFAULT_SETTINGS:
			data.set_value("settings", key, DEFAULT_SETTINGS[key])
	if not data.has_section("flight"):
		for key in DEFAULT_FLIGHT:
			data.set_value("flight", key, DEFAULT_FLIGHT[key])
	if not data.has_section("controller"):
		data.set_value("controller", "name", "")
		data.set_value("controller", "device", -1)
		data.set_value("controller", "channels", {"roll": {}, "pitch": {}, "yaw": {}, "throttle": {}})
		data.set_value("controller", "active_profile", "")
	if not data.has_section("controller_profiles"):
		data.set_value("controller_profiles", "_initialized", true)
	if not data.has_section("records"):
		data.set_value("records", "best_times", {})

func settings() -> Dictionary:
	var result := DEFAULT_SETTINGS.duplicate(true)
	for key in result:
		result[key] = data.get_value("settings", key, result[key])
	return result

func flight() -> Dictionary:
	var result := DEFAULT_FLIGHT.duplicate(true)
	for key in result:
		result[key] = data.get_value("flight", key, result[key])
	return result

func controller() -> Dictionary:
	var profiles := controller_profiles()
	var active_id := str(data.get_value("controller", "active_profile", ""))
	if profiles.has(active_id):
		return profiles[active_id]
	return {
		"name": data.get_value("controller", "name", ""),
		"device": data.get_value("controller", "device", -1),
		"channels": data.get_value("controller", "channels", {"roll": {}, "pitch": {}, "yaw": {}, "throttle": {}}),
		"profile_id": "",
	}

func controller_profiles() -> Dictionary:
	var profiles: Dictionary = {}
	for key in data.get_section_keys("controller_profiles"):
		if key == "_initialized": continue
		var value: Variant = data.get_value("controller_profiles", key, {})
		if value is Dictionary: profiles[key] = value
	return profiles

func save_settings(settings_value: Dictionary) -> Error:
	for key in settings_value:
		data.set_value("settings", key, settings_value[key])
	return data.save(SAVE_PATH)

func save_flight(flight_value: Dictionary) -> Error:
	for key in flight_value:
		data.set_value("flight", key, flight_value[key])
	return data.save(SAVE_PATH)

func save_controller(controller_value: Dictionary) -> Error:
	var profile_id := str(controller_value.get("profile_id", controller_value.get("name", "Radio profile"))).strip_edges()
	if profile_id.is_empty(): profile_id = "Radio profile"
	var saved_profile := controller_value.duplicate(true)
	saved_profile["profile_id"] = profile_id
	saved_profile["name"] = profile_id
	data.set_value("controller_profiles", profile_id, saved_profile)
	data.set_value("controller", "active_profile", profile_id)
	data.set_value("controller", "name", controller_value.get("name", ""))
	data.set_value("controller", "device", controller_value.get("device", -1))
	data.set_value("controller", "channels", controller_value.get("channels", {}))
	return data.save(SAVE_PATH)

func best_time(course_id: String) -> float:
	var records: Dictionary = data.get_value("records", "best_times", {})
	return float(records.get(course_id, 0.0))

func set_best_time(course_id: String, time_seconds: float) -> bool:
	var records: Dictionary = data.get_value("records", "best_times", {})
	var old_time := float(records.get(course_id, 0.0))
	if old_time > 0.0 and old_time <= time_seconds:
		return false
	records[course_id] = time_seconds
	data.set_value("records", "best_times", records)
	data.save(SAVE_PATH)
	return true
