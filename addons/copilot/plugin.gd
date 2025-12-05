@tool
extends EditorPlugin

const CopilotDock = preload("res://addons/copilot/scripts/copilot_dock.gd")
const SettingsDialogScene = preload("res://addons/copilot/scenes/settings_dialog.tscn")

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
	settings_dialog = SettingsDialogScene.instantiate()
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
		config.set_value("mode", "auto_apply_mode", false)  # Default: manual apply mode
		config.save(config_path)


func get_setting(section: String, key: String) -> Variant:
	var default_value: Variant = ""
	if section == "mode":
		match key:
			"auto_apply_mode":
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


## Get the currently open scene path
func get_current_scene_path() -> String:
	var edited_scene_root := get_editor_interface().get_edited_scene_root()
	if edited_scene_root and edited_scene_root.scene_file_path:
		return edited_scene_root.scene_file_path
	return ""


## Get the file tree structure of the project (excluding addons folder)
func get_file_tree(base_path: String = "res://", max_depth: int = 4) -> String:
	return _build_file_tree(base_path, 0, max_depth)


func _build_file_tree(dir_path: String, depth: int, max_depth: int) -> String:
	if depth >= max_depth:
		return ""
	
	var result := ""
	var dir := DirAccess.open(dir_path)
	
	if not dir:
		return ""
	
	var indent := "  ".repeat(depth)
	var dirs := []
	var files := []
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		
		# Skip addons folder and .import folder
		if file_name == "addons" or file_name == ".import" or file_name == ".godot":
			file_name = dir.get_next()
			continue
		
		var full_path := dir_path.path_join(file_name)
		
		if dir.current_is_dir():
			dirs.append(file_name)
		else:
			# Only include relevant files
			if _is_relevant_file(file_name):
				files.append(file_name)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# Sort for consistent output
	dirs.sort()
	files.sort()
	
	# Add directories first
	for d in dirs:
		result += indent + "📁 " + d + "/\n"
		result += _build_file_tree(dir_path.path_join(d), depth + 1, max_depth)
	
	# Then add files
	for f in files:
		result += indent + "📄 " + f + "\n"
	
	return result


func _is_relevant_file(file_name: String) -> bool:
	var extensions := [".gd", ".tscn", ".tres", ".cfg", ".json", ".txt", ".md", ".shader", ".gdshader"]
	for ext in extensions:
		if file_name.ends_with(ext):
			return true
	return false


## Read file content by path
func read_file_content(file_path: String) -> String:
	return _read_file_content(file_path)


## Write content to a file
func write_file_content(file_path: String, content: String) -> bool:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		return true
	return false
