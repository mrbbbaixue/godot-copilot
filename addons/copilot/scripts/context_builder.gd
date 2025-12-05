@tool
class_name ContextBuilder
## Builds automatic context strings from the current project state

signal context_updated(context_string: String)

var _plugin: EditorPlugin
var _current_script_path := ""

## Initialize with the main plugin instance
func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin

## Build the automatic context string with current scene, code, and file tree
func build_auto_context() -> String:
	if not _plugin:
		return ""

	var context_parts := []

	# 1. File tree structure
	var file_tree = _get_file_tree()
	if not file_tree.is_empty():
		context_parts.append("## Project File Structure:\n```\n%s```" % file_tree)

	# 2. Current open scene
	var scene_path = _get_current_scene_path()
	if not scene_path.is_empty():
		var scene_content = _read_scene_content(scene_path)
		if not scene_content.is_empty():
			context_parts.append("## Currently Open Scene (%s):\n```tscn\n%s\n```" % [scene_path, scene_content])

	# 3. Current script in code editor
	var script = _get_current_script()
	var code = _get_current_code()
	if script and not code.is_empty():
		var script_path = script.resource_path
		_current_script_path = script_path
		context_parts.append("## Currently Open Script (%s):\n```gdscript\n%s\n```" % [script_path, code])

	if context_parts.is_empty():
		return ""

	return "# Current Project Context\n\n" + "\n\n".join(context_parts)

## Get current script path (cached from last context build)
func get_current_script_path() -> String:
	return _current_script_path

## Clear cached script path (e.g., when chat is cleared)
func clear_cached_path() -> void:
	_current_script_path = ""

# Private helper methods
func _get_file_tree() -> String:
	if _plugin:
		return _plugin.get_file_tree()
	return ""

func _get_current_scene_path() -> String:
	if _plugin:
		return _plugin.get_current_scene_path()
	return ""

func _read_scene_content(scene_path: String) -> String:
	if _plugin:
		return _plugin.read_scene_content(scene_path)
	return ""

func _get_current_script() -> Script:
	if _plugin:
		return _plugin.get_current_script()
	return null

func _get_current_code() -> String:
	if _plugin:
		return _plugin.get_current_code()
	return ""