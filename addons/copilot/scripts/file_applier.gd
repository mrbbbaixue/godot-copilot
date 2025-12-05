@tool
class_name FileApplier
## Handles applying diffs and code blocks to files

const DiffUtils = preload("res://addons/copilot/scripts/diff_utils.gd")

signal file_applied(file_path: String, success: bool, message: String)
signal auto_apply_started
signal auto_apply_finished

var _plugin: EditorPlugin
var _current_script_path := ""

## Initialize with the main plugin instance
func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin

## Set the current script path for editor updates
func set_current_script_path(path: String) -> void:
	_current_script_path = path

## Apply a diff to a file
func apply_diff(file_path: String, diff_text: String) -> Dictionary:
	if not _plugin:
		return {"success": false, "error": "Plugin not initialized."}

	# Read original file content
	var original_content = _read_file_content(file_path)
	if original_content.is_empty() and not (diff_text.contains("--- /dev/null") or diff_text.contains("--- a/dev/null")):
		return {"success": false, "error": "Cannot read file: %s" % file_path}

	# Apply the diff
	var result := DiffUtils.apply_diff(original_content, diff_text)

	if result["success"]:
		# Write the modified content back to the file
		if _write_file_content(file_path, result["code"]):
			_update_editor_if_current(file_path, result["code"])
			file_applied.emit(file_path, true, "✅ Diff applied to %s" % file_path)
		else:
			result["success"] = false
			result["error"] = "Failed to write to file: %s" % file_path
			file_applied.emit(file_path, false, "❌ Failed to write to file: %s" % file_path)

	return result

## Apply code to a file
func apply_code(file_path: String, code: String) -> Dictionary:
	if not _plugin:
		return {"success": false, "error": "Plugin not initialized."}

	# Write the code to the file
	if _write_file_content(file_path, code):
		_update_editor_if_current(file_path, code)
		file_applied.emit(file_path, true, "✅ Code applied to %s" % file_path)
		return {"success": true}
	else:
		var error = "❌ Failed to write to file: %s" % file_path
		file_applied.emit(file_path, false, error)
		return {"success": false, "error": error}

## Auto-apply changes from AI response
func auto_apply_changes(content: String) -> void:
	if not _plugin:
		return

	auto_apply_started.emit()

	# Extract diffs and code blocks from the content
	var diffs := DiffUtils.extract_all_diffs(content)
	var code_blocks := DiffUtils.extract_code_blocks_with_paths(content)

	# Apply all diffs
	for diff_info: Dictionary in diffs:
		var file_path: String = diff_info["path"]
		var diff_text: String = diff_info["diff"]
		var is_new_file: bool = diff_info["is_new_file"]

		# Read original file content (if not a new file)
		var original_content := ""
		if not is_new_file:
			original_content = _read_file_content(file_path)
			if original_content.is_empty():
				file_applied.emit(file_path, false, "⚠ Skipping diff for %s (cannot read file)" % file_path)
				continue

		# Apply the diff
		var result := DiffUtils.apply_diff(original_content, diff_text)

		if result["success"]:
			if _write_file_content(file_path, result["code"]):
				_update_editor_if_current(file_path, result["code"])
				file_applied.emit(file_path, true, "✅ Auto-applied diff to %s" % file_path)
			else:
				file_applied.emit(file_path, false, "❌ Failed to write to file: %s" % file_path)
		else:
			file_applied.emit(file_path, false, "❌ Failed to auto-apply diff to %s: %s" % [file_path, result["error"]])

	# Apply all code blocks
	for block_info: Dictionary in code_blocks:
		var file_path: String = block_info["path"]
		var code: String = block_info["code"]

		if _write_file_content(file_path, code):
			_update_editor_if_current(file_path, code)
			file_applied.emit(file_path, true, "✅ Auto-applied code to %s" % file_path)
		else:
			file_applied.emit(file_path, false, "❌ Failed to write to file: %s" % file_path)

	auto_apply_finished.emit()

# Private helper methods
func _read_file_content(file_path: String) -> String:
	if _plugin:
		return _plugin.read_file_content(file_path)
	return ""

func _write_file_content(file_path: String, content: String) -> bool:
	if _plugin:
		return _plugin.write_file_content(file_path, content)
	return false

func _update_editor_if_current(file_path: String, code: String) -> void:
	if _plugin and (file_path == _current_script_path or file_path == _plugin.get_current_script_path()):
		_plugin.set_current_code(code)