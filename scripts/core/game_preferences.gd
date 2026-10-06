extends RefCounted

const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var master_volume: float = 80.0
var window_preset: int = 1
var fullscreen: bool = false
var reduced_crt: bool = false
var last_error: String = ""

func load_from(path: String) -> bool:
	last_error = ""
	if not FileAccess.file_exists(path):
		return true
	var config := ConfigFile.new()
	if config.load(path) != OK:
		last_error = "设置文件无法读取，已保留当前配置。"
		return false
	var volume: Variant = config.get_value("settings", "master_volume", 80.0)
	var preset: Variant = config.get_value("settings", "window_preset", 1)
	var full: Variant = config.get_value("settings", "fullscreen", false)
	var reduced: Variant = config.get_value("settings", "reduced_crt", false)
	if config.get_value("settings", "version", 0) != 1 or not [TYPE_INT, TYPE_FLOAT].has(typeof(volume)) or typeof(preset) != TYPE_INT or typeof(full) != TYPE_BOOL or typeof(reduced) != TYPE_BOOL:
		last_error = "设置格式或版本无效，已保留当前配置。"
		return false
	if not is_finite(float(volume)) or float(volume) < 0 or float(volume) > 100 or preset < 0 or preset >= WINDOW_SIZES.size():
		last_error = "设置数值超出范围，已保留当前配置。"
		return false
	master_volume = volume
	window_preset = preset
	fullscreen = full
	reduced_crt = reduced
	return true

func save_to(path: String) -> bool:
	last_error = ""
	if not is_finite(master_volume) or master_volume < 0 or master_volume > 100 or window_preset < 0 or window_preset >= WINDOW_SIZES.size():
		last_error = "设置数值无效，未写入。"
		return false
	var config := ConfigFile.new()
	config.set_value("settings", "version", 1)
	config.set_value("settings", "master_volume", master_volume)
	config.set_value("settings", "window_preset", window_preset)
	config.set_value("settings", "fullscreen", fullscreen)
	config.set_value("settings", "reduced_crt", reduced_crt)
	var pending := path + ".tmp"
	if config.save(pending) != OK or DirAccess.rename_absolute(pending, path) != OK:
		last_error = "设置保存失败，原配置未替换。请检查存储权限。"
		return false
	return true

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume == 0)
	RenderingServer.global_shader_parameter_set("crt_effect_strength", 0.25 if reduced_crt else 1.0)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		if not fullscreen:
			DisplayServer.window_set_size(WINDOW_SIZES[window_preset])
