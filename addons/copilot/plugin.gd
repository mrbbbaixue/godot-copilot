@tool
extends EditorPlugin

const CopilotDock = preload("res://addons/copilot/copilot_dock.gd")
const SettingsDialog = preload("res://addons/copilot/settings_dialog.gd")

var dock: Control
var settings_dialog: AcceptDialog

# Settings storage
var config := ConfigFile.new()
var config_path := "user://copilot.cfg"


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
		config.set_value("mode", "full_code_mode", false)  # Default: diff mode (not full code)
		config.save(config_path)


func get_setting(section: String, key: String) -> Variant:
	var default_value: Variant = ""
	if section == "mode" and key == "full_code_mode":
		default_value = false
	return config.get_value(section, key, default_value)


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


func get_current_script_path() -> String:
	var script := get_current_script()
	if script:
		return script.resource_path
	return ""


## Find the scene file (.tscn) that references the current script
func find_scene_for_script(script_path: String) -> String:
	if script_path.is_empty():
		return ""
	
	# Search for .tscn files in the project that reference this script
	var scenes := _find_all_scenes("res://")
	
	for scene_path in scenes:
		var content := _read_file_content(scene_path)
		if content.contains(script_path):
			return scene_path
	
	return ""


## Read the content of a scene file (.tscn)
func read_scene_content(scene_path: String) -> String:
	if scene_path.is_empty():
		return ""
	return _read_file_content(scene_path)


## Find all .tscn files recursively in a directory
func _find_all_scenes(dir_path: String) -> Array:
	var scenes := []
	var dir := DirAccess.open(dir_path)
	
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		
		while file_name != "":
			if file_name.begins_with("."):
				file_name = dir.get_next()
				continue
			
			var full_path := dir_path.path_join(file_name)
			
			if dir.current_is_dir():
				# Skip addons folder to avoid searching plugin files
				if file_name != "addons":
					scenes.append_array(_find_all_scenes(full_path))
			elif file_name.ends_with(".tscn"):
				scenes.append(full_path)
			
			file_name = dir.get_next()
		
		dir.list_dir_end()
	
	return scenes


## Read file content as string
func _read_file_content(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file:
		var content := file.get_as_text()
		file.close()
		return content
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
