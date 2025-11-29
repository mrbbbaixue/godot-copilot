@tool
extends EditorPlugin

const CopilotDock = preload("res://addons/godot_copilot/copilot_dock.gd")
const SettingsDialog = preload("res://addons/godot_copilot/settings_dialog.gd")

var dock: Control
var settings_dialog: AcceptDialog

# Settings storage
var config := ConfigFile.new()
var config_path := "user://godot_copilot.cfg"


func _enter_tree() -> void:
	# Load configuration
	_load_config()
	
	# Create and add the dock to the right side
	dock = CopilotDock.new()
	dock.name = "Copilot"
	dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# Create settings dialog
	settings_dialog = SettingsDialog.new()
	settings_dialog.plugin = self
	get_editor_interface().get_base_control().add_child(settings_dialog)


func _exit_tree() -> void:
	# Clean up dock
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	
	# Clean up settings dialog
	if settings_dialog:
		settings_dialog.queue_free()
		settings_dialog = null


func _load_config() -> void:
	if config.load(config_path) != OK:
		# Default settings
		config.set_value("api", "base_url", "https://api.openai.com/v1")
		config.set_value("api", "api_key", "")
		config.set_value("api", "model", "gpt-4o")
		config.save(config_path)


func get_setting(section: String, key: String) -> Variant:
	return config.get_value(section, key, "")


func set_setting(section: String, key: String, value: Variant) -> void:
	config.set_value(section, key, value)
	config.save(config_path)


func show_settings() -> void:
	if settings_dialog:
		settings_dialog.popup_centered(Vector2i(500, 300))


func get_current_script_editor() -> ScriptEditorBase:
	var script_editor := get_editor_interface().get_script_editor()
	if script_editor:
		return script_editor.get_current_editor()
	return null


func get_current_script() -> Script:
	var script_editor := get_editor_interface().get_script_editor()
	if script_editor:
		return script_editor.get_current_script()
	return null


func get_current_code() -> String:
	var editor := get_current_script_editor()
	if editor:
		var code_edit := _find_code_edit(editor)
		if code_edit:
			return code_edit.text
	return ""


func set_current_code(code: String) -> void:
	var editor := get_current_script_editor()
	if editor:
		var code_edit := _find_code_edit(editor)
		if code_edit:
			code_edit.text = code


func _find_code_edit(node: Node) -> CodeEdit:
	if node is CodeEdit:
		return node
	for child in node.get_children():
		var result := _find_code_edit(child)
		if result:
			return result
	return null
