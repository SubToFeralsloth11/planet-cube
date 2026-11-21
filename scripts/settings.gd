extends Node
## Player settings (autoload "Cfg"): audio levels, controls, camera and display. Saved to user://settings.cfg.

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"master": 0.9, "music": 0.6, "sfx": 0.9,
	"sens": 1.0, "invert_y": false, "fov": 78.0, "view_bob": true,
	"fullscreen": false, "show_fps": false,
}

var values := DEFAULTS.duplicate()


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in DEFAULTS:
			values[k] = cf.get_value("settings", k, DEFAULTS[k])
	apply()


func get_v(key: String):
	return values.get(key, DEFAULTS.get(key))


func set_v(key: String, v) -> void:
	values[key] = v
	apply()
	save()


func sens_mult() -> float:
	return float(values["sens"])


func save() -> void:
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("settings", k, values[k])
	cf.save(PATH)


func apply() -> void:
	_bus("Master", values["master"])
	_bus("Music", values["music"])
	_bus("SFX", values["sfx"])
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_MAXIMIZED
		var cur := DisplayServer.window_get_mode()
		var is_full := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if values["fullscreen"] != is_full:
			DisplayServer.window_set_mode(want)


func _bus(name: String, lin: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.0001)))
	AudioServer.set_bus_mute(i, lin <= 0.001)
