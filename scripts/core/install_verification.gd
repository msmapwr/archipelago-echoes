extends RefCounted

# Read-only installation diagnostic, available in the shipped runtime.
# No gameplay command, settings write, resource grant or persistent mutation.
static func validate(shell: Control) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not OS.has_feature("release") or OS.has_feature("editor"): errors.append("Expected a release export template")
	if not shell.startup_failure.is_empty(): errors.append(shell.startup_failure)
	if shell.session_stage != "menu" or not shell.get_tree().paused: errors.append("Menu must keep simulation paused")
	if not shell.get_node("StartButton").visible: errors.append("Start control missing")
	for path in DataManager.DEFINITION_PATHS:
		if ResourceLoader.load(path) == null: errors.append("Missing packed definition: " + path)
	for path in ["res://scenes/main/crt_main.tscn", "res://scenes/unit_showcase.tscn", "res://shaders/crt_glass.gdshader", "res://shaders/ppi_phosphor.gdshader"]:
		if not ResourceLoader.exists(path): errors.append("Missing packed runtime resource: " + path)
	for path in ["res://tests/p0_smoke.gd", "res://tools/dev.py", "res://docs/plan.md", "res://AGENTS.md"]:
		if FileAccess.file_exists(path) or ResourceLoader.exists(path): errors.append("Development file included in export: " + path)
	return errors
